const express = require('express');

const Post = require('../models/Post');
const User = require('../models/User');
const Comment = require('../models/Comment');
const CommentReaction = require('../models/CommentReaction');
const asyncHandler = require('../utils/async-handler');
const { requireAuth } = require('../middlewares/auth');
const { isValidObjectId } = require('../middlewares/object-id');
const { assertContentAllowed } = require('../services/content-moderation');
const {
  sendNotification,
  NOTIFICATION_TYPES,
} = require('../services/notification-service');
const { emitGlobal, emitToPost } = require('../realtime/socket');
const { toPublicUser } = require('../utils/public-user');

const router = express.Router();

router.use(requireAuth);

function actorSnapshot(user) {
  return {
    actorId: user._id.toString(),
    actorName: user.displayName || user.username || 'Ai đó',
    actorUsername: user.username || '',
    actorAvatarUrl: user.avatarUrl || '',
  };
}

function readMediaUrls(value) {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.map((item) => String(item).trim()).filter(Boolean);
}

async function withCommentMeta(comments, userId) {
  const commentList = Array.isArray(comments) ? comments : [comments];
  const commentIds = [];

  for (const comment of commentList) {
    commentIds.push(comment._id);
    for (const reply of comment.replies || []) {
      commentIds.push(reply._id);
    }
  }

  const reactions = await CommentReaction.find({
    commentId: { $in: commentIds },
    userId,
  }).select('commentId');
  const likedCommentIds = new Set(
    reactions.map((reaction) => reaction.commentId.toString()),
  );

  // Refresh author lastActiveAt from the User collection so the
  // "online" indicator on comment avatars reflects the user's real
  // activity, not the snapshot taken at comment-creation time.
  const authorIds = new Set();
  for (const comment of commentList) {
    authorIds.add(comment.authorId.toString());
    for (const reply of comment.replies || []) {
      authorIds.add(reply.authorId.toString());
    }
  }
  const authorDocs = authorIds.size
    ? await User.find({ _id: { $in: [...authorIds] } }).select(
        '_id displayName username avatarUrl role lastActiveAt',
      )
    : [];
  const authorById = new Map(
    authorDocs.map((doc) => [doc._id.toString(), doc]),
  );

  const enrichSnapshot = (snap, authorId) => {
    const current = authorById.get(authorId.toString());
    return {
      ...(snap || {}),
      displayName: current?.displayName || snap?.displayName || '',
      username: current?.username || snap?.username || '',
      avatarUrl: current?.avatarUrl || snap?.avatarUrl || '',
      role: current?.role || snap?.role || '',
      lastActiveAt: current?.lastActiveAt || snap?.lastActiveAt || null,
    };
  };

  const items = commentList.map((comment) => {
    const commentObject =
      typeof comment.toObject === 'function' ? comment.toObject() : comment;
    return {
      ...commentObject,
      likedByMe: likedCommentIds.has(comment._id.toString()),
      authorSnapshot: enrichSnapshot(comment.authorSnapshot, comment.authorId),
      replies: (comment.replies || []).map((reply) => {
        const replyObject =
          typeof reply.toObject === 'function' ? reply.toObject() : reply;
        return {
          ...replyObject,
          likedByMe: likedCommentIds.has(reply._id.toString()),
          authorSnapshot: enrichSnapshot(reply.authorSnapshot, reply.authorId),
        };
      }),
    };
  });

  return Array.isArray(comments) ? items : items[0];
}

router.get(
  '/posts/:postId',
  asyncHandler(async (req, res) => {
    const { postId } = req.params;
    if (!isValidObjectId(postId)) {
      return res.status(400).json({ message: 'Invalid postId.' });
    }

    const comments = await Comment.find({
      postId,
      status: 'PUBLISHED',
    }).sort({ createdAt: 1 });

    const parentComments = [];
    const childrenMap = new Map();

    for (const comment of comments) {
      if (!comment.parentCommentId) {
        parentComments.push(comment);
        continue;
      }

      const key = comment.parentCommentId.toString();
      const current = childrenMap.get(key) || [];
      current.push(comment);
      childrenMap.set(key, current);
    }

    const items = parentComments.map((item) => ({
      ...item.toObject(),
      replies: childrenMap.get(item._id.toString()) || [],
    }));

    return res.json({ items: await withCommentMeta(items, req.user.id) });
  }),
);

router.post(
  '/posts/:postId',
  asyncHandler(async (req, res) => {
    const { postId } = req.params;
    const { content = '' } = req.body;
    const mediaUrls = readMediaUrls(req.body.mediaUrls);
    const cleanContent = String(content).trim();

    if (!isValidObjectId(postId)) {
      return res.status(400).json({ message: 'Invalid postId.' });
    }
    if (!cleanContent && mediaUrls.length === 0) {
      return res.status(400).json({ message: 'content or mediaUrls is required.' });
    }

    if (cleanContent) {
      await assertContentAllowed({
        text: cleanContent,
        userId: req.user.id,
        targetType: 'COMMENT',
        targetId: `blocked-comment:${postId}:${req.user.id}:${Date.now()}`,
        action: 'add a comment',
      });
    }

    const post = await Post.findById(postId);
    if (!post || post.status !== 'PUBLISHED') {
      return res.status(404).json({ message: 'Post not found.' });
    }
    if (!post.allowComments) {
      return res.status(403).json({ message: 'Comments are disabled for this post.' });
    }

    const author = await User.findById(req.user.id);
    if (!author) {
      return res.status(404).json({ message: 'User not found.' });
    }

    const comment = await Comment.create({
      postId,
      authorId: req.user.id,
      authorSnapshot: {
        displayName: author.displayName,
        username: author.username,
        avatarUrl: author.avatarUrl,
        lastActiveAt: author.lastActiveAt || null,
      },
      parentCommentId: null,
      content: cleanContent,
      mediaUrls,
    });

    const updatedPost = await Post.findByIdAndUpdate(
      postId,
      { $inc: { commentCount: 1 } },
      { returnNewDocument: true },
    );

    emitToPost(postId, 'comment:created', {
      postId,
      comment: await withCommentMeta(comment.toObject(), req.user.id),
      commentCount: updatedPost.commentCount,
    });
    emitGlobal('post:comment_count', {
      postId,
      commentCount: updatedPost.commentCount,
    });

    if (post.authorId.toString() !== req.user.id) {
      await sendNotification({
        userId: post.authorId,
        actorId: req.user.id,
        type: NOTIFICATION_TYPES.COMMENT_CREATED,
        payload: {
          postId,
          commentId: comment._id.toString(),
          contentSnippet: cleanContent.slice(0, 200),
          ...actorSnapshot(author),
          navigationTarget: {
            route: 'POST_DETAIL',
            postId,
            commentId: comment._id.toString(),
          },
        },
      });
    }

    return res.status(201).json({
      message: 'Comment added.',
      comment: await withCommentMeta(comment.toObject(), req.user.id),
    });
  }),
);

router.post(
  '/:commentId/replies',
  asyncHandler(async (req, res) => {
    const { commentId } = req.params;
    const { content = '' } = req.body;
    const mediaUrls = readMediaUrls(req.body.mediaUrls);
    const cleanContent = String(content).trim();

    if (!isValidObjectId(commentId)) {
      return res.status(400).json({ message: 'Invalid commentId.' });
    }
    if (!cleanContent && mediaUrls.length === 0) {
      return res.status(400).json({ message: 'content or mediaUrls is required.' });
    }

    if (cleanContent) {
      await assertContentAllowed({
        text: cleanContent,
        userId: req.user.id,
        targetType: 'COMMENT',
        targetId: `blocked-reply:${commentId}:${req.user.id}:${Date.now()}`,
        action: 'reply to a comment',
      });
    }

    const parent = await Comment.findById(commentId);
    if (!parent || parent.status !== 'PUBLISHED') {
      return res.status(404).json({ message: 'Parent comment not found.' });
    }

    const post = await Post.findById(parent.postId);
    if (!post || post.status !== 'PUBLISHED') {
      return res.status(404).json({ message: 'Post not found.' });
    }
    if (!post.allowComments) {
      return res.status(403).json({ message: 'Comments are disabled for this post.' });
    }

    const author = await User.findById(req.user.id);
    if (!author) {
      return res.status(404).json({ message: 'User not found.' });
    }

    const reply = await Comment.create({
      postId: parent.postId,
      authorId: req.user.id,
      authorSnapshot: {
        displayName: author.displayName,
        username: author.username,
        avatarUrl: author.avatarUrl,
        lastActiveAt: author.lastActiveAt || null,
      },
      parentCommentId: parent._id,
      content: cleanContent,
      mediaUrls,
    });

    const updatedPost = await Post.findByIdAndUpdate(
      parent.postId,
      { $inc: { commentCount: 1 } },
      { returnNewDocument: true },
    );

    emitToPost(parent.postId.toString(), 'comment:created', {
      postId: parent.postId.toString(),
      parentCommentId: parent._id.toString(),
      comment: await withCommentMeta(reply.toObject(), req.user.id),
      commentCount: updatedPost.commentCount,
    });
    emitGlobal('post:comment_count', {
      postId: parent.postId.toString(),
      commentCount: updatedPost.commentCount,
    });

    // Notify the parent comment's author that someone replied.
    if (parent.authorId.toString() !== req.user.id) {
      await sendNotification({
        userId: parent.authorId,
        actorId: req.user.id,
        type: NOTIFICATION_TYPES.COMMENT_REPLIED,
        payload: {
          postId: parent.postId.toString(),
          commentId: reply._id.toString(),
          parentCommentId: parent._id.toString(),
          contentSnippet: cleanContent.slice(0, 200),
          ...actorSnapshot(author),
          navigationTarget: {
            route: 'POST_DETAIL',
            postId: parent.postId.toString(),
            commentId: parent._id.toString(),
          },
        },
      });
    }

    // Also notify the post author when a reply is added (only if
    // they're not already being notified as the parent author).
    if (
      post.authorId.toString() !== req.user.id &&
      post.authorId.toString() !== parent.authorId.toString()
    ) {
      await sendNotification({
        userId: post.authorId,
        actorId: req.user.id,
        type: NOTIFICATION_TYPES.COMMENT_CREATED,
        payload: {
          postId: parent.postId.toString(),
          commentId: reply._id.toString(),
          parentCommentId: parent._id.toString(),
          contentSnippet: cleanContent.slice(0, 200),
          ...actorSnapshot(author),
          navigationTarget: {
            route: 'POST_DETAIL',
            postId: parent.postId.toString(),
            commentId: reply._id.toString(),
          },
        },
      });
    }

    return res.status(201).json({
      message: 'Reply added.',
      reply: await withCommentMeta(reply.toObject(), req.user.id),
    });
  }),
);

router.post(
  '/:commentId/like',
  asyncHandler(async (req, res) => {
    const { commentId } = req.params;
    if (!isValidObjectId(commentId)) {
      return res.status(400).json({ message: 'Invalid commentId.' });
    }

    const comment = await Comment.findById(commentId);
    if (!comment || comment.status !== 'PUBLISHED') {
      return res.status(404).json({ message: 'Comment not found.' });
    }

    const post = await Post.findById(comment.postId).select('allowReactions');
    if (!post || !post.allowReactions) {
      return res
        .status(403)
        .json({ message: 'Reactions are disabled for this post.' });
    }

    const existing = await CommentReaction.findOne({
      commentId,
      userId: req.user.id,
    });

    let liked;
    let updated;

    // Atomic operations: use findOneAndDelete to avoid race between
    // checking existence and writing.
    if (existing) {
      const deleted = await CommentReaction.findOneAndDelete({
        _id: existing._id,
        commentId,
        userId: req.user.id,
      });
      if (deleted) {
        updated = await Comment.findByIdAndUpdate(
          commentId,
          { $inc: { likeCount: -1 } },
          { returnNewDocument: true },
        );
        if (updated && updated.likeCount < 0) {
          updated.likeCount = 0;
          await updated.save();
        }
      } else {
        updated = await Comment.findById(commentId);
      }
      liked = false;
    } else {
      let createdReaction = false;
      try {
        await CommentReaction.create({
          commentId,
          userId: req.user.id,
          reaction: 'heart',
        });
        createdReaction = true;
      } catch (error) {
        if (error.code !== 11000) {
          throw error;
        }
      }
      updated = createdReaction
        ? await Comment.findByIdAndUpdate(
            commentId,
            { $inc: { likeCount: 1 } },
            { returnNewDocument: true },
          )
        : await Comment.findById(commentId);
      liked = true;
    }

    const payload = {
      postId: comment.postId.toString(),
      commentId,
      liked,
      likeCount: updated.likeCount,
      userId: req.user.id,
    };
    emitToPost(payload.postId, 'comment:liked', payload);

    if (liked && comment.authorId.toString() !== req.user.id) {
      const reactor = await User.findById(req.user.id).select(
        'displayName username avatarUrl',
      );
      await sendNotification({
        userId: comment.authorId,
        actorId: req.user.id,
        type: NOTIFICATION_TYPES.COMMENT_LIKED,
        payload: {
          postId: payload.postId,
          commentId,
          contentSnippet: String(comment.content || '').slice(0, 140),
          ...(reactor ? actorSnapshot(reactor) : {}),
          navigationTarget: {
            route: 'POST_DETAIL',
            postId: payload.postId,
            commentId,
          },
        },
      });
    }

    return res.json({
      message: liked ? 'Comment liked.' : 'Comment unliked.',
      ...payload,
    });
  }),
);

router.get(
  '/:commentId/reactions',
  asyncHandler(async (req, res) => {
    const { commentId } = req.params;
    if (!isValidObjectId(commentId)) {
      return res.status(400).json({ message: 'Invalid commentId.' });
    }

    const comment = await Comment.findById(commentId);
    if (!comment || comment.status !== 'PUBLISHED') {
      return res.status(404).json({ message: 'Comment not found.' });
    }

    if (comment.authorId.toString() !== req.user.id) {
      return res
        .status(403)
        .json({ message: 'Only the comment author can view reaction users.' });
    }

    const rows = await CommentReaction.find({ commentId })
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
          reactedAt: row.createdAt,
          user: toPublicUser(user),
        };
      })
      .filter(Boolean);

    return res.json({ items });
  }),
);

router.patch(
  '/:commentId',
  asyncHandler(async (req, res) => {
    const { commentId } = req.params;
    const { content = '' } = req.body;
    const mediaUrls = req.body.mediaUrls !== undefined ? readMediaUrls(req.body.mediaUrls) : null;
    const cleanContent = String(content).trim();

    if (!isValidObjectId(commentId)) {
      return res.status(400).json({ message: 'Invalid commentId.' });
    }
    if (!cleanContent && (mediaUrls == null || mediaUrls.length === 0)) {
      return res.status(400).json({ message: 'content or mediaUrls is required.' });
    }

    const comment = await Comment.findById(commentId);
    if (!comment || comment.status === 'DELETED') {
      return res.status(404).json({ message: 'Comment not found.' });
    }
    if (comment.authorId.toString() !== req.user.id) {
      return res.status(403).json({ message: 'Only author can edit this comment.' });
    }

    if (cleanContent) {
      await assertContentAllowed({
        text: cleanContent,
        userId: req.user.id,
        targetType: 'COMMENT',
        targetId: commentId,
        action: 'edit a comment',
      });
    }

    comment.content = cleanContent;
    if (mediaUrls != null) {
      comment.mediaUrls = mediaUrls;
    }
    await comment.save();

    emitToPost(comment.postId.toString(), 'comment:updated', {
      postId: comment.postId.toString(),
      comment: await withCommentMeta(comment.toObject(), req.user.id),
    });

    return res.json({ message: 'Comment updated.', comment });
  }),
);

router.delete(
  '/:commentId',
  asyncHandler(async (req, res) => {
    const { commentId } = req.params;
    if (!isValidObjectId(commentId)) {
      return res.status(400).json({ message: 'Invalid commentId.' });
    }

    const comment = await Comment.findById(commentId);
    if (!comment || comment.status === 'DELETED') {
      return res.status(404).json({ message: 'Comment not found.' });
    }

    const canDelete =
      comment.authorId.toString() === req.user.id || req.user.role !== 'CHILD';
    if (!canDelete) {
      return res.status(403).json({ message: 'Not enough permission to delete.' });
    }

    comment.status = 'DELETED';
    await comment.save();
    const updatedPost = await Post.findOneAndUpdate(
      { _id: comment.postId, commentCount: { $gt: 0 } },
      { $inc: { commentCount: -1 } },
      { returnNewDocument: true },
    );

    emitToPost(comment.postId.toString(), 'comment:deleted', {
      postId: comment.postId.toString(),
      commentId,
      commentCount: updatedPost?.commentCount ?? 0,
    });
    emitGlobal('post:comment_count', {
      postId: comment.postId.toString(),
      commentCount: updatedPost?.commentCount ?? 0,
    });

    const deletedByAdmin = req.user.role !== 'CHILD' && comment.authorId.toString() !== req.user.id;
    if (deletedByAdmin) {
      await sendNotification({
        userId: comment.authorId,
        actorId: req.user.id,
        type: NOTIFICATION_TYPES.COMMENT_DELETED,
        payload: {
          postId: comment.postId.toString(),
          commentId,
          contentSnippet: String(comment.content || '').slice(0, 200),
          navigationTarget: {
            route: 'POST_DETAIL',
            postId: comment.postId.toString(),
          },
        },
      });
    }

    return res.json({ message: 'Comment deleted (soft delete).' });
  }),
);

module.exports = router;
