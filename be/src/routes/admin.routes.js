const express = require('express');

const AuditLog = require('../models/AuditLog');
const AppSetting = require('../models/AppSetting');
const Chat = require('../models/Chat');
const Comment = require('../models/Comment');
const Friendship = require('../models/Friendship');
const Group = require('../models/Group');
const GroupMember = require('../models/GroupMember');
const MediaAsset = require('../models/MediaAsset');
const Message = require('../models/Message');
const Notification = require('../models/Notification');
const Post = require('../models/Post');
const Report = require('../models/Report');
const FlaggedContent = require('../models/FlaggedContent');
const SupportMessage = require('../models/SupportMessage');
const SupportThread = require('../models/SupportThread');
const User = require('../models/User');
const asyncHandler = require('../utils/async-handler');
const { requireAuth, requireRole } = require('../middlewares/auth');
const { isValidObjectId } = require('../middlewares/object-id');
const { emitToUser, emitGlobal } = require('../realtime/socket');
const { toPublicUser } = require('../utils/public-user');
const { detachMediaFromSource } = require('../services/media-attachment');
const { destroyMediaAsset } = require('../services/media-storage');
const {
  sendNotification,
  broadcastNotification,
  NOTIFICATION_TYPES,
} = require('../services/notification-service');

const router = express.Router();

router.use(requireAuth);
router.use(requireRole('MODERATOR', 'ADMIN'));

const DEFAULT_SAFETY_CONFIG = {
  safeSearchDefault: true,
  autoHideHighRisk: true,
  rules: [
    'No bullying, threats or insulting language.',
    'Do not share phone numbers, home address or school details.',
    'Keep posts safe for ages 7 to 14.',
    'Stop interaction when someone asks for space.',
  ],
};

function nowMinus(ms) {
  return new Date(Date.now() - ms);
}

function readPostRisk(post) {
  const content = `${post.content || ''}`.toLowerCase();
  if (/school|address|phone|private|secret/.test(content)) {
    return 'HIGH';
  }
  if (post.status === 'HIDDEN') {
    return 'MEDIUM';
  }
  return 'LOW';
}

function readMessageSeverity(message) {
  const content = `${message.content || ''}`.toLowerCase();
  if (/school|address|phone|private|secret|where do you live/.test(content)) {
    return 'HIGH';
  }
  if (/stop|hate|stupid|spam|link/.test(content)) {
    return 'MEDIUM';
  }
  return 'LOW';
}

async function logAdminAction(req, action, targetType = '', targetId = '', metadata = {}) {
  await AuditLog.create({
    actorId: req.user.id,
    actorUsername: req.user.username,
    action,
    targetType,
    targetId,
    metadata,
  });
}

async function buildBadgeCatalog() {
  const [postCount, friendPairCount, groupMemberCount, reportCount] = await Promise.all([
    Post.countDocuments({ status: 'PUBLISHED' }),
    Friendship.countDocuments({}),
    GroupMember.countDocuments({ status: 'ACTIVE' }),
    Report.countDocuments({}),
  ]);

  return [
    {
      id: 'first-post',
      name: 'First Post',
      rule: 'Create 1 post',
      enabled: true,
      earned: postCount,
    },
    {
      id: 'friendly',
      name: 'Friendly',
      rule: 'Make 3 friends',
      enabled: true,
      earned: friendPairCount,
    },
    {
      id: 'group-explorer',
      name: 'Group Explorer',
      rule: 'Join a group',
      enabled: true,
      earned: groupMemberCount,
    },
    {
      id: 'safety-helper',
      name: 'Safety Helper',
      rule: 'Submit a safety report',
      enabled: true,
      earned: reportCount,
    },
  ];
}

function serializeAdminMediaAsset(asset) {
  const owner =
    asset.ownerId && typeof asset.ownerId === 'object'
      ? asset.ownerId
      : null;

  return {
    id: asset._id.toString(),
    owner: owner?.displayName || owner?.username || '',
    ownerId: owner?._id?.toString() || asset.ownerId?.toString() || '',
    source: asset.sourceType,
    sourceType: asset.sourceType,
    sourceId: asset.sourceId?.toString() || '',
    url: asset.secureUrl,
    resourceType: asset.resourceType,
    status: asset.status,
    moderation: asset.moderation || {},
    createdAt: asset.createdAt,
  };
}

/**
 * Build the "highest priority reports" feed for the admin dashboard.
 *
 * Strategy:
 *  1. Pull the 20 most urgent unresolved reports and use them to find
 *     every distinct target that has been reported. This naturally
 *     dedupes the queue — five users reporting the same post collapse
 *     into a single row showing the duplicate count, the highest
 *     urgency, and the most recent report.
 *  2. Resolve a tiny preview of each target (post text / comment text /
 *     username of a reported user) so the moderator can decide without
 *     a click-through.
 *  3. Populate the most recent reporter so the UI can show "flagged by
 *     Alice 2m ago" out of the box.
 */
async function buildTopReports() {
  const recent = await Report.find({ status: { $in: ['PENDING', 'REVIEWING'] } })
    .sort({ urgency: -1, createdAt: -1 })
    .limit(20)
    .populate('reporterId', 'displayName username avatarUrl')
    .populate('targetAuthorId', 'displayName username avatarUrl');

  if (recent.length === 0) {
    return [];
  }

  // Group reports by (targetType, targetId).
  const groups = new Map();
  for (const report of recent) {
    const key = `${report.targetType}:${report.targetId}`;
    const existing = groups.get(key);
    if (existing) {
      existing.reports.push(report);
      if (report.urgency > existing.urgency) {
        existing.urgency = report.urgency;
      }
      if (report.createdAt > existing.lastReportedAt) {
        existing.lastReportedAt = report.createdAt;
        existing.lastReporter = report.reporterId;
      }
    } else {
      groups.set(key, {
        // `source` distinguishes a real user report from an
        // auto-flagged blocked attempt. The dashboard renders the two
        // very differently — for AUTO_MODERATION we never want to
        // show "reporter" because the reporter *is* the system.
        source: report.source,
        targetType: report.targetType,
        targetId: report.targetId,
        category: report.category,
        urgency: report.urgency,
        reports: [report],
        // Snapshot the content the first time we see this group so
        // we always have something to show, even if every report in
        // the group was created from the same auto-flag.
        targetContent: report.targetContent || '',
        targetAuthor: report.targetAuthorId,
        lastReportedAt: report.createdAt,
        lastReporter: report.reporterId,
      });
    }
  }

  // Some targetId values are not valid ObjectIds (e.g. moderation
  // pipeline stores synthetic ids like "blocked-post:<id>:<ts>"). Skip
  // them so a stray string does not blow up the $in query.
  const validId = (value) => isValidObjectId(value);

  const targetKeys = [...groups.keys()];
  const postIds = targetKeys
    .map((k) => groups.get(k))
    .filter((g) => g.targetType === 'POST' && validId(g.targetId))
    .map((g) => g.targetId);
  const commentIds = targetKeys
    .map((k) => groups.get(k))
    .filter((g) => g.targetType === 'COMMENT' && validId(g.targetId))
    .map((g) => g.targetId);
  const userIds = targetKeys
    .map((k) => groups.get(k))
    .filter((g) => g.targetType === 'USER' && validId(g.targetId))
    .map((g) => g.targetId);

  const [posts, comments, users] = await Promise.all([
    postIds.length
      ? Post.find({ _id: { $in: postIds } }).select(
          '_id content authorSnapshot status',
        )
      : [],
    commentIds.length
      ? Comment.find({ _id: { $in: commentIds } }).select(
          '_id content authorSnapshot status',
        )
      : [],
    userIds.length
      ? User.find({ _id: { $in: userIds } }).select(
          '_id displayName username avatarUrl',
        )
      : [],
  ]);

  // Many targetIds are synthetic strings from the moderation pipeline
  // (e.g. "blocked-message:<chatId>:<userId>:<ts>"). We still want to
  // show the offending user on the dashboard, so collect those userIds
  // and look them up in a single round trip.
  const blockedUserIds = targetKeys
    .map((k) => groups.get(k))
    .filter((g) => g.targetId && g.targetId.startsWith('blocked-') && isValidObjectId(parseBlockedTarget(g.targetId)?.userId))
    .map((g) => parseBlockedTarget(g.targetId).userId);

  const blockedUsers = blockedUserIds.length
    ? await User.find({ _id: { $in: blockedUserIds } }).select(
        '_id displayName username avatarUrl',
      )
    : [];
  const blockedUserById = new Map(
    blockedUsers.map((u) => [u._id.toString(), u]),
  );

  const postById = new Map(posts.map((p) => [p._id.toString(), p]));
  const commentById = new Map(comments.map((c) => [c._id.toString(), c]));
  const userById = new Map(users.map((u) => [u._id.toString(), u]));

  const items = [...groups.values()].map((group) => {
    const report = group.reports[0];
    const reporter = group.lastReporter;
    const reporterSafe = reporter && typeof reporter === 'object'
      ? {
          id: reporter._id.toString(),
          displayName: reporter.displayName,
          username: reporter.username,
          avatarUrl: reporter.avatarUrl || '',
        }
      : null;

    // The user who *wrote* the offending content. For AUTO_MODERATION
    // this is the same person as reporterId by design (the system is
    // reporting on their behalf), so we still surface it as "author".
    const authorSafe = group.targetAuthor && typeof group.targetAuthor === 'object'
      ? {
          id: group.targetAuthor._id.toString(),
          displayName: group.targetAuthor.displayName || group.targetAuthor.username,
          username: group.targetAuthor.username,
          avatarUrl: group.targetAuthor.avatarUrl || '',
        }
      : null;

    // For synthetic (blocked-*) targets, look up the offending user
    // by id and pull a content snippet from the report details.
    const blocked = parseBlockedTarget(group.targetId);
    const blockedUser = blocked?.userId
      ? blockedUserById.get(blocked.userId)
      : null;

    // Prefer the persisted snapshot from the Report itself, then
    // fall back to the regex snippet parsed out of `details`. This is
    // what makes the dashboard show the actual message even though
    // the Message row was never saved.
    const persistedSnippet = (group.targetContent || '').trim();
    const detailsSnippet = extractBlockedSnippet(report.details);
    const snippet = persistedSnippet || detailsSnippet;

    const targetPreview = describeReportTarget(
      group.targetType,
      group.targetId,
      {
        postById,
        commentById,
        userById,
        snippet,
        authorDisplayName:
          authorSafe?.displayName ||
          (blockedUser ? blockedUser.displayName || blockedUser.username : ''),
      },
    );

    return {
      id: report._id.toString(),
      // Distinguishes user reports from auto-flagged attempts so the
      // admin UI can label them correctly.
      source: group.source || 'USER',
      targetType: group.targetType,
      targetId: group.targetId,
      category: group.category,
      urgency: group.urgency,
      status: report.status,
      details: report.details || '',
      duplicateCount: group.reports.length,
      lastReportedAt: group.lastReportedAt,
      // `reporter` is the actual reporter (a user, or the system). For
      // AUTO_MODERATION this is effectively the system, so admins can
      // tell it apart from a real user report at a glance.
      reporter: reporterSafe,
      // `author` is the person who wrote the offending content. This
      // is the field admins actually care about for taking action.
      author: authorSafe,
      target: targetPreview,
    };
  });

  // Sort by (urgency desc, lastReportedAt desc) so the freshest,
  // most-urgent cluster is at the top.
  items.sort((a, b) => {
    if (b.urgency !== a.urgency) {
      return b.urgency - a.urgency;
    }
    return new Date(b.lastReportedAt) - new Date(a.lastReportedAt);
  });

  return items.slice(0, 5);
}

function describeReportTarget(targetType, targetId, lookups) {
  if (targetType === 'POST' && lookups.postById.has(targetId)) {
    const post = lookups.postById.get(targetId);
    return {
      kind: 'POST',
      id: targetId,
      content: post.content,
      status: post.status,
      author: post.authorSnapshot?.displayName || post.authorSnapshot?.username || '',
    };
  }
  if (targetType === 'COMMENT' && lookups.commentById.has(targetId)) {
    const comment = lookups.commentById.get(targetId);
    return {
      kind: 'COMMENT',
      id: targetId,
      content: comment.content,
      author: comment.authorSnapshot?.displayName || comment.authorSnapshot?.username || '',
    };
  }
  if (targetType === 'USER' && lookups.userById.has(targetId)) {
    const user = lookups.userById.get(targetId);
    return {
      kind: 'USER',
      id: targetId,
      displayName: user.displayName,
      username: user.username,
      avatarUrl: user.avatarUrl || '',
    };
  }
  // The moderation pipeline stores synthetic ids like
  // "blocked-message:<chatId>:<userId>:<ts>" because the offending
  // content was never saved. Surface what we can: a kind label, the
  // raw id, and a snippet of the offending content captured at the
  // time of blocking (lookups.snippet is filled by the caller).
  return {
    kind: targetType,
    id: targetId,
    content: lookups.snippet || '',
    author: lookups.authorDisplayName || '',
    blocked: true,
  };
}

/**
 * Parse the synthetic id produced by the moderation pipeline so the
 * admin UI can link the report to the original chat / post. The
 * original content is lost (it was blocked before save) but the id
 * itself is enough to find the user who tried to post it.
 *
 * Format: blocked-<TYPE>:<id1>:<id2>:<ts>
 *   - blocked-post:<userId>:<ts>
 *   - blocked-comment:<postId>:<userId>:<ts>
 *   - blocked-message:<chatId>:<userId>:<ts>
 */
function parseBlockedTarget(targetId) {
  if (!targetId || !targetId.startsWith('blocked-')) {
    return null;
  }
  const parts = targetId.split(':');
  if (parts.length < 3) {
    return { kind: 'BLOCKED', raw: targetId };
  }
  const kind = parts[0].replace('blocked-', '').toUpperCase();
  if (kind === 'POST') {
    return { kind, userId: parts[1], raw: targetId };
  }
  if (kind === 'COMMENT' || kind === 'MESSAGE') {
    return { kind, relatedId: parts[1], userId: parts[2], raw: targetId };
  }
  return { kind, raw: targetId };
}

/**
 * Pull the "Content preview: ..." fragment out of a Report.details
 * string. The moderation service stores the offending snippet there
 * so the admin still has *something* to act on, even when the post /
 * message itself was never persisted.
 */
function extractBlockedSnippet(details) {
  if (!details || typeof details !== 'string') {
    return '';
  }
  const match = details.match(/Content preview:\s*(.+)$/);
  return match ? match[1].trim() : '';
}

/**
 * Build the "flagged content" feed for the admin dashboard.
 *
 * Reads straight from the FlaggedContent collection. Each row is one
 * piece of content that has been flagged (by NSFWJS, the keyword
 * filter, a user report, etc.) — the source of truth for what moderators
 * should look at next. Each row carries:
 *   - the flag itself (who, when, why, score)
 *   - a small preview of the underlying content
 *   - a count of related user reports on the same target so a single
 *     report doesn't get lost in a flood of automated flags.
 */
async function buildFlaggedContent() {
  const flags = await FlaggedContent.find({ status: 'PENDING' })
    .sort({ score: -1, createdAt: -1 })
    .limit(20);

  if (flags.length === 0) {
    return [];
  }

  // Group by (sourceType, sourceId) and pick the strongest flag per
  // group. This mirrors the dedup logic used for user reports so the
  // moderator does not see the same post five times.
  const groups = new Map();
  for (const flag of flags) {
    const key = `${flag.sourceType}:${flag.sourceId}`;
    const existing = groups.get(key);
    if (!existing || flag.score > existing.flag.score) {
      groups.set(key, { flag, allFlags: [...(existing?.allFlags || []), flag] });
    } else if (existing) {
      existing.allFlags.push(flag);
    }
  }

  const postIds = [];
  const commentIds = [];
  const messageIds = [];
  const mediaIds = [];
  for (const { flag } of groups.values()) {
    if (flag.sourceType === 'POST' && isValidObjectId(flag.sourceId)) {
      postIds.push(flag.sourceId);
    } else if (flag.sourceType === 'COMMENT' && isValidObjectId(flag.sourceId)) {
      commentIds.push(flag.sourceId);
    } else if (flag.sourceType === 'MESSAGE' && isValidObjectId(flag.sourceId)) {
      messageIds.push(flag.sourceId);
    } else if (flag.sourceType === 'MEDIA' && isValidObjectId(flag.sourceId)) {
      mediaIds.push(flag.sourceId);
    }
  }

  const [posts, comments, messages, media] = await Promise.all([
    postIds.length
      ? Post.find({ _id: { $in: postIds } }).select(
          '_id content authorSnapshot status mediaUrls',
        )
      : [],
    commentIds.length
      ? Comment.find({ _id: { $in: commentIds } }).select(
          '_id content authorSnapshot status',
        )
      : [],
    messageIds.length
      ? Message.find({ _id: { $in: messageIds } }).select(
          '_id content senderId status',
        ).populate('senderId', 'displayName username')
      : [],
    mediaIds.length
      ? MediaAsset.find({ _id: { $in: mediaIds } }).select(
          '_id secureUrl resourceType status moderation ownerId',
        ).populate('ownerId', 'displayName username')
      : [],
  ]);

  const postById = new Map(posts.map((p) => [p._id.toString(), p]));
  const commentById = new Map(comments.map((c) => [c._id.toString(), c]));
  const messageById = new Map(messages.map((m) => [m._id.toString(), m]));
  const mediaById = new Map(media.map((m) => [m._id.toString(), m]));

  // Count user reports per target for context. This helps the
  // moderator know "the keyword filter tripped, but 4 kids also
  // reported this manually — handle it now".
  const userReportCounts = await Report.aggregate([
    {
      $match: {
        status: { $in: ['PENDING', 'REVIEWING'] },
        category: { $ne: 'SPAM' },
      },
    },
    {
      $group: {
        _id: { targetType: '$targetType', targetId: '$targetId' },
        count: { $sum: 1 },
      },
    },
  ]);
  const reportCountByKey = new Map(
    userReportCounts.map((entry) => [
      `${entry._id.targetType}:${entry._id.targetId}`,
      entry.count,
    ]),
  );

  const items = [...groups.values()].map(({ flag, allFlags }) => {
    const key = `${flag.sourceType}:${flag.sourceId}`;
    const preview = describeFlaggedTarget(flag, {
      postById,
      commentById,
      messageById,
      mediaById,
    });
    return {
      id: flag._id.toString(),
      sourceType: flag.sourceType,
      sourceId: flag.sourceId,
      flaggedBy: flag.flaggedBy,
      categories: flag.categories,
      score: flag.score,
      details: flag.details || {},
      status: flag.status,
      createdAt: flag.createdAt,
      flagCount: allFlags.length,
      userReportCount: reportCountByKey.get(key) || 0,
      target: preview,
    };
  });

  // Highest score first; break ties by recency.
  items.sort((a, b) => {
    if (b.score !== a.score) {
      return b.score - a.score;
    }
    return new Date(b.createdAt) - new Date(a.createdAt);
  });

  return items.slice(0, 5);
}

function describeFlaggedTarget(flag, lookups) {
  if (flag.sourceType === 'POST' && lookups.postById.has(flag.sourceId)) {
    const post = lookups.postById.get(flag.sourceId);
    return {
      kind: 'POST',
      id: flag.sourceId,
      content: post.content,
      mediaUrls: post.mediaUrls || [],
      status: post.status,
      author: post.authorSnapshot?.displayName || post.authorSnapshot?.username || '',
    };
  }
  if (flag.sourceType === 'COMMENT' && lookups.commentById.has(flag.sourceId)) {
    const comment = lookups.commentById.get(flag.sourceId);
    return {
      kind: 'COMMENT',
      id: flag.sourceId,
      content: comment.content,
      author: comment.authorSnapshot?.displayName || comment.authorSnapshot?.username || '',
    };
  }
  if (flag.sourceType === 'MESSAGE' && lookups.messageById.has(flag.sourceId)) {
    const message = lookups.messageById.get(flag.sourceId);
    return {
      kind: 'MESSAGE',
      id: flag.sourceId,
      content: message.content,
      author: message.senderId?.displayName || message.senderId?.username || '',
      status: message.status,
    };
  }
  if (flag.sourceType === 'MEDIA' && lookups.mediaById?.has(flag.sourceId)) {
    const asset = lookups.mediaById.get(flag.sourceId);
    return {
      kind: 'MEDIA',
      id: flag.sourceId,
      url: asset.secureUrl,
      resourceType: asset.resourceType,
      status: asset.status,
      author: asset.ownerId?.displayName || asset.ownerId?.username || '',
      // Surface the AI's reason so the moderator does not have to
      // open the file just to see "why did the CNN service flag this".
      reason: flag.details?.topLabel || flag.details?.unsafeLabel || '',
      aiScore: flag.details?.topScore || flag.score,
    };
  }
  return { kind: flag.sourceType, id: flag.sourceId, content: '' };
}

function serializeSupportMessage(message) {
  return {
    id: message._id.toString(),
    threadId: message.threadId?.toString() || '',
    senderId: message.senderId?.toString() || '',
    senderRole: message.senderRole,
    content: message.content,
    createdAt: message.createdAt,
  };
}

function serializeSupportThread(thread, lastMessage = null) {
  const user =
    thread.userId && typeof thread.userId === 'object' && thread.userId.displayName !== undefined
      ? thread.userId
      : null;
  const assignedAdmin =
    thread.assignedAdminId &&
    typeof thread.assignedAdminId === 'object' &&
    thread.assignedAdminId.displayName !== undefined
      ? thread.assignedAdminId
      : null;

  return {
    id: thread._id.toString(),
    userId: user?._id?.toString() || thread.userId?.toString() || '',
    user: user
      ? {
          id: user._id.toString(),
          displayName: user.displayName,
          username: user.username,
          age: user.age,
        }
      : null,
    assignedAdmin: assignedAdmin
      ? {
          id: assignedAdmin._id.toString(),
          displayName: assignedAdmin.displayName,
          username: assignedAdmin.username,
        }
      : null,
    subject: thread.subject,
    category: thread.category,
    status: thread.status,
    lastMessage: lastMessage ? serializeSupportMessage(lastMessage) : null,
    lastMessageAt: thread.lastMessageAt,
    createdAt: thread.createdAt,
    updatedAt: thread.updatedAt,
  };
}

router.get(
  '/dashboard',
  asyncHandler(async (req, res) => {
    const sinceToday = nowMinus(24 * 60 * 60 * 1000);
    const [
      activeChildren,
      postsToday,
      openReports,
      flaggedMessages,
      topReports,
      flaggedPosts,
      watchedUsers,
      auditEvents,
    ] = await Promise.all([
      User.countDocuments({ role: 'CHILD', isActive: true }),
      Post.countDocuments({ createdAt: { $gte: sinceToday }, status: 'PUBLISHED' }),
      Report.countDocuments({ status: { $in: ['PENDING', 'REVIEWING'] } }),
      // "Flagged messages" = auto-flagged by the moderation pipeline in
      // the last 24h, not a hand-rolled keyword regex that misses
      // 90% of real cases.
      FlaggedContent.countDocuments({
        sourceType: 'MESSAGE',
        status: 'PENDING',
        createdAt: { $gte: sinceToday },
      }),
      // Highest priority reports: unresolved first, most urgent first.
      // We populate the reporter so the UI can show "who flagged this"
      // and aggregate duplicate reports on the same target so the queue
      // is not 5 copies of the same complaint.
      buildTopReports(),
      // Flagged content: pull straight from the FlaggedContent collection
      // which is fed by NSFW / keyword filter / user reports, rather
      // than doing a hand-rolled keyword regex on every recent post.
      buildFlaggedContent(),
      User.find({ moderationStatus: 'WATCHLIST' }).sort({ updatedAt: -1 }).limit(5),
      AuditLog.find({}).sort({ createdAt: -1 }).limit(10),
    ]);

    return res.json({
      stats: [
        { label: 'Active children', value: activeChildren, trend: '+0%', tone: 'blue' },
        { label: 'Posts today', value: postsToday, trend: '+0%', tone: 'green' },
        { label: 'Open reports', value: openReports, trend: '+0%', tone: 'orange' },
        { label: 'Flagged messages', value: flaggedMessages, trend: '+0%', tone: 'pink' },
      ],
      topReports,
      flaggedPosts,
      watchedUsers: watchedUsers.map((user) => ({
        ...toPublicUser(user),
        status: user.moderationStatus,
        risk: 'MEDIUM',
      })),
      auditEvents,
    });
  }),
);

router.get(
  '/users',
  asyncHandler(async (req, res) => {
    const q = String(req.query.q || '').trim();
    const query = {};
    if (q) {
      query.$or = [
        { displayName: { $regex: q, $options: 'i' } },
        { username: { $regex: q, $options: 'i' } },
      ];
    }

    const users = await User.find(query).sort({ createdAt: -1 }).limit(100);
    const items = await Promise.all(
      users.map(async (user) => {
        const [friends, posts] = await Promise.all([
          Friendship.countDocuments({
            $or: [{ userAId: user._id }, { userBId: user._id }],
          }),
          Post.countDocuments({ authorId: user._id, status: { $ne: 'DELETED' } }),
        ]);

        return {
          ...toPublicUser(user),
          status: user.moderationStatus || (user.isActive ? 'ACTIVE' : 'SUSPENDED'),
          isActive: user.isActive,
          friends,
          posts,
          risk: user.moderationStatus === 'WATCHLIST' ? 'MEDIUM' : 'LOW',
        };
      }),
    );

    return res.json({ items });
  }),
);

router.patch(
  '/users/:userId/status',
  asyncHandler(async (req, res) => {
    const { userId } = req.params;
    const status = String(req.body.status || '').toUpperCase();
    if (!isValidObjectId(userId)) {
      return res.status(400).json({ message: 'Invalid userId.' });
    }
    if (!['ACTIVE', 'WATCHLIST', 'SUSPENDED'].includes(status)) {
      return res.status(400).json({ message: 'Invalid user status.' });
    }

    const user = await User.findByIdAndUpdate(
      userId,
      {
        $set: {
          moderationStatus: status,
          isActive: status !== 'SUSPENDED',
        },
      },
      { returnNewDocument: true },
    );
    if (!user) {
      return res.status(404).json({ message: 'User not found.' });
    }

    await logAdminAction(req, `Set user status to ${status}`, 'USER', userId);
    return res.json({ message: 'User status updated.', user: toPublicUser(user) });
  }),
);

router.get(
  '/posts',
  asyncHandler(async (req, res) => {
    const status = String(req.query.status || '').toUpperCase();
    // `pending=1` is the review-queue view: only posts that an
    // admin still needs to look at (HIDDEN because a sensitive image
    // crossed the auto-publish threshold). Other filters compose
    // with it: `?pending=1&status=HIDDEN` is the explicit form, but
    // we also accept `?status=PENDING_REVIEW` for friendlier URLs.
    const pendingFlag = String(req.query.pending || '').trim() === '1';
    const query = {};
    if (status === 'PENDING_REVIEW') {
      query.pendingMediaReview = true;
      query.status = 'HIDDEN';
    } else if (pendingFlag) {
      query.pendingMediaReview = true;
      query.status = 'HIDDEN';
    } else if (status && status !== 'ALL') {
      query.status = status;
    }
    const posts = await Post.find(query).sort({ createdAt: -1 }).limit(200);
    return res.json({
      items: posts.map((post) => ({
        id: post._id.toString(),
        authorId: post.authorId.toString(),
        author: post.authorSnapshot?.displayName || post.authorSnapshot?.username || '',
        content: post.content,
        topics: post.topics,
        visibility: post.audience,
        mediaUrls: post.mediaUrls || [],
        reactions: post.reactionCount,
        comments: post.commentCount,
        status: post.status,
        risk: readPostRisk(post),
        pendingMediaReview: post.pendingMediaReview === true,
        mediaModerationScore: post.mediaModerationScore || 0,
        mediaModerationLabel: post.mediaModerationLabel || '',
        moderationDecisionAt: post.moderationDecisionAt || null,
        createdAt: post.createdAt,
      })),
    });
  }),
);

router.patch(
  '/posts/:postId/status',
  asyncHandler(async (req, res) => {
    const { postId } = req.params;
    const status = String(req.body.status || '').toUpperCase();
    if (!isValidObjectId(postId)) {
      return res.status(400).json({ message: 'Invalid postId.' });
    }
    if (!['PUBLISHED', 'HIDDEN', 'DELETED'].includes(status)) {
      return res.status(400).json({ message: 'Invalid post status.' });
    }

    const note = String(req.body.note || '').trim();

    const post = await Post.findByIdAndUpdate(
      postId,
      {
        $set: {
          status,
          // Once the admin has decided, the post is no longer
          // "pending review" regardless of the outcome. This keeps
          // the review queue from re-showing a post that has already
          // been published or deleted.
          pendingMediaReview: status === 'HIDDEN',
          moderationDecisionAt: new Date(),
          moderationDecisionBy: req.user.id,
          moderationDecisionNote: note,
        },
      },
      { returnNewDocument: true },
    );
    if (!post) {
      return res.status(404).json({ message: 'Post not found.' });
    }

    // Surface the admin's decision back to the author in two ways:
    //   - persistent Notification row so the user sees it next time
    //     they open the app even if they were offline
    //   - realtime `post:moderation_decided` event so the in-app
    //     SnackBar fires immediately for online users
    let userMessage = '';
    if (status === 'PUBLISHED') {
      userMessage =
        'Bài đăng của bạn đã được admin duyệt và hiển thị trên bảng tin.';
    } else if (status === 'DELETED') {
      userMessage =
        'Bài đăng của bạn đã bị xóa vì chứa hình ảnh không phù hợp.';
    } else {
      userMessage = 'Bài đăng của bạn đã được đặt lại trạng thái chờ duyệt.';
    }

    await sendNotification({
      userId: post.authorId,
      actorId: req.user.id,
      type: NOTIFICATION_TYPES.POST_MODERATION_DECIDED,
      title:
        status === 'PUBLISHED' ? 'Bài đăng đã được duyệt' : 'Bài đăng đã bị xóa',
      body: userMessage,
      payload: {
        postId: post._id.toString(),
        status,
        note,
        mediaModerationScore: post.mediaModerationScore,
        mediaModerationLabel: post.mediaModerationLabel,
        decidedBy: req.user.id,
        decidedAt: post.moderationDecisionAt,
        navigationTarget: {
          route: 'POST_DETAIL',
          postId: post._id.toString(),
        },
      },
    });

    emitToUser(post.authorId.toString(), 'post:moderation_decided', {
      postId: post._id.toString(),
      status,
      note,
      message: userMessage,
      mediaModerationScore: post.mediaModerationScore,
      mediaModerationLabel: post.mediaModerationLabel,
      decidedAt: post.moderationDecisionAt,
    });

    // If the admin published the post, also broadcast a feed change
    // so other clients refresh the home feed.
    if (status === 'PUBLISHED') {
      emitGlobal('feed:changed', {
        reason: 'post_published_by_admin',
        postId,
      });
    }

    await logAdminAction(
      req,
      `Set post status to ${status}${post.pendingMediaReview ? '' : ' (reviewed)'}`,
      'POST',
      postId,
      { note },
    );
    return res.json({ message: 'Post status updated.', post });
  }),
);

router.get(
  '/comments',
  asyncHandler(async (req, res) => {
    const query = {};
    if (req.query.postId && isValidObjectId(req.query.postId)) {
      query.postId = req.query.postId;
    }
    const comments = await Comment.find(query).sort({ createdAt: -1 }).limit(200);
    return res.json({
      items: comments.map((comment) => ({
        id: comment._id.toString(),
        postId: comment.postId.toString(),
        authorId: comment.authorId.toString(),
        author:
          comment.authorSnapshot?.displayName ||
          comment.authorSnapshot?.username ||
          '',
        content: comment.content,
        status: comment.status,
        createdAt: comment.createdAt,
      })),
    });
  }),
);

router.patch(
  '/comments/:commentId/status',
  asyncHandler(async (req, res) => {
    const { commentId } = req.params;
    const status = String(req.body.status || '').toUpperCase();
    if (!isValidObjectId(commentId)) {
      return res.status(400).json({ message: 'Invalid commentId.' });
    }
    if (!['PUBLISHED', 'HIDDEN', 'DELETED'].includes(status)) {
      return res.status(400).json({ message: 'Invalid comment status.' });
    }

    const comment = await Comment.findByIdAndUpdate(
      commentId,
      { $set: { status } },
      { returnNewDocument: true },
    );
    if (!comment) {
      return res.status(404).json({ message: 'Comment not found.' });
    }

    await logAdminAction(req, `Set comment status to ${status}`, 'COMMENT', commentId);
    return res.json({ message: 'Comment status updated.', comment });
  }),
);

router.get(
  '/reports',
  asyncHandler(async (req, res) => {
    const status = String(req.query.status || '').toUpperCase();
    const query = status && status !== 'ALL' ? { status } : {};
    const reports = await Report.find(query)
      .sort({ urgency: -1, createdAt: -1 })
      .limit(100)
      .populate('reporterId', 'displayName username avatarUrl')
      .populate('targetAuthorId', 'displayName username avatarUrl');

    // Project a shape that the admin UI already understands: same
    // `source` / `author` / `target` triple we use on the dashboard
    // cards. For real (non-blocked) targets we can fall back to the
    // persisted post / comment / user via the same lookup helpers.
    const items = reports.map((report) => {
      const obj = report.toObject();
      const reporter = obj.reporterId && typeof obj.reporterId === 'object'
        ? {
            id: obj.reporterId._id.toString(),
            displayName: obj.reporterId.displayName,
            username: obj.reporterId.username,
            avatarUrl: obj.reporterId.avatarUrl || '',
          }
        : null;
      const author = obj.targetAuthorId && typeof obj.targetAuthorId === 'object'
        ? {
            id: obj.targetAuthorId._id.toString(),
            displayName: obj.targetAuthorId.displayName || obj.targetAuthorId.username,
            username: obj.targetAuthorId.username,
            avatarUrl: obj.targetAuthorId.avatarUrl || '',
          }
        : null;

      return {
        id: obj._id.toString(),
        source: obj.source || 'USER',
        category: obj.category,
        urgency: obj.urgency,
        status: obj.status,
        details: obj.details || '',
        targetType: obj.targetType,
        targetId: obj.targetId,
        targetContent: obj.targetContent || '',
        createdAt: obj.createdAt,
        updatedAt: obj.updatedAt,
        reporter,
        author,
      };
    });

    // Enrich each item with a `target` preview (full post / comment /
    // user record) so the admin detail panel can show the offending
    // content + attached media without a second round-trip. Real
    // reports (targetId is a real ObjectId) get a real lookup;
    // synthetic "blocked-*" ids from the moderation pipeline keep the
    // `targetContent` snippet they were saved with.
    const postIds = items
      .filter((item) => item.targetType === 'POST' && isValidObjectId(item.targetId))
      .map((item) => item.targetId);
    const commentIds = items
      .filter((item) => item.targetType === 'COMMENT' && isValidObjectId(item.targetId))
      .map((item) => item.targetId);
    const userIds = items
      .filter((item) => item.targetType === 'USER' && isValidObjectId(item.targetId))
      .map((item) => item.targetId);

    const [posts, comments, users] = await Promise.all([
      postIds.length
        ? Post.find({ _id: { $in: postIds } }).select(
            '_id content authorSnapshot status mediaUrls audience topics reactionCount commentCount createdAt',
          )
        : [],
      commentIds.length
        ? Comment.find({ _id: { $in: commentIds } }).select(
            '_id content authorSnapshot status postId createdAt',
          )
        : [],
      userIds.length
        ? User.find({ _id: { $in: userIds } }).select(
            '_id displayName username avatarUrl age role moderationStatus createdAt',
          )
        : [],
    ]);

    const postById = new Map(posts.map((p) => [p._id.toString(), p]));
    const commentById = new Map(comments.map((c) => [c._id.toString(), c]));
    const userById = new Map(users.map((u) => [u._id.toString(), u]));

    const enriched = items.map((item) => {
      let target = null;
      if (item.targetType === 'POST' && postById.has(item.targetId)) {
        const post = postById.get(item.targetId);
        target = {
          kind: 'POST',
          id: post._id.toString(),
          content: post.content,
          mediaUrls: post.mediaUrls || [],
          audience: post.audience,
          topics: post.topics || [],
          status: post.status,
          reactions: post.reactionCount,
          commentCount: post.commentCount,
          author: post.authorSnapshot?.displayName || post.authorSnapshot?.username || '',
          authorHandle: post.authorSnapshot?.username || '',
          createdAt: post.createdAt,
        };
      } else if (item.targetType === 'COMMENT' && commentById.has(item.targetId)) {
        const comment = commentById.get(item.targetId);
        target = {
          kind: 'COMMENT',
          id: comment._id.toString(),
          postId: comment.postId.toString(),
          content: comment.content,
          status: comment.status,
          author: comment.authorSnapshot?.displayName || comment.authorSnapshot?.username || '',
          authorHandle: comment.authorSnapshot?.username || '',
          createdAt: comment.createdAt,
        };
      } else if (item.targetType === 'USER' && userById.has(item.targetId)) {
        const user = userById.get(item.targetId);
        target = {
          kind: 'USER',
          id: user._id.toString(),
          displayName: user.displayName,
          username: user.username,
          avatarUrl: user.avatarUrl || '',
          age: user.age,
          role: user.role,
          moderationStatus: user.moderationStatus,
          createdAt: user.createdAt,
        };
      } else if (item.targetId && item.targetId.startsWith('blocked-')) {
        const blocked = parseBlockedTarget(item.targetId);
        const snippet = item.targetContent || extractBlockedSnippet(item.details);
        target = {
          kind: `BLOCKED_${blocked?.kind || item.targetType}`,
          id: item.targetId,
          content: snippet,
          blocked: true,
          relatedId: blocked?.relatedId || '',
        };
      }
      return { ...item, target };
    });

    return res.json({ items: enriched });
  }),
);

router.patch(
  '/reports/:reportId',
  asyncHandler(async (req, res) => {
    const { reportId } = req.params;
    const status = String(req.body.status || '').toUpperCase();
    if (!isValidObjectId(reportId)) {
      return res.status(400).json({ message: 'Invalid reportId.' });
    }
    if (!['PENDING', 'REVIEWING', 'RESOLVED', 'DISMISSED'].includes(status)) {
      return res.status(400).json({ message: 'Invalid report status.' });
    }

    const report = await Report.findByIdAndUpdate(reportId, { $set: { status } }, { returnNewDocument: true });
    if (!report) {
      return res.status(404).json({ message: 'Report not found.' });
    }

    await logAdminAction(req, `Set report status to ${status}`, 'REPORT', reportId);
    return res.json({ message: 'Report updated.', report });
  }),
);

router.get(
  '/groups',
  asyncHandler(async (req, res) => {
    const groups = await Group.find({}).sort({ createdAt: -1 }).limit(100).populate('ownerId', 'displayName username');
    return res.json({
      items: groups.map((group) => ({
        id: group._id.toString(),
        name: group.name,
        topic: group.topic,
        description: group.description,
        members: group.memberCount,
        ageRange: `${group.ageMin}-${group.ageMax}`,
        status: group.status,
        owner: group.ownerId?.displayName || group.ownerId?.username || '',
      })),
    });
  }),
);

router.post(
  '/groups',
  asyncHandler(async (req, res) => {
    const { name, topic, description = '', ageMin = 7, ageMax = 14 } = req.body;
    if (!name || !topic) {
      return res.status(400).json({ message: 'name and topic are required.' });
    }

    const group = await Group.create({
      name: String(name).trim(),
      topic: String(topic).trim(),
      description: String(description || '').trim(),
      ageMin: Number(ageMin),
      ageMax: Number(ageMax),
      ownerId: req.user.id,
      memberCount: 0,
    });

    await logAdminAction(req, 'Created group', 'GROUP', group._id.toString());
    return res.status(201).json({ message: 'Group created.', group });
  }),
);

router.patch(
  '/groups/:groupId/status',
  asyncHandler(async (req, res) => {
    const { groupId } = req.params;
    const status = String(req.body.status || '').toUpperCase();
    if (!isValidObjectId(groupId)) {
      return res.status(400).json({ message: 'Invalid groupId.' });
    }
    if (!['ACTIVE', 'PAUSED', 'ARCHIVED'].includes(status)) {
      return res.status(400).json({ message: 'Invalid group status.' });
    }

    const group = await Group.findByIdAndUpdate(groupId, { $set: { status } }, { returnNewDocument: true });
    if (!group) {
      return res.status(404).json({ message: 'Group not found.' });
    }

    await logAdminAction(req, `Set group status to ${status}`, 'GROUP', groupId);
    return res.json({ message: 'Group status updated.', group });
  }),
);

router.get(
  '/messages',
  asyncHandler(async (req, res) => {
    const messages = await Message.find({}).sort({ createdAt: -1 }).limit(100).populate('senderId', 'displayName username');
    const chatIds = [...new Set(messages.map((message) => message.chatId.toString()))];
    const chats = await Chat.find({ _id: { $in: chatIds } });
    const chatsById = new Map(chats.map((chat) => [chat._id.toString(), chat]));

    return res.json({
      items: messages.map((message) => {
        const chat = chatsById.get(message.chatId.toString());
        return {
          id: message._id.toString(),
          chat: chat ? `${chat.type} chat` : 'Chat',
          sender: message.senderId?.displayName || message.senderId?.username || '',
          snippet: message.content,
          severity: readMessageSeverity(message),
          status: message.status === 'DELETED' ? 'REMOVED' : readMessageSeverity(message) === 'LOW' ? 'SAFE' : 'FLAGGED',
          createdAt: message.createdAt,
        };
      }),
    });
  }),
);

router.patch(
  '/messages/:messageId/status',
  asyncHandler(async (req, res) => {
    const { messageId } = req.params;
    const status = String(req.body.status || '').toUpperCase();
    if (!isValidObjectId(messageId)) {
      return res.status(400).json({ message: 'Invalid messageId.' });
    }
    if (!['SAFE', 'REMOVED', 'DELETED', 'SENT'].includes(status)) {
      return res.status(400).json({ message: 'Invalid message status.' });
    }

    const message = await Message.findByIdAndUpdate(
      messageId,
      { $set: { status: status === 'REMOVED' || status === 'DELETED' ? 'DELETED' : 'SENT' } },
      { returnNewDocument: true },
    );
    if (!message) {
      return res.status(404).json({ message: 'Message not found.' });
    }

    await logAdminAction(req, `Set message status to ${status}`, 'MESSAGE', messageId);
    return res.json({ message: 'Message status updated.', data: message });
  }),
);

router.post(
  '/notifications/broadcast',
  asyncHandler(async (req, res) => {
    const { title, body, audience = 'ALL' } = req.body;
    if (!title || !body) {
      return res.status(400).json({ message: 'title and body are required.' });
    }

    const query = {};
    if (audience === 'CHILDREN') {
      query.role = 'CHILD';
    } else if (audience === 'MODERATORS') {
      query.role = { $in: ['MODERATOR', 'ADMIN'] };
    } else if (audience === 'AGE_7_10') {
      query.age = { $gte: 7, $lte: 10 };
      query.role = 'CHILD';
    } else if (audience === 'AGE_11_14') {
      query.age = { $gte: 11, $lte: 14 };
      query.role = 'CHILD';
    }

    const users = await User.find({ ...query, isActive: true }).select('_id');
    if (users.length > 0) {
      // Persist the notification rows AND push the realtime event
      // so online users see the broadcast immediately. We use the
      // service so we get the standard category / navigation
      // metadata too.
      await broadcastNotification({
        userIds: users.map((user) => user._id),
        actorId: req.user.id,
        type: NOTIFICATION_TYPES.ADMIN_BROADCAST,
        title: String(title).trim(),
        body: String(body).trim(),
        payload: {
          audience,
          adminActorId: req.user.id,
          navigationTarget: {
            route: 'NOTIFICATIONS',
          },
        },
      });
    }

    await logAdminAction(req, `Broadcast notification to ${audience}`, 'NOTIFICATION', '');
    return res.status(201).json({ message: 'Notification queued.', count: users.length });
  }),
);

router.get(
  '/badges',
  asyncHandler(async (req, res) => {
    return res.json({ items: await buildBadgeCatalog() });
  }),
);

router.get(
  '/media',
  asyncHandler(async (req, res) => {
    const status = String(req.query.status || '').toUpperCase();
    const assetQuery = {};
    if (status && status !== 'ALL' && ['APPROVED', 'REVIEW', 'BLOCKED', 'REMOVED'].includes(status)) {
      assetQuery.status = status;
    }

    const [assets, users, posts] = await Promise.all([
      MediaAsset.find(assetQuery)
        .sort({ createdAt: -1 })
        .limit(200)
        .populate('ownerId', 'displayName username'),
      User.find({ avatarUrl: { $ne: '' } }).sort({ updatedAt: -1 }).limit(50),
      Post.find({ mediaUrls: { $exists: true, $ne: [] } }).sort({ createdAt: -1 }).limit(100),
    ]);

    const assetUrls = new Set(assets.map((asset) => asset.secureUrl));
    const items = [
      ...assets.map(serializeAdminMediaAsset),
      ...users.map((user) => ({
        id: `avatar:${user._id.toString()}`,
        owner: user.displayName,
        source: 'Profile',
        url: user.avatarUrl,
        status: 'APPROVED',
      })).filter((item) => !assetUrls.has(item.url)),
      ...posts.flatMap((post) =>
        post.mediaUrls.map((url, index) => ({
          id: `${post._id.toString()}:${index}`,
          owner: post.authorSnapshot?.displayName || '',
          source: 'Post',
          url,
          status: post.status === 'HIDDEN' ? 'REVIEW' : 'APPROVED',
        })),
      ).filter((item) => !assetUrls.has(item.url)),
    ];

    return res.json({ items });
  }),
);

router.get(
  '/flags',
  asyncHandler(async (req, res) => {
    const status = String(req.query.status || '').toUpperCase();
    const query = status && status !== 'ALL' ? { status } : { status: 'PENDING' };
    const flags = await FlaggedContent.find(query).sort({ createdAt: -1 }).limit(200);
    return res.json({
      items: flags.map((flag) => ({
        id: flag._id.toString(),
        sourceType: flag.sourceType,
        sourceId: flag.sourceId,
        flaggedBy: flag.flaggedBy,
        categories: flag.categories,
        score: flag.score,
        details: flag.details,
        status: flag.status,
        createdAt: flag.createdAt,
      })),
    });
  }),
);

router.patch(
  '/flags/:flagId',
  asyncHandler(async (req, res) => {
    const { flagId } = req.params;
    if (!isValidObjectId(flagId)) {
      return res.status(400).json({ message: 'Invalid flagId.' });
    }
    const action = String(req.body.action || '').toUpperCase();
    if (!['CONFIRM', 'DISMISS'].includes(action)) {
      return res.status(400).json({ message: 'action must be CONFIRM or DISMISS.' });
    }

    const flag = await FlaggedContent.findById(flagId);
    if (!flag) {
      return res.status(404).json({ message: 'Flag not found.' });
    }

    if (flag.sourceType === 'MEDIA' && isValidObjectId(flag.sourceId)) {
      const asset = await MediaAsset.findById(flag.sourceId);
      if (asset) {
        if (action === 'CONFIRM') {
          await detachMediaFromSource(asset);
          await destroyMediaAsset(asset);
          asset.status = 'REMOVED';
        } else {
          asset.status = 'APPROVED';
        }
        await asset.save();
      }
    }

    flag.status = action === 'CONFIRM' ? 'CONFIRMED' : 'DISMISSED';
    flag.handledBy = req.user.id;
    flag.handledAt = new Date();
    await flag.save();

    await logAdminAction(
      req,
      action === 'CONFIRM'
        ? `Removed flagged ${flag.sourceType.toLowerCase()} (${flag.details?.assetStatus || 'unknown'})`
        : `Approved flagged ${flag.sourceType.toLowerCase()} (${flag.details?.assetStatus || 'unknown'})`,
      flag.sourceType,
      flag.sourceId,
      { flagId: flag._id.toString() },
    );

    return res.json({ message: 'Flag handled.', flag });
  }),
);

router.patch(
  '/media/:mediaId/status',
  asyncHandler(async (req, res) => {
    const { mediaId } = req.params;
    const status = String(req.body.status || '').toUpperCase();
    if (!['APPROVED', 'REVIEW', 'REMOVED'].includes(status)) {
      return res.status(400).json({ message: 'Invalid media status.' });
    }

    if (isValidObjectId(mediaId)) {
      const asset = await MediaAsset.findById(mediaId);
      if (!asset) {
        return res.status(404).json({ message: 'Media not found.' });
      }

      if (status === 'REMOVED') {
        await detachMediaFromSource(asset);
        await destroyMediaAsset(asset);
      }

      asset.status = status;
      await asset.save();
    } else if (status === 'REMOVED' && mediaId.startsWith('avatar:')) {
      const userId = mediaId.replace('avatar:', '');
      if (!isValidObjectId(userId)) {
        return res.status(400).json({ message: 'Invalid media id.' });
      }
      await User.findByIdAndUpdate(userId, { $set: { avatarUrl: '' } });
    } else if (status === 'REMOVED') {
      const [postId, rawIndex] = mediaId.split(':');
      const index = Number(rawIndex);
      if (!isValidObjectId(postId) || Number.isNaN(index)) {
        return res.status(400).json({ message: 'Invalid media id.' });
      }
      const post = await Post.findById(postId);
      if (!post) {
        return res.status(404).json({ message: 'Post not found.' });
      }
      post.mediaUrls = post.mediaUrls.filter((_, itemIndex) => itemIndex !== index);
      await post.save();
    }

    await logAdminAction(req, `Set media status to ${status}`, 'MEDIA', mediaId);
    return res.json({ message: 'Media updated.' });
  }),
);

router.get(
  '/safety',
  asyncHandler(async (req, res) => {
    const setting = await AppSetting.findOne({ key: 'safety_config' });
    return res.json({ data: setting?.value || DEFAULT_SAFETY_CONFIG });
  }),
);

router.patch(
  '/safety',
  asyncHandler(async (req, res) => {
    const value = {
      safeSearchDefault: req.body.safeSearchDefault !== false,
      autoHideHighRisk: req.body.autoHideHighRisk !== false,
      rules: Array.isArray(req.body.rules)
        ? req.body.rules.map((rule) => String(rule).trim()).filter(Boolean)
        : DEFAULT_SAFETY_CONFIG.rules,
    };

    await AppSetting.findOneAndUpdate(
      { key: 'safety_config' },
      { $set: { key: 'safety_config', value } },
      { upsert: true, returnNewDocument: true },
    );
    await logAdminAction(req, 'Updated safety configuration', 'SAFETY', 'safety_config');
    return res.json({ message: 'Safety settings updated.', data: value });
  }),
);

router.get(
  '/support',
  asyncHandler(async (req, res) => {
    const status = String(req.query.status || '').toUpperCase();
    const query = status && status !== 'ALL' ? { status } : {};
    const threads = await SupportThread.find(query)
      .sort({ lastMessageAt: -1 })
      .limit(100)
      .populate('userId', 'displayName username age')
      .populate('assignedAdminId', 'displayName username');

    const lastMessages = await Promise.all(
      threads.map((thread) =>
        SupportMessage.findOne({ threadId: thread._id }).sort({ createdAt: -1 }),
      ),
    );

    return res.json({
      items: threads.map((thread, index) =>
        serializeSupportThread(thread, lastMessages[index]),
      ),
    });
  }),
);

router.get(
  '/support/:threadId/messages',
  asyncHandler(async (req, res) => {
    const { threadId } = req.params;
    if (!isValidObjectId(threadId)) {
      return res.status(400).json({ message: 'Invalid threadId.' });
    }

    const thread = await SupportThread.findById(threadId)
      .populate('userId', 'displayName username age')
      .populate('assignedAdminId', 'displayName username');
    if (!thread) {
      return res.status(404).json({ message: 'Support thread not found.' });
    }

    const messages = await SupportMessage.find({ threadId })
      .sort({ createdAt: 1 })
      .limit(300);

    return res.json({
      thread: serializeSupportThread(thread),
      messages: messages.map(serializeSupportMessage),
    });
  }),
);

router.post(
  '/support/:threadId/messages',
  asyncHandler(async (req, res) => {
    const { threadId } = req.params;
    const content = String(req.body.content || '').trim();
    if (!isValidObjectId(threadId)) {
      return res.status(400).json({ message: 'Invalid threadId.' });
    }
    if (!content) {
      return res.status(400).json({ message: 'content is required.' });
    }

    const thread = await SupportThread.findById(threadId);
    if (!thread) {
      return res.status(404).json({ message: 'Support thread not found.' });
    }

    const message = await SupportMessage.create({
      threadId,
      senderId: req.user.id,
      senderRole: 'ADMIN',
      content,
    });

    thread.status = 'PENDING_USER';
    thread.assignedAdminId = req.user.id;
    thread.lastMessageAt = message.createdAt;
    await thread.save();
    const threadUserId = thread.userId.toString();
    await thread.populate('userId', 'displayName username age');
    await thread.populate('assignedAdminId', 'displayName username');

    const payload = {
      thread: serializeSupportThread(thread),
      message: serializeSupportMessage(message),
    };
    emitToUser(threadUserId, 'support:message', payload);

    const adminUser = await User.findById(req.user.id).select(
      'displayName username avatarUrl',
    );
    await sendNotification({
      userId: threadUserId,
      actorId: req.user.id,
      type: NOTIFICATION_TYPES.SUPPORT_MESSAGE_RECEIVED,
      payload: {
        threadId,
        subject: thread.subject,
        contentSnippet: content.slice(0, 240),
        adminActorName: adminUser?.displayName || adminUser?.username || 'Đội ngũ Kiddo',
        navigationTarget: {
          route: 'SUPPORT',
          threadId,
        },
      },
    });

    await logAdminAction(req, 'Replied to support thread', 'SUPPORT', threadId);
    return res.status(201).json(payload);
  }),
);

router.patch(
  '/support/:threadId/status',
  asyncHandler(async (req, res) => {
    const { threadId } = req.params;
    const status = String(req.body.status || '').toUpperCase();
    if (!isValidObjectId(threadId)) {
      return res.status(400).json({ message: 'Invalid threadId.' });
    }
    if (!['OPEN', 'PENDING_USER', 'RESOLVED'].includes(status)) {
      return res.status(400).json({ message: 'Invalid support status.' });
    }

    const thread = await SupportThread.findByIdAndUpdate(
      threadId,
      {
        $set: {
          status,
          assignedAdminId: req.user.id,
        },
      },
      { returnNewDocument: true },
    );
    if (!thread) {
      return res.status(404).json({ message: 'Support thread not found.' });
    }
    const threadUserId = thread.userId.toString();
    await thread.populate('userId', 'displayName username age');
    await thread.populate('assignedAdminId', 'displayName username');

    emitToUser(threadUserId, 'support:updated', {
      thread: serializeSupportThread(thread),
    });

    await sendNotification({
      userId: threadUserId,
      actorId: req.user.id,
      type: NOTIFICATION_TYPES.SUPPORT_STATUS_UPDATED,
      payload: {
        threadId,
        subject: thread.subject,
        status,
        navigationTarget: {
          route: 'SUPPORT',
          threadId,
        },
      },
    });

    await logAdminAction(req, `Set support status to ${status}`, 'SUPPORT', threadId);
    return res.json({ message: 'Support thread updated.', thread: serializeSupportThread(thread) });
  }),
);

router.get(
  '/audit',
  asyncHandler(async (req, res) => {
    const items = await AuditLog.find({}).sort({ createdAt: -1 }).limit(100);
    return res.json({ items });
  }),
);

module.exports = router;
