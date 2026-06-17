const express = require('express');

const Post = require('../models/Post');
const PostBookmark = require('../models/PostBookmark');
const PostReaction = require('../models/PostReaction');
const { ALLOWED_REACTIONS } = require('../models/PostReaction');
const Group = require('../models/Group');
const GroupMember = require('../models/GroupMember');
const User = require('../models/User');
const Friendship = require('../models/Friendship');
const Notification = require('../models/Notification');
const MediaAsset = require('../models/MediaAsset');
const asyncHandler = require('../utils/async-handler');
const { requireAuth } = require('../middlewares/auth');
const { isValidObjectId } = require('../middlewares/object-id');
const { normalizeFriendPair } = require('../utils/friendship');
const { withPostMeta } = require('../utils/post-meta');
const { assertContentAllowed } = require('../services/content-moderation');
const {
  sendNotification,
  broadcastNotification,
  NOTIFICATION_TYPES,
} = require('../services/notification-service');
const env = require('../config/env');
const { emitGlobal, emitToPost, emitToUser } = require('../realtime/socket');

const router = express.Router();

router.use(requireAuth);

/**
 * For a list of secureUrls belonging to the post author, look up the
 * MediaAsset rows and figure out whether any of them crossed the
 * configured moderation threshold. We use this in the create-post
 * path to decide between PUBLISHED (auto) and HIDDEN + admin review.
 *
 * Returns:
 *   - hasFlagged: true if at least one image needs admin review
 *   - maxScore: highest unsafe score across the post's attachments
 *   - topLabel: the label that produced that score (e.g. "NSFW")
 */
async function summarisePostMedia(userId, mediaUrls) {
  if (!Array.isArray(mediaUrls) || mediaUrls.length === 0) {
    return { hasFlagged: false, maxScore: 0, topLabel: '' };
  }

  const assets = await MediaAsset.find({
    ownerId: userId,
    secureUrl: { $in: mediaUrls },
  });

  if (assets.length === 0) {
    return { hasFlagged: false, maxScore: 0, topLabel: '' };
  }

  const threshold = env.mediaModerationThreshold;
  let maxScore = 0;
  let topLabel = '';
  let hasFlagged = false;

  for (const asset of assets) {
    const status = asset.status;
    const score = Number(asset.moderation?.unsafeScore || 0);
    if (status === 'BLOCKED' || (status === 'REVIEW' && score >= threshold)) {
      hasFlagged = true;
      if (score > maxScore) {
        maxScore = score;
        topLabel = asset.moderation?.unsafeLabel || asset.moderation?.topLabel || '';
      }
    }
  }

  return { hasFlagged, maxScore, topLabel };
}

function actorSnapshot(user) {
  return {
    actorId: user._id.toString(),
    actorName: user.displayName || user.username || 'Ai đó',
    actorUsername: user.username || '',
    actorAvatarUrl: user.avatarUrl || '',
  };
}

async function getFriendSet(userId) {
  const rows = await Friendship.find({
    $or: [{ userAId: userId }, { userBId: userId }],
  });
  const set = new Set();
  for (const row of rows) {
    const a = row.userAId.toString();
    const b = row.userBId.toString();
    set.add(a === userId ? b : a);
  }
  return set;
}

async function filterNonChildAuthorPosts(posts, currentUser) {
  if (currentUser.role !== 'CHILD' || posts.length === 0) {
    return posts;
  }

  const authorIds = [...new Set(posts.map((post) => post.authorId.toString()))];
  const childAuthors = await User.find({
    _id: { $in: authorIds },
    role: 'CHILD',
    isActive: true,
  }).select('_id');
  const childAuthorIds = new Set(childAuthors.map((user) => user._id.toString()));

  return posts.filter((post) => childAuthorIds.has(post.authorId.toString()));
}

router.post(
  '/',
  asyncHandler(async (req, res) => {
    const {
      content,
      topics = [],
      mood = '',
      mediaUrls = [],
      audience = 'FRIENDS',
      allowComments = true,
      allowReactions = true,
      ageMin = 7,
      ageMax = 14,
      groupId = null,
    } = req.body;

    if (!content || !String(content).trim()) {
      return res.status(400).json({ message: 'content is required.' });
    }
    if (Number(ageMin) > Number(ageMax)) {
      return res.status(400).json({ message: 'ageMin must be <= ageMax.' });
    }

    let resolvedGroupId = null;
    if (groupId) {
      if (!isValidObjectId(groupId)) {
        return res.status(400).json({ message: 'Invalid groupId.' });
      }
      const group = await Group.findById(groupId);
      if (!group || group.status !== 'ACTIVE') {
        return res.status(404).json({ message: 'Group not found.' });
      }
      const membership = await GroupMember.findOne({
        groupId,
        userId: req.user.id,
        status: 'ACTIVE',
      });
      if (!membership) {
        return res
          .status(403)
          .json({ message: 'You must join the group before posting.' });
      }
      resolvedGroupId = group._id;
    }

    await assertContentAllowed({
      text: content,
      userId: req.user.id,
      targetType: 'POST',
      targetId: `blocked-post:${req.user.id}:${Date.now()}`,
      action: 'create a post',
    });

    const author = await User.findById(req.user.id);
    if (!author) {
      return res.status(404).json({ message: 'Author not found.' });
    }

    const finalAudience = resolvedGroupId ? 'GROUP' : (audience === 'PUBLIC' ? 'PUBLIC' : 'FRIENDS');

    // Image moderation: if any attachment crossed the configured
    // threshold, we still create the post (so the user does not lose
    // their work) but mark it as HIDDEN + pendingMediaReview. The
    // admin will see it on the Posts & comments tab and either
    // publish or delete it from there.
    const mediaSummary = await summarisePostMedia(
      req.user.id,
      Array.isArray(mediaUrls) ? mediaUrls : [],
    );
    const needsReview = mediaSummary.hasFlagged;
    const initialStatus = needsReview ? 'HIDDEN' : 'PUBLISHED';

    const post = await Post.create({
      authorId: author._id,
      authorSnapshot: {
        displayName: author.displayName,
        username: author.username,
        avatarUrl: author.avatarUrl,
      },
      content: String(content).trim(),
      topics: Array.isArray(topics)
        ? topics.map((item) => String(item).trim()).filter(Boolean)
        : [],
      mood: String(mood || '').trim(),
      mediaUrls: Array.isArray(mediaUrls)
        ? mediaUrls.map((item) => String(item).trim()).filter(Boolean)
        : [],
      audience: finalAudience,
      allowComments: !!allowComments,
      allowReactions: !!allowReactions,
      ageMin: Number(ageMin),
      ageMax: Number(ageMax),
      groupId: resolvedGroupId,
      status: initialStatus,
      pendingMediaReview: needsReview,
      mediaModerationScore: mediaSummary.maxScore,
      mediaModerationLabel: mediaSummary.topLabel,
    });

    if (needsReview) {
      // Inform the author that their post is held for review. The
      // realtime event is the primary path (in-app SnackBar); the
      // Notification row is the persistent record that survives a
      // reload.
      await sendNotification({
        userId: author._id,
        type: NOTIFICATION_TYPES.POST_PENDING_MEDIA_REVIEW,
        payload: {
          postId: post._id.toString(),
          mediaModerationScore: mediaSummary.maxScore,
          mediaModerationLabel: mediaSummary.topLabel,
          navigationTarget: {
            route: 'POST_DETAIL',
            postId: post._id.toString(),
          },
        },
      });
      emitToUser(author._id.toString(), 'post:pending_media_review', {
        postId: post._id.toString(),
        mediaModerationScore: mediaSummary.maxScore,
        mediaModerationLabel: mediaSummary.topLabel,
      });

      // Surface to admins so the moderation queue picks it up.
      const adminDocs = await User.find({
        role: 'ADMIN',
        isActive: true,
      }).select('_id');
      if (adminDocs.length > 0) {
        await broadcastNotification({
          userIds: adminDocs.map((admin) => admin._id),
          actorId: req.user.id,
          type: NOTIFICATION_TYPES.ADMIN_MODERATION_ALERT,
          payload: {
            subjectType: 'POST',
            subjectId: post._id.toString(),
            postId: post._id.toString(),
            reason: 'POST_PENDING_MEDIA_REVIEW',
            mediaModerationScore: mediaSummary.maxScore,
            mediaModerationLabel: mediaSummary.topLabel,
            message: `Bài đăng mới của ${author.displayName || author.username || 'một người dùng'} đang chờ duyệt vì hình ảnh nhạy cảm.`,
            navigationTarget: {
              route: 'ADMIN_POSTS_PENDING',
              postId: post._id.toString(),
            },
          },
        });
      }
    } else {
      emitGlobal('feed:changed', {
        reason: 'post_created',
        postId: post._id.toString(),
      });

      // Notify group members (besides the author) about the new group post.
      if (resolvedGroupId) {
        const memberIds = (
          await GroupMember.find({
            groupId: resolvedGroupId,
            status: 'ACTIVE',
          }).select('userId')
        )
          .map((m) => m.userId.toString())
          .filter((id) => id !== req.user.id);
        const group = await Group.findById(resolvedGroupId).select('name');
        if (memberIds.length > 0 && group) {
          await broadcastNotification({
            userIds: memberIds,
            actorId: req.user.id,
            type: NOTIFICATION_TYPES.GROUP_POST_CREATED,
            payload: {
              groupId: resolvedGroupId.toString(),
              groupName: group.name,
              postId: post._id.toString(),
              ...actorSnapshot(author),
              navigationTarget: {
                route: 'POST_DETAIL',
                postId: post._id.toString(),
              },
            },
          });
        }
      }
    }

    return res.status(201).json({
      message: needsReview
        ? 'Post created but is awaiting admin review because of a sensitive image.'
        : 'Post created.',
      post: await withPostMeta(post, req.user.id),
      moderation: {
        needsReview,
        mediaModerationScore: mediaSummary.maxScore,
        mediaModerationLabel: mediaSummary.topLabel,
        threshold: env.mediaModerationThreshold,
      },
    });
  }),
);

router.get(
  '/feed',
  asyncHandler(async (req, res) => {
    const q = String(req.query.q || '').trim();
    const topic = String(req.query.topic || '').trim();
    const age = req.query.age !== undefined ? Number(req.query.age) : req.user.age;
    const limit = Math.max(1, Math.min(100, Number(req.query.limit) || 50));
    const beforeRaw = String(req.query.before || '').trim();
    const beforeDate = beforeRaw ? new Date(beforeRaw) : null;
    if (beforeRaw && Number.isNaN(beforeDate.getTime())) {
      return res.status(400).json({ message: 'Invalid before cursor.' });
    }
    const scope = String(req.query.scope || 'all')
      .trim()
      .toLowerCase();

    const friendIds = await getFriendSet(req.user.id);
    friendIds.add(req.user.id);

    const myGroupIds = await GroupMember.find({
      userId: req.user.id,
      status: 'ACTIVE',
    }).distinct('groupId');

    const query = {
      status: 'PUBLISHED',
      ageMin: { $lte: age },
      ageMax: { $gte: age },
      $or: [
        { groupId: null },
        { groupId: { $in: myGroupIds } },
      ],
    };

    if (scope === 'friends') {
      query.audience = { $in: ['FRIENDS', 'GROUP'] };
      query.authorId = { $in: [...friendIds] };
    } else if (scope === 'public') {
      query.audience = 'PUBLIC';
    }

    if (topic) {
      query.topics = topic;
    }

    if (q) {
      query.$or = [
        { content: { $regex: q, $options: 'i' } },
        { topics: { $regex: q, $options: 'i' } },
      ];
    }

    if (beforeDate) {
      query.createdAt = { $lt: beforeDate };
    }

    const posts = await Post.find(query)
      .sort({ createdAt: -1 })
      .limit(limit + 1);
    const childAuthorPosts = await filterNonChildAuthorPosts(posts, req.user);

    const visible = childAuthorPosts.filter((post) => {
      if (post.audience === 'PUBLIC') {
        return true;
      }
      if (post.audience === 'GROUP') {
        const authorId = post.authorId.toString();
        const groupId = post.groupId ? post.groupId.toString() : '';
        return (
          myGroupIds.map((id) => id.toString()).includes(groupId) ||
          friendIds.has(authorId)
        );
      }
      return friendIds.has(post.authorId.toString());
    });

    const hasMore = visible.length > limit;
    const page = hasMore ? visible.slice(0, limit) : visible;
    const nextBefore = hasMore
      ? page[page.length - 1].createdAt.toISOString()
      : null;

    return res.json({
      items: await withPostMeta(page, req.user.id),
      nextBefore,
      hasMore,
    });
  }),
);

router.get(
  '/mine',
  asyncHandler(async (req, res) => {
    // The default view only shows posts the user has successfully
    // published. When `includePending=1` is set we also include
    // HIDDEN posts that are waiting for admin review, so the user
    // can tap into the "Đang chờ admin duyệt" banner from the
    // post detail screen and see them in their own list.
    const includePending = String(req.query.includePending || '').trim() === '1';
    const statusFilter = includePending
      ? { $in: ['PUBLISHED', 'HIDDEN'] }
      : 'PUBLISHED';
    const posts = await Post.find({
      authorId: req.user.id,
      status: statusFilter,
      groupId: null,
    })
      .sort({ createdAt: -1 })
      .limit(100);

    return res.json({ items: await withPostMeta(posts, req.user.id) });
  }),
);

router.get(
  '/:postId/reactions',
  asyncHandler(async (req, res) => {
    const { postId } = req.params;
    if (!isValidObjectId(postId)) {
      return res.status(400).json({ message: 'Invalid postId.' });
    }

    const reaction = String(req.query.reaction || '')
      .toLowerCase()
      .trim();
    if (reaction && !ALLOWED_REACTIONS.includes(reaction)) {
      return res.status(400).json({ message: 'Invalid reaction.' });
    }

    const post = await Post.findById(postId);
    if (!post || post.status !== 'PUBLISHED') {
      return res.status(404).json({ message: 'Post not found.' });
    }

    if (post.authorId.toString() !== req.user.id) {
      return res
        .status(403)
        .json({ message: 'Only the post owner can view reaction users.' });
    }

    const query = { postId };
    if (reaction) {
      query.reaction = reaction;
    }

    const rows = await PostReaction.find(query)
      .sort({ createdAt: -1 })
      .populate({
        path: 'userId',
        select:
          '_id displayName username age role avatarUrl coverUrl bio favoriteTopics privacy lastActiveAt isActive',
      });

    const items = rows
      .map((row) => {
        const user = row.userId;
        if (!user || user.isActive === false) {
          return null;
        }

        return {
          reaction: row.reaction,
          reactedAt: row.createdAt,
          user: {
            id: user._id.toString(),
            displayName: user.displayName,
            username: user.username,
            age: user.age,
            role: user.role,
            avatarUrl: user.avatarUrl || '',
            coverUrl: user.coverUrl || '',
            bio: user.bio || '',
            favoriteTopics: user.favoriteTopics || [],
            privacy: user.privacy || {},
            lastActiveAt: user.lastActiveAt || null,
          },
        };
      })
      .filter(Boolean);

    return res.json({ items });
  }),
);

router.post(
  '/:postId/like',
  asyncHandler(async (req, res) => {
    const { postId } = req.params;
    if (!isValidObjectId(postId)) {
      return res.status(400).json({ message: 'Invalid postId.' });
    }

    const requestedReaction = String(req.body.reaction || 'heart')
      .toLowerCase()
      .trim();
    const reaction = ALLOWED_REACTIONS.includes(requestedReaction)
      ? requestedReaction
      : 'heart';

    const post = await Post.findById(postId);
    if (!post || post.status !== 'PUBLISHED') {
      return res.status(404).json({ message: 'Post not found.' });
    }

    if (req.user.role === 'CHILD') {
      const author = await User.findById(post.authorId).select('role isActive');
      if (!author || author.role !== 'CHILD' || !author.isActive) {
        return res.status(404).json({ message: 'Post not found.' });
      }
    }
    if (!post.allowReactions) {
      return res.status(403).json({ message: 'Reactions are disabled.' });
    }

    const existing = await PostReaction.findOne({
      postId,
      userId: req.user.id,
    });

    let liked;
    let updated;
    let finalReaction = reaction;

    if (existing) {
      if (existing.reaction === reaction) {
        // Toggle off when user taps the same reaction again.
        await PostReaction.deleteOne({ _id: existing._id });
        updated = await Post.findByIdAndUpdate(
          postId,
          { $inc: { reactionCount: -1 } },
          { new: true },
        );
        if (updated.reactionCount < 0) {
          updated.reactionCount = 0;
          await updated.save();
        }
        liked = false;
        finalReaction = null;
      } else {
        // Switch reaction in place; count remains the same.
        existing.reaction = reaction;
        await existing.save();
        updated = await Post.findById(postId);
        liked = true;
      }
    } else {
      let createdReaction = false;
      try {
        await PostReaction.create({
          postId,
          userId: req.user.id,
          reaction,
        });
        createdReaction = true;
      } catch (error) {
        if (error.code !== 11000) {
          throw error;
        }
      }
      updated = createdReaction
        ? await Post.findByIdAndUpdate(
            postId,
            { $inc: { reactionCount: 1 } },
            { new: true },
          )
        : await Post.findById(postId);
      liked = true;
    }

    const breakdown = await PostReaction.aggregate([
      { $match: { postId: post._id } },
      { $group: { _id: '$reaction', count: { $sum: 1 } } },
    ]);
    const reactions = breakdown.reduce((acc, item) => {
      acc[item._id] = item.count;
      return acc;
    }, {});

    const payload = {
      postId,
      liked,
      reaction: finalReaction,
      reactions,
      reactionCount: updated.reactionCount,
      userId: req.user.id,
    };
    emitGlobal('post:liked', payload);

    // Notify the post author when somebody reacts to their post.
    // We skip self-reactions (toggle off when removing) and avoid
    // spam by only firing on the "first like" — i.e. when this
    // request caused the reactionCount to grow.
    if (liked && finalReaction && post.authorId.toString() !== req.user.id) {
      const reactor = await User.findById(req.user.id).select(
        'displayName username avatarUrl',
      );
      await sendNotification({
        userId: post.authorId,
        actorId: req.user.id,
        type: NOTIFICATION_TYPES.POST_LIKED,
        payload: {
          postId,
          reaction: finalReaction,
          contentSnippet: String(post.content || '').slice(0, 140),
          ...(reactor ? actorSnapshot(reactor) : {}),
          navigationTarget: {
            route: 'POST_DETAIL',
            postId,
          },
        },
      });
    }

    return res.json({
      message: liked ? 'Reaction saved.' : 'Reaction removed.',
      ...payload,
    });
  }),
);

router.post(
  '/:postId/bookmark',
  asyncHandler(async (req, res) => {
    const { postId } = req.params;
    if (!isValidObjectId(postId)) {
      return res.status(400).json({ message: 'Invalid postId.' });
    }

    const post = await Post.findById(postId);
    if (!post || post.status !== 'PUBLISHED') {
      return res.status(404).json({ message: 'Post not found.' });
    }

    let bookmarked;
    try {
      await PostBookmark.create({ postId, userId: req.user.id });
      bookmarked = true;
    } catch (error) {
      if (error.code !== 11000) {
        throw error;
      }
      bookmarked = true;
    }

    return res.json({
      message: bookmarked ? 'Post bookmarked.' : 'Post already bookmarked.',
      postId,
      bookmarked,
    });
  }),
);

router.delete(
  '/:postId/bookmark',
  asyncHandler(async (req, res) => {
    const { postId } = req.params;
    if (!isValidObjectId(postId)) {
      return res.status(400).json({ message: 'Invalid postId.' });
    }

    const result = await PostBookmark.deleteOne({
      postId,
      userId: req.user.id,
    });

    return res.json({
      message: 'Post removed from bookmarks.',
      postId,
      bookmarked: false,
      removed: result.deletedCount > 0,
    });
  }),
);

router.get(
  '/bookmarks/me',
  asyncHandler(async (req, res) => {
    const limit = Math.max(1, Math.min(50, Number(req.query.limit) || 20));
    const beforeRaw = String(req.query.before || '').trim();
    const beforeDate = beforeRaw ? new Date(beforeRaw) : null;
    if (beforeRaw && Number.isNaN(beforeDate.getTime())) {
      return res.status(400).json({ message: 'Invalid before cursor.' });
    }

    const query = { userId: req.user.id };
    if (beforeDate) {
      query.createdAt = { $lt: beforeDate };
    }

    const bookmarks = await PostBookmark.find(query)
      .sort({ createdAt: -1 })
      .limit(limit + 1);
    const hasMore = bookmarks.length > limit;
    const page = hasMore ? bookmarks.slice(0, limit) : bookmarks;

    if (page.length === 0) {
      return res.json({ items: [], nextBefore: null, hasMore: false });
    }

    const postIds = page.map((bookmark) => bookmark.postId);
    const posts = await Post.find({ _id: { $in: postIds } });
    const items = await withPostMeta(posts, req.user.id);

    const ordered = postIds
      .map((id) => items.find((post) => post._id.toString() === id.toString()))
      .filter(Boolean);

    const nextBefore = hasMore
      ? new Date(page[page.length - 1].createdAt).toISOString()
      : null;

    return res.json({ items: ordered, nextBefore, hasMore });
  }),
);

router.get(
  '/:postId',
  asyncHandler(async (req, res) => {
    const { postId } = req.params;
    if (!isValidObjectId(postId)) {
      return res.status(400).json({ message: 'Invalid postId.' });
    }

    const post = await Post.findById(postId);
    if (!post || post.status !== 'PUBLISHED') {
      return res.status(404).json({ message: 'Post not found.' });
    }

    if (req.user.age < post.ageMin || req.user.age > post.ageMax) {
      return res.status(403).json({ message: 'This post is outside your age range.' });
    }

    if (post.audience === 'FRIENDS' && post.authorId.toString() !== req.user.id) {
      const pair = normalizeFriendPair(req.user.id, post.authorId);
      const friendship = await Friendship.findOne(pair);
      if (!friendship) {
        return res.status(403).json({ message: 'This post is for friends only.' });
      }
    }

    if (post.audience === 'GROUP' && post.groupId) {
      const membership = await GroupMember.findOne({
        groupId: post.groupId,
        userId: req.user.id,
        status: 'ACTIVE',
      });
      if (!membership && post.authorId.toString() !== req.user.id) {
        return res
          .status(403)
          .json({ message: 'You must join the group to view this post.' });
      }
    }

    return res.json({ post: await withPostMeta(post, req.user.id) });
  }),
);

router.patch(
  '/:postId',
  asyncHandler(async (req, res) => {
    const { postId } = req.params;
    if (!isValidObjectId(postId)) {
      return res.status(400).json({ message: 'Invalid postId.' });
    }

    const post = await Post.findById(postId);
    if (!post || post.status === 'DELETED') {
      return res.status(404).json({ message: 'Post not found.' });
    }
    if (post.authorId.toString() !== req.user.id) {
      return res.status(403).json({ message: 'Only author can update this post.' });
    }

    if (req.body.content !== undefined) {
      await assertContentAllowed({
        text: req.body.content,
        userId: req.user.id,
        targetType: 'POST',
        targetId: postId,
        action: 'edit a post',
      });
    }

    const allowedFields = [
      'content',
      'topics',
      'mood',
      'mediaUrls',
      'audience',
      'allowComments',
      'allowReactions',
      'ageMin',
      'ageMax',
    ];
    const update = {};
    for (const field of allowedFields) {
      if (req.body[field] !== undefined) {
        update[field] = req.body[field];
      }
    }

    const updated = await Post.findByIdAndUpdate(
      postId,
      { $set: update },
      { new: true, runValidators: true },
    );

    emitToPost(postId, 'post:updated', {
      post: await withPostMeta(updated, req.user.id),
    });
    emitGlobal('feed:changed', {
      reason: 'post_updated',
      postId,
    });

    return res.json({
      message: 'Post updated.',
      post: await withPostMeta(updated, req.user.id),
    });
  }),
);

router.delete(
  '/:postId',
  asyncHandler(async (req, res) => {
    const { postId } = req.params;
    if (!isValidObjectId(postId)) {
      return res.status(400).json({ message: 'Invalid postId.' });
    }

    const post = await Post.findById(postId);
    if (!post || post.status === 'DELETED') {
      return res.status(404).json({ message: 'Post not found.' });
    }
    if (post.authorId.toString() !== req.user.id && req.user.role === 'CHILD') {
      return res.status(403).json({ message: 'Only author can delete this post.' });
    }

    post.status = 'DELETED';
    await post.save();

    emitGlobal('feed:changed', { reason: 'post_deleted', postId });

    return res.json({ message: 'Post deleted (soft delete).' });
  }),
);

module.exports = router;
