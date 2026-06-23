const express = require('express');

const SupportMessage = require('../models/SupportMessage');
const SupportThread = require('../models/SupportThread');
const User = require('../models/User');
const asyncHandler = require('../utils/async-handler');
const { requireAuth } = require('../middlewares/auth');
const { isValidObjectId } = require('../middlewares/object-id');
const { emitToUser } = require('../realtime/socket');
const {
  sendNotification,
  broadcastNotification,
  NOTIFICATION_TYPES,
} = require('../services/notification-service');

const router = express.Router();

router.use(requireAuth);

const VALID_CATEGORIES = ['GENERAL', 'SAFETY', 'ACCOUNT', 'TECHNICAL', 'REPORT'];

function serializeMessage(message) {
  return {
    id: message._id.toString(),
    threadId: message.threadId.toString(),
    senderId: message.senderId.toString(),
    senderRole: message.senderRole,
    content: message.content,
    createdAt: message.createdAt,
  };
}

function serializeThread(thread, user = null) {
  return {
    id: thread._id.toString(),
    userId: thread.userId.toString(),
    user: user ? {
      id: user._id.toString(),
      displayName: user.displayName,
      username: user.username,
      age: user.age,
    } : null,
    subject: thread.subject,
    category: thread.category,
    status: thread.status,
    lastMessageAt: thread.lastMessageAt,
    createdAt: thread.createdAt,
    updatedAt: thread.updatedAt,
  };
}

function readCategory(value) {
  const category = String(value || 'GENERAL').toUpperCase();
  return VALID_CATEGORIES.includes(category) ? category : 'GENERAL';
}

function actorSnapshot(user) {
  return {
    actorId: user._id.toString(),
    actorName: user.displayName || user.username || 'Ai đó',
    actorUsername: user.username || '',
    actorAvatarUrl: user.avatarUrl || '',
  };
}

async function findOrCreateOpenThread(userId, { subject, category } = {}) {
  let thread = await SupportThread.findOne({
    userId,
    status: { $ne: 'RESOLVED' },
  }).sort({ lastMessageAt: -1 });

  if (!thread) {
    thread = await SupportThread.create({
      userId,
      subject: String(subject || 'Support request').trim() || 'Support request',
      category: readCategory(category),
      lastMessageAt: new Date(),
    });
  }

  return thread;
}

router.get(
  '/thread',
  asyncHandler(async (req, res) => {
    const thread = await findOrCreateOpenThread(req.user.id);
    const messages = await SupportMessage.find({ threadId: thread._id })
      .sort({ createdAt: 1 })
      .limit(200);

    return res.json({
      thread: serializeThread(thread),
      messages: messages.map(serializeMessage),
    });
  }),
);

router.post(
  '/messages',
  asyncHandler(async (req, res) => {
    const content = String(req.body.content || '').trim();
    if (!content) {
      return res.status(400).json({ message: 'content is required.' });
    }

    const thread = await findOrCreateOpenThread(req.user.id, {
      subject: req.body.subject,
      category: req.body.category,
    });

    const message = await SupportMessage.create({
      threadId: thread._id,
      senderId: req.user.id,
      senderRole: 'USER',
      content,
    });

    thread.status = 'OPEN';
    thread.lastMessageAt = message.createdAt;
    await thread.save();

    const admins = await User.find({
      role: { $in: ['ADMIN', 'MODERATOR'] },
      isActive: true,
    }).select('_id');

    const payload = {
      thread: serializeThread(thread),
      message: serializeMessage(message),
    };

    const sender = await User.findById(req.user.id).select(
      'displayName username avatarUrl',
    );

    for (const admin of admins) {
      emitToUser(admin._id.toString(), 'support:message', payload);
    }

    // Persist a notification for every admin so offline moderators
    // see the new ticket in their queue.
    if (admins.length > 0) {
      await broadcastNotification({
        userIds: admins.map((admin) => admin._id),
        actorId: req.user.id,
        type: NOTIFICATION_TYPES.SUPPORT_MESSAGE_RECEIVED,
        payload: {
          threadId: thread._id.toString(),
          subject: thread.subject,
          contentSnippet: content.slice(0, 240),
          ...(sender ? actorSnapshot(sender) : {}),
          navigationTarget: {
            route: 'ADMIN_SUPPORT',
            threadId: thread._id.toString(),
          },
        },
      });
    }

    return res.status(201).json(payload);
  }),
);

router.patch(
  '/thread/:threadId/resolve',
  asyncHandler(async (req, res) => {
    const { threadId } = req.params;
    if (!isValidObjectId(threadId)) {
      return res.status(400).json({ message: 'Invalid threadId.' });
    }

    const thread = await SupportThread.findOne({
      _id: threadId,
      userId: req.user.id,
    });
    if (!thread) {
      return res.status(404).json({ message: 'Support thread not found.' });
    }

    thread.status = 'RESOLVED';
    await thread.save();

    // Tell the user that they closed their own ticket.
    await sendNotification({
      userId: req.user.id,
      actorId: req.user.id,
      type: NOTIFICATION_TYPES.SUPPORT_STATUS_UPDATED,
      payload: {
        threadId: thread._id.toString(),
        subject: thread.subject,
        status: 'RESOLVED',
        navigationTarget: {
          route: 'SUPPORT',
          threadId: thread._id.toString(),
        },
      },
    });

    // Let admins know the thread was resolved.
    const admins = await User.find({
      role: { $in: ['ADMIN', 'MODERATOR'] },
      isActive: true,
    }).select('_id');
    if (admins.length > 0) {
    await broadcastNotification({
      userIds: admins.map((admin) => admin._id),
      actorId: req.user.id,
      type: NOTIFICATION_TYPES.SUPPORT_STATUS_UPDATED,
        payload: {
          threadId: thread._id.toString(),
          subject: thread.subject,
          status: 'RESOLVED',
          actorId: req.user.id,
          navigationTarget: {
            route: 'ADMIN_SUPPORT',
            threadId: thread._id.toString(),
          },
        },
      });
    }

    return res.json({ message: 'Support thread resolved.', thread: serializeThread(thread) });
  }),
);

module.exports = router;
