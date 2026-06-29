const express = require('express');

const Report = require('../models/Report');
const Notification = require('../models/Notification');
const User = require('../models/User');
const Post = require('../models/Post');
const Comment = require('../models/Comment');
const Group = require('../models/Group');
const Message = require('../models/Message');
const asyncHandler = require('../utils/async-handler');
const { requireAuth, requireRole } = require('../middlewares/auth');
const { isValidObjectId } = require('../middlewares/object-id');
const {
  sendNotification,
  broadcastNotification,
  NOTIFICATION_TYPES,
} = require('../services/notification-service');

const router = express.Router();

const COMMUNITY_RULES = [
  {
    id: 'kindness',
    title: 'Be kind in every message',
    description: 'No bullying, insulting, or threatening language.',
  },
  {
    id: 'private-info',
    title: 'Protect private information',
    description: 'Do not share phone numbers, home address, or school details.',
  },
  {
    id: 'age-safe',
    title: 'Post age-appropriate content',
    description: 'Keep all posts safe for ages 7 to 14.',
  },
  {
    id: 'respect',
    title: 'Respect boundaries',
    description: 'Stop interaction when someone asks for space.',
  },
];

function normalizeReportCategory(category) {
  const value = String(category || '').trim().toUpperCase().replace(/\s+/g, '_');
  const aliases = {
    BULLYING: 'BULLYING',
    UNSAFE_CONTENT: 'UNSAFE_CONTENT',
    PRIVATE_INFO: 'PRIVATE_INFO',
    PRIVATE_INFO_SHARING: 'PRIVATE_INFO',
    SPAM: 'SPAM',
    OTHER: 'OTHER',
  };
  return aliases[value] || 'OTHER';
}

function normalizeReportTargetType(targetType) {
  const value = String(targetType || '').trim().toUpperCase().replace(/\s+/g, '_');
  if (value === 'CHAT') {
    return 'MESSAGE';
  }
  if (['USER', 'POST', 'COMMENT', 'GROUP', 'MESSAGE'].includes(value)) {
    return value;
  }
  return 'POST';
}

/**
 * Fetch the raw content associated with a report's target so the
 * admin panel can display it without a second round-trip.
 *
 * Returns null if the target was already deleted / not found.
 */
async function resolveTargetContent(targetType, targetId) {
  if (!targetType || !targetId) {
    return null;
  }
  try {
    switch (String(targetType).toUpperCase()) {
      case 'POST': {
        const post = await Post.findById(targetId)
          .select('author displayName username avatarUrl content mediaUrls status visibility reactions commentCount topics createdAt')
          .lean();
        if (!post) {
          return null;
        }
        // Flatten author subdocument into top-level fields so the
        // frontend TargetDetail component stays simple.
        return {
          kind: 'POST',
          author: post.displayName || post.author?.displayName || post.author?.username || 'Unknown',
          authorHandle: post.username || post.author?.username || '',
          authorAvatarUrl: post.avatarUrl || post.author?.avatarUrl || '',
          content: post.content || '',
          mediaUrls: post.mediaUrls || [],
          status: post.status || 'PUBLISHED',
          audience: post.visibility || 'FRIENDS',
          reactions: post.reactions || 0,
          commentCount: post.commentCount || 0,
          topics: post.topics || [],
          createdAt: post.createdAt,
        };
      }
      case 'COMMENT': {
        const comment = await Comment.findById(targetId)
          .select('author displayName username avatarUrl content postId createdAt')
          .lean();
        if (!comment) {
          return null;
        }
        return {
          kind: 'COMMENT',
          author: comment.displayName || comment.author?.displayName || comment.author?.username || 'Unknown',
          authorHandle: comment.username || comment.author?.username || '',
          authorAvatarUrl: comment.avatarUrl || comment.author?.avatarUrl || '',
          content: comment.content || '',
          postId: comment.postId?.toString() || '',
          createdAt: comment.createdAt,
        };
      }
      case 'USER': {
        const user = await User.findById(targetId)
          .select('displayName username avatarUrl role age createdAt isActive')
          .lean();
        if (!user) {
          return null;
        }
        return {
          kind: 'USER',
          displayName: user.displayName || '',
          username: user.username || '',
          avatarUrl: user.avatarUrl || '',
          role: user.role || 'USER',
          age: user.age || null,
          moderationStatus: user.isActive === false ? 'SUSPENDED' : 'ACTIVE',
          createdAt: user.createdAt,
        };
      }
      case 'GROUP': {
        const group = await Group.findById(targetId)
          .select('name topic description memberCount createdAt')
          .lean();
        if (!group) {
          return null;
        }
        return {
          kind: 'GROUP',
          name: group.name || '',
          topic: group.topic || '',
          description: group.description || '',
          memberCount: group.memberCount || 0,
          createdAt: group.createdAt,
        };
      }
      case 'MESSAGE': {
        const message = await Message.findById(targetId)
          .select('senderId sender displayName username avatarUrl content createdAt')
          .lean();
        if (!message) {
          return null;
        }
        return {
          kind: 'MESSAGE',
          author: message.displayName || message.sender?.displayName || message.sender?.username || 'Unknown',
          authorHandle: message.username || message.sender?.username || '',
          authorAvatarUrl: message.avatarUrl || message.sender?.avatarUrl || '',
          content: message.content || '',
          createdAt: message.createdAt,
        };
      }
      default:
        return null;
    }
  } catch {
    // Target may have already been deleted — return null so the
    // frontend renders the "no longer available" message.
    return null;
  }
}

/**
 * Build a reporter / targetAuthor summary from a User document.
 * Strips sensitive fields and returns only what's needed by the UI.
 */
function summarizeUser(userDoc) {
  if (!userDoc) {
    return null;
  }
  return {
    id: userDoc._id?.toString() || userDoc.id || '',
    displayName: userDoc.displayName || userDoc.username || 'Unknown',
    username: userDoc.username || '',
    avatarUrl: userDoc.avatarUrl || '',
    role: userDoc.role || 'USER',
  };
}

/**
 * Enrich a single Report document with all resolved data needed
 * by the admin panel so the frontend never has to guess or round-trip.
 */
async function enrichReport(report) {
  const [reporter, targetAuthor, target] = await Promise.all([
    report.reporterId
      ? User.findById(report.reporterId).select('displayName username avatarUrl role').lean()
      : null,
    report.targetAuthorId
      ? User.findById(report.targetAuthorId).select('displayName username avatarUrl role').lean()
      : null,
    resolveTargetContent(report.targetType, report.targetId),
  ]);

  return {
    id: report._id.toString(),
    source: report.source,
    category: report.category,
    urgency: report.urgency,
    status: report.status,
    details: report.details || '',
    targetContent: report.targetContent || '',
    targetType: report.targetType,
    targetId: report.targetId,
    targetAuthorId: report.targetAuthorId ? report.targetAuthorId.toString() : null,
    reporterId: report.reporterId ? report.reporterId.toString() : null,
    createdAt: report.createdAt,
    updatedAt: report.updatedAt,
    reporter: summarizeUser(reporter),
    targetAuthor: summarizeUser(targetAuthor),
    target,
  };
}

router.get('/rules', (req, res) => {
  res.json({ items: COMMUNITY_RULES });
});

router.post(
  '/reports',
  requireAuth,
  asyncHandler(async (req, res) => {
    const { targetType, targetId, category, details = '', urgency = 2 } = req.body;

    if (!targetType || !targetId || !category) {
      return res.status(400).json({
        message: 'targetType, targetId, category are required.',
      });
    }

    const report = await Report.create({
      reporterId: req.user.id,
      targetType: normalizeReportTargetType(targetType),
      targetId: String(targetId),
      category: normalizeReportCategory(category),
      details: String(details || '').trim(),
      urgency: Number(urgency),
    });

    await sendNotification({
      userId: req.user.id,
      actorId: req.user.id,
      type: NOTIFICATION_TYPES.REPORT_SUBMITTED,
      payload: {
        reportId: report._id.toString(),
        targetType: report.targetType,
        targetId: report.targetId,
        category: report.category,
        navigationTarget: {
          route: 'REPORTS',
        },
      },
    });

    // Surface the new report to moderators/admins so the queue
    // updates in realtime instead of waiting for a refresh.
    const admins = await User.find({
      role: { $in: ['ADMIN', 'MODERATOR'] },
      isActive: true,
    }).select('_id');
    if (admins.length > 0) {
      const reporter = await User.findById(req.user.id).select(
        'displayName username avatarUrl',
      );
      await broadcastNotification({
        userIds: admins.map((admin) => admin._id),
        actorId: req.user.id,
        type: NOTIFICATION_TYPES.ADMIN_MODERATION_ALERT,
        payload: {
          subjectType: 'REPORT',
          subjectId: report._id.toString(),
          reportId: report._id.toString(),
          reason: 'REPORT_SUBMITTED',
          category: report.category,
          urgency: report.urgency,
          actorName:
            reporter?.displayName || reporter?.username || 'Một người dùng',
          actorUsername: reporter?.username || '',
          actorAvatarUrl: reporter?.avatarUrl || '',
          navigationTarget: {
            route: 'ADMIN_REPORTS',
            reportId: report._id.toString(),
          },
        },
      });
    }

    return res.status(201).json({ message: 'Report submitted.', report });
  }),
);

router.get(
  '/reports/me',
  requireAuth,
  asyncHandler(async (req, res) => {
    const items = await Report.find({ reporterId: req.user.id }).sort({
      createdAt: -1,
    });
    return res.json({ items });
  }),
);

// ── Moderation endpoints ─────────────────────────────────────────────

router.get(
  '/reports/moderation',
  requireAuth,
  requireRole('MODERATOR', 'ADMIN'),
  asyncHandler(async (req, res) => {
    const status = req.query.status ? String(req.query.status) : undefined;
    const query = status ? { status } : {};

    const reports = await Report.find(query)
      .sort({ urgency: -1, createdAt: -1 })
      .lean();

    // Resolve all reports in parallel — MongoDB can serve them faster
    // than sequential queries would.
    const enriched = await Promise.all(reports.map(enrichReport));

    return res.json({ items: enriched });
  }),
);

router.get(
  '/reports/:reportId',
  requireAuth,
  requireRole('MODERATOR', 'ADMIN'),
  asyncHandler(async (req, res) => {
    const { reportId } = req.params;

    if (!isValidObjectId(reportId)) {
      return res.status(400).json({ message: 'Invalid reportId.' });
    }

    const report = await Report.findById(reportId).lean();
    if (!report) {
      return res.status(404).json({ message: 'Report not found.' });
    }

    return res.json({ item: await enrichReport(report) });
  }),
);

router.patch(
  '/reports/:reportId',
  requireAuth,
  requireRole('MODERATOR', 'ADMIN'),
  asyncHandler(async (req, res) => {
    const { reportId } = req.params;
    const { status } = req.body;

    if (!isValidObjectId(reportId)) {
      return res.status(400).json({ message: 'Invalid reportId.' });
    }

    if (!['PENDING', 'REVIEWING', 'RESOLVED', 'DISMISSED'].includes(status)) {
      return res.status(400).json({ message: 'Invalid report status.' });
    }

    const report = await Report.findByIdAndUpdate(
      reportId,
      { $set: { status } },
      { returnNewDocument: true, runValidators: true },
    );
    if (!report) {
      return res.status(404).json({ message: 'Report not found.' });
    }

    await sendNotification({
      userId: report.reporterId,
      actorId: req.user.id,
      type: NOTIFICATION_TYPES.REPORT_STATUS_UPDATED,
      payload: {
        reportId: report._id.toString(),
        status,
        navigationTarget: {
          route: 'REPORTS',
        },
      },
    });

    return res.json({ message: 'Report updated.', report });
  }),
);

module.exports = router;
