const express = require('express');
const multer = require('multer');

const Comment = require('../models/Comment');
const Group = require('../models/Group');
const MediaAsset = require('../models/MediaAsset');
const Message = require('../models/Message');
const Post = require('../models/Post');
const asyncHandler = require('../utils/async-handler');
const { requireAuth } = require('../middlewares/auth');
const { isValidObjectId } = require('../middlewares/object-id');
const { attachMediaToSource, detachMediaFromSource } = require('../services/media-attachment');
const { assertMediaAllowed } = require('../services/ai-media-moderation');
const { destroyMediaAsset, uploadBuffer } = require('../services/media-storage');
const env = require('../config/env');
const FlaggedContent = require('../models/FlaggedContent');
const { emitGlobal } = require('../realtime/socket');

const router = express.Router();

const allowedSourceTypes = new Set([
  'PROFILE',
  'PROFILE_COVER',
  'POST',
  'COMMENT',
  'MESSAGE',
  'GROUP',
  'OTHER',
]);

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 25 * 1024 * 1024,
  },
  fileFilter: (req, file, callback) => {
    if (/^(image|video|audio)\//.test(file.mimetype)) {
      callback(null, true);
      return;
    }

    // Fallback: some clients (notably Flutter on Android) send an empty
    // mimetype or "application/octet-stream" for image files. Trust the
    // extension as a last resort so legitimate uploads are not rejected.
    const allowedExt = /\.(jpe?g|png|gif|webp|bmp|heic|heif|svg|mp4|mov|webm|mkv|m4a|mp3|aac|opus|ogg|wav|flac)$/i;
    if (file.originalname && allowedExt.test(file.originalname)) {
      callback(null, true);
      return;
    }

    callback(new Error('Only image, video, and audio files are allowed.'));
  },
});

router.use(requireAuth);

function uploadSingle(req, res, next) {
  upload.single('file')(req, res, (error) => {
    if (!error) {
      next();
      return;
    }

    const message =
      error instanceof multer.MulterError && error.code === 'LIMIT_FILE_SIZE'
        ? 'File size must be 25MB or less.'
        : error.message;
    res.status(400).json({ message });
  });
}

function normalizeSourceType(value) {
  const sourceType = String(value || 'OTHER').trim().toUpperCase();
  return allowedSourceTypes.has(sourceType) ? sourceType : 'OTHER';
}

function createHttpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function canManageSource(req, ownerId) {
  return ownerId.toString() === req.user.id || req.user.role !== 'CHILD';
}

async function validateSource(req, sourceType, rawSourceId) {
  if (sourceType === 'PROFILE' || sourceType === 'PROFILE_COVER') {
    return req.user.id;
  }

  if (sourceType === 'OTHER') {
    return null;
  }

  if (!isValidObjectId(rawSourceId)) {
    throw createHttpError(400, 'Valid sourceId is required.');
  }

  if (sourceType === 'POST') {
    const post = await Post.findById(rawSourceId);
    if (!post || post.status === 'DELETED') {
      throw createHttpError(404, 'Post not found.');
    }
    if (!canManageSource(req, post.authorId)) {
      throw createHttpError(403, 'Not allowed to attach media to this post.');
    }
    return post._id;
  }

  if (sourceType === 'COMMENT') {
    const comment = await Comment.findById(rawSourceId);
    if (!comment || comment.status === 'DELETED') {
      throw createHttpError(404, 'Comment not found.');
    }
    if (!canManageSource(req, comment.authorId)) {
      throw createHttpError(403, 'Not allowed to attach media to this comment.');
    }
    return comment._id;
  }

  if (sourceType === 'MESSAGE') {
    const message = await Message.findById(rawSourceId);
    if (!message || message.status === 'DELETED') {
      throw createHttpError(404, 'Message not found.');
    }
    if (!canManageSource(req, message.senderId)) {
      throw createHttpError(403, 'Not allowed to attach media to this message.');
    }
    return message._id;
  }

  if (sourceType === 'GROUP') {
    const group = await Group.findById(rawSourceId);
    if (!group || group.status !== 'ACTIVE') {
      throw createHttpError(404, 'Group not found.');
    }
    if (!canManageSource(req, group.ownerId)) {
      throw createHttpError(403, 'Only the group owner can update group media.');
    }
    return group._id;
  }

  return rawSourceId;
}

function serializeMediaAsset(asset) {
  const owner =
    asset.ownerId && typeof asset.ownerId === 'object'
      ? asset.ownerId
      : null;

  return {
    id: asset._id.toString(),
    ownerId: owner?._id?.toString() || asset.ownerId?.toString() || '',
    owner: owner?.displayName || owner?.username || '',
    sourceType: asset.sourceType,
    source: asset.sourceType,
    sourceId: asset.sourceId?.toString() || '',
    publicId: asset.publicId,
    url: asset.secureUrl,
    secureUrl: asset.secureUrl,
    resourceType: asset.resourceType,
    format: asset.format,
    bytes: asset.bytes,
    width: asset.width,
    height: asset.height,
    duration: asset.duration,
    status: asset.status,
    moderation: asset.moderation || {},
    createdAt: asset.createdAt,
    updatedAt: asset.updatedAt,
  };
}

router.post(
  '/upload',
  uploadSingle,
  asyncHandler(async (req, res) => {
    if (!req.file) {
      return res.status(400).json({ message: 'file is required.' });
    }

    const sourceType = normalizeSourceType(req.body.sourceType);
    const sourceId = await validateSource(req, sourceType, req.body.sourceId);
    const isAudio = /^audio\//.test(req.file.mimetype) ||
      /\.(m4a|mp3|aac|opus|ogg|wav|flac)$/i.test(req.file.originalname);
    const moderation = isAudio
      ? { decision: 'SKIPPED', skippedReason: 'Audio files are not moderated.' }
      : await assertMediaAllowed(req.file);
    const uploaded = await uploadBuffer(req.file, {
      sourceType,
      ownerId: req.user.id,
    });

    const aiDecision = moderation.decision || 'APPROVED';
    let assetStatus = 'APPROVED';
    if (aiDecision === 'REVIEW') assetStatus = 'REVIEW';
    else if (aiDecision === 'BLOCKED') assetStatus = 'BLOCKED';

    const asset = await MediaAsset.create({
      ownerId: req.user.id,
      sourceType,
      sourceId,
      publicId: uploaded.public_id,
      secureUrl: uploaded.secure_url,
      resourceType: uploaded.resource_type === 'video' ? 'video' : 'image',
      format: uploaded.format || '',
      originalFilename: req.file.originalname || '',
      mimeType: req.file.mimetype || '',
      bytes: Number(uploaded.bytes || req.file.size || 0),
      width: Number(uploaded.width || 0),
      height: Number(uploaded.height || 0),
      duration: Number(uploaded.duration || 0),
      status: assetStatus,
      moderation,
    });

    if (assetStatus === 'REVIEW' || assetStatus === 'BLOCKED') {
      const flag = await FlaggedContent.create({
        sourceType: 'MEDIA',
        sourceId: asset._id.toString(),
        flaggedBy: 'CNN_SERVICE',
        categories: [moderation.unsafeLabel || moderation.topLabel || 'unsafe'],
        score: Number(moderation.unsafeScore || 0),
        details: {
          aiDecision,
          assetStatus,
          topLabel: moderation.topLabel,
          topScore: moderation.topScore,
          unsafeLabel: moderation.unsafeLabel,
          unsafeScore: moderation.unsafeScore,
          thresholds: moderation.details?.thresholds || {},
        },
        status: 'PENDING',
      });

      emitGlobal('moderation:flagged', {
        reason: assetStatus === 'BLOCKED' ? 'ai_media_blocked' : 'ai_media_review',
        flagId: flag._id.toString(),
        mediaId: asset._id.toString(),
        mediaUrl: asset.secureUrl,
        decision: aiDecision,
        assetStatus,
        unsafeLabel: moderation.unsafeLabel,
        unsafeScore: moderation.unsafeScore,
        ownerId: req.user.id,
      });
    }

    await attachMediaToSource(asset);

    let userMessage = 'Media uploaded.';
    if (assetStatus === 'REVIEW') {
      userMessage = 'Media uploaded but is awaiting admin review.';
    } else if (assetStatus === 'BLOCKED') {
      userMessage = 'Media was blocked by AI moderation and is awaiting admin review.';
    }

    // Surface the AI score + whether it crossed the auto-publish
    // threshold so the client (and the admin UI) can render a
    // helpful message without re-fetching the asset. We only flag
    // the asset as "threshold exceeded" for images — videos use the
    // multi-frame score from the moderation service, and we still
    // treat them as "needs review" the same way.
    const score = Number(moderation.unsafeScore || 0);
    const threshold = env.mediaModerationThreshold;
    const thresholdExceeded =
      assetStatus !== 'APPROVED' && score >= threshold;

    return res.status(201).json({
      message: userMessage,
      media: serializeMediaAsset(asset),
      moderation: {
        status: assetStatus,
        decision: aiDecision,
        unsafeLabel: moderation.unsafeLabel,
        unsafeScore: score,
        topLabel: moderation.topLabel,
        topScore: Number(moderation.topScore || 0),
        threshold,
        thresholdExceeded,
      },
    });
  }),
);

router.get(
  '/me',
  asyncHandler(async (req, res) => {
    const assets = await MediaAsset.find({
      ownerId: req.user.id,
      status: { $ne: 'REMOVED' },
    })
      .sort({ createdAt: -1 })
      .limit(100);

    return res.json({ items: assets.map(serializeMediaAsset) });
  }),
);

router.patch(
  '/:mediaId/source',
  asyncHandler(async (req, res) => {
    const { mediaId } = req.params;
    if (!isValidObjectId(mediaId)) {
      return res.status(400).json({ message: 'Invalid mediaId.' });
    }

    const asset = await MediaAsset.findById(mediaId);
    if (!asset || asset.status === 'REMOVED') {
      return res.status(404).json({ message: 'Media not found.' });
    }
    if (!canManageSource(req, asset.ownerId)) {
      return res.status(403).json({ message: 'Not allowed to update this media.' });
    }

    const sourceType = normalizeSourceType(req.body.sourceType);
    const sourceId = await validateSource(req, sourceType, req.body.sourceId);

    const previousSourceType = asset.sourceType;
    const previousSourceId = asset.sourceId;
    asset.sourceType = sourceType;
    asset.sourceId = sourceId;
    await asset.save();

    if (
      previousSourceType !== sourceType ||
      previousSourceId?.toString() !== sourceId?.toString()
    ) {
      await attachMediaToSource(asset);
    }

    return res.json({
      message: 'Media source updated.',
      media: serializeMediaAsset(asset),
    });
  }),
);

router.delete(
  '/:mediaId',
  asyncHandler(async (req, res) => {
    const { mediaId } = req.params;
    if (!isValidObjectId(mediaId)) {
      return res.status(400).json({ message: 'Invalid mediaId.' });
    }

    const asset = await MediaAsset.findById(mediaId);
    if (!asset || asset.status === 'REMOVED') {
      return res.status(404).json({ message: 'Media not found.' });
    }

    if (!canManageSource(req, asset.ownerId)) {
      return res.status(403).json({ message: 'Not allowed to delete this media.' });
    }

    await detachMediaFromSource(asset);
    await destroyMediaAsset(asset);

    asset.status = 'REMOVED';
    await asset.save();

    return res.json({ message: 'Media removed.' });
  }),
);

module.exports = router;
