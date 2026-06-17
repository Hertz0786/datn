const express = require('express');

const Report = require('../models/Report');
const Notification = require('../models/Notification');
const User = require('../models/User');
const asyncHandler = require('../utils/async-handler');
const { requireAuth, requireRole } = require('../middlewares/auth');
const { isValidObjectId } = require('../middlewares/object-id');
const {
  sendNotification,
  broadcastNotification,
  NOTIFICATION_TYPES,
} = require('../services/notification-service');
const { emitToUser } = require('../realtime/socket');

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

router.get(
  '/reports/moderation',
  requireAuth,
  requireRole('MODERATOR', 'ADMIN'),
  asyncHandler(async (req, res) => {
    const status = req.query.status ? String(req.query.status) : undefined;
    const query = status ? { status } : {};
    const items = await Report.find(query).sort({ urgency: -1, createdAt: -1 });
    return res.json({ items });
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
      { new: true, runValidators: true },
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
