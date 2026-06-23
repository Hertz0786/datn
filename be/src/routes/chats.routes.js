const express = require('express');

const Chat = require('../models/Chat');
const Friendship = require('../models/Friendship');
const GroupMember = require('../models/GroupMember');
const Message = require('../models/Message');
const User = require('../models/User');
const asyncHandler = require('../utils/async-handler');
const { requireAuth } = require('../middlewares/auth');
const { isValidObjectId } = require('../middlewares/object-id');
const { normalizeFriendPair } = require('../utils/friendship');
const { buildChatSummaries, serializeMessage } = require('../utils/chat-summary');
const { assertContentAllowed } = require('../services/content-moderation');
const {
  sendNotification,
  broadcastNotification,
  NOTIFICATION_TYPES,
} = require('../services/notification-service');
const { emitToChat, emitToUser } = require('../realtime/socket');

const router = express.Router();

router.use(requireAuth);

function readMediaUrls(value) {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.map((item) => String(item).trim()).filter(Boolean);
}

function uniqueIds(ids) {
  return [...new Set(ids.map((id) => String(id || '').trim()).filter(Boolean))];
}

async function canUseChat(chat, userId) {
  if (chat.type === 'SOCIAL_GROUP') {
    if (!chat.groupId) {
      return false;
    }
    const membership = await GroupMember.findOne({
      groupId: chat.groupId,
      userId,
      status: 'ACTIVE',
    }).select('_id');
    return !!membership;
  }

  if (chat.type !== 'DIRECT') {
    return true;
  }

  const memberIds = chat.memberIds.map((memberId) => memberId.toString());
  const otherUserId = memberIds.find((memberId) => memberId !== userId);
  if (!otherUserId) {
    return false;
  }

  const friendship = await Friendship.findOne(
    normalizeFriendPair(userId, otherUserId),
  );
  return !!friendship;
}

async function assertFriendMembers(currentUserId, rawUserIds) {
  const userIds = uniqueIds(rawUserIds).filter((id) => id !== currentUserId);
  if (userIds.length === 0) {
    const error = new Error('Choose at least one friend.');
    error.statusCode = 400;
    throw error;
  }

  const invalidId = userIds.find((id) => !isValidObjectId(id));
  if (invalidId) {
    const error = new Error('Invalid member id.');
    error.statusCode = 400;
    throw error;
  }

  const users = await User.find({
    _id: { $in: userIds },
    isActive: true,
  }).select('_id');
  if (users.length !== userIds.length) {
    const error = new Error('One or more members were not found.');
    error.statusCode = 404;
    throw error;
  }

  const friendshipQueries = userIds.map((userId) =>
    normalizeFriendPair(currentUserId, userId),
  );
  const friendships = await Friendship.find({ $or: friendshipQueries }).select(
    'userAId userBId',
  );
  if (friendships.length !== userIds.length) {
    const error = new Error('You can only add friends to a group chat.');
    error.statusCode = 403;
    throw error;
  }

  return userIds;
}

function createHttpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function actorSnapshot(user) {
  return {
    actorId: user._id.toString(),
    actorName: user.displayName || user.username || 'Ai đó',
    actorUsername: user.username || '',
    actorAvatarUrl: user.avatarUrl || '',
  };
}

function chatTitle(chat) {
  return chat.title || (chat.type === 'DIRECT' ? 'Trò chuyện' : 'Nhóm chat');
}

router.post(
  '/direct',
  asyncHandler(async (req, res) => {
    const { targetUserId } = req.body;
    if (!isValidObjectId(targetUserId)) {
      return res.status(400).json({ message: 'Invalid targetUserId.' });
    }
    if (targetUserId === req.user.id) {
      return res.status(400).json({ message: 'Cannot create chat with yourself.' });
    }

    const target = await User.findById(targetUserId);
    if (!target || !target.isActive) {
      return res.status(404).json({ message: 'Target user not found.' });
    }

    const friendship = await Friendship.findOne(
      normalizeFriendPair(req.user.id, targetUserId),
    );
    if (!friendship) {
      return res.status(403).json({ message: 'You can only chat with friends.' });
    }

    const memberIds = [req.user.id, targetUserId].sort();

    let chat = await Chat.findOne({ type: 'DIRECT', memberIds });
    if (!chat) {
      chat = await Chat.create({
        type: 'DIRECT',
        memberIds,
        createdBy: req.user.id,
      });
    }

    const [summary] = await buildChatSummaries([chat], req.user.id);
    return res.status(201).json({ chat: summary });
  }),
);

router.post(
  '/group',
  asyncHandler(async (req, res) => {
    const title = String(req.body.title || '').trim();
    const avatarUrl = String(req.body.avatarUrl || '').trim();
    const memberIds = await assertFriendMembers(req.user.id, req.body.memberIds || []);

    if (!title) {
      return res.status(400).json({ message: 'Group chat title is required.' });
    }
    if (memberIds.length > 19) {
      return res.status(400).json({ message: 'A group chat can have up to 20 members.' });
    }

    const chat = await Chat.create({
      type: 'GROUP',
      title,
      avatarUrl,
      memberIds: [req.user.id, ...memberIds],
      createdBy: req.user.id,
    });

    const [summary] = await buildChatSummaries([chat], req.user.id);
    return res.status(201).json({ chat: summary });
  }),
);

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const limit = Math.max(1, Math.min(50, Number(req.query.limit) || 20));
    const beforeRaw = String(req.query.before || '').trim();
    const beforeDate = beforeRaw ? new Date(beforeRaw) : null;
    if (beforeRaw && Number.isNaN(beforeDate.getTime())) {
      return res.status(400).json({ message: 'Invalid before cursor.' });
    }

    const query = { memberIds: req.user.id };
    if (beforeDate) {
      query.updatedAt = { $lt: beforeDate };
    }

    const chats = await Chat.find(query)
      .sort({ updatedAt: -1 })
      .limit(limit + 1);
    const hasMore = chats.length > limit;
    const page = hasMore ? chats.slice(0, limit) : chats;
    const items = await buildChatSummaries(page, req.user.id);
    const nextBefore = hasMore
      ? new Date(page[page.length - 1].updatedAt).toISOString()
      : null;

    return res.json({ items, nextBefore, hasMore });
  }),
);

router.patch(
  '/:chatId/group',
  asyncHandler(async (req, res) => {
    const { chatId } = req.params;
    if (!isValidObjectId(chatId)) {
      return res.status(400).json({ message: 'Invalid chatId.' });
    }

    const chat = await Chat.findOne({ _id: chatId, type: 'GROUP', memberIds: req.user.id });
    if (!chat) {
      return res.status(404).json({ message: 'Group chat not found.' });
    }
    if (chat.createdBy.toString() !== req.user.id) {
      return res.status(403).json({ message: 'Only the group chat owner can update this chat.' });
    }

    const update = {};
    if (req.body.title !== undefined) {
      const title = String(req.body.title || '').trim();
      if (!title) {
        return res.status(400).json({ message: 'Group chat title is required.' });
      }
      update.title = title;
    }
    if (req.body.avatarUrl !== undefined) {
      update.avatarUrl = String(req.body.avatarUrl || '').trim();
    }

    if (Object.keys(update).length === 0) {
      const [summary] = await buildChatSummaries([chat], req.user.id);
      return res.json({ chat: summary });
    }

    const updated = await Chat.findByIdAndUpdate(
      chatId,
      { $set: update },
      { returnNewDocument: true, runValidators: true },
    );
    const [summary] = await buildChatSummaries([updated], req.user.id);
    return res.json({ message: 'Group chat updated.', chat: summary });
  }),
);

router.post(
  '/:chatId/members',
  asyncHandler(async (req, res) => {
    const { chatId } = req.params;
    if (!isValidObjectId(chatId)) {
      return res.status(400).json({ message: 'Invalid chatId.' });
    }

    const chat = await Chat.findOne({ _id: chatId, type: 'GROUP', memberIds: req.user.id });
    if (!chat) {
      return res.status(404).json({ message: 'Group chat not found.' });
    }
    if (chat.createdBy.toString() !== req.user.id) {
      return res.status(403).json({ message: 'Only the group chat owner can add members.' });
    }

    const existingIds = new Set(chat.memberIds.map((memberId) => memberId.toString()));
    const memberIds = (await assertFriendMembers(req.user.id, req.body.memberIds || []))
      .filter((userId) => !existingIds.has(userId));

    if (memberIds.length === 0) {
      const [summary] = await buildChatSummaries([chat], req.user.id);
      return res.json({ message: 'No new members to add.', chat: summary });
    }
    if (existingIds.size + memberIds.length > 20) {
      return res.status(400).json({ message: 'A group chat can have up to 20 members.' });
    }

    const updated = await Chat.findByIdAndUpdate(
      chatId,
      { $addToSet: { memberIds: { $each: memberIds } } },
      { returnNewDocument: true, runValidators: true },
    );

    // Notify every newly added member that they've been included.
    const adder = await User.findById(req.user.id).select(
      'displayName username avatarUrl',
    );
    for (const addedId of memberIds) {
      await sendNotification({
        userId: addedId,
        actorId: req.user.id,
        type: NOTIFICATION_TYPES.CHAT_MEMBER_ADDED,
        payload: {
          chatId,
          chatName: chatTitle(updated),
          ...(adder ? actorSnapshot(adder) : {}),
          navigationTarget: {
            route: 'CHAT_DETAIL',
            chatId,
          },
        },
      });
    }

    const [summary] = await buildChatSummaries([updated], req.user.id);
    return res.json({ message: 'Members added.', chat: summary });
  }),
);

router.delete(
  '/:chatId/members/:userId',
  asyncHandler(async (req, res) => {
    const { chatId, userId } = req.params;
    if (!isValidObjectId(chatId)) {
      return res.status(400).json({ message: 'Invalid chatId.' });
    }
    if (!isValidObjectId(userId)) {
      return res.status(400).json({ message: 'Invalid userId.' });
    }

    const chat = await Chat.findOne({ _id: chatId, type: 'GROUP', memberIds: req.user.id });
    if (!chat) {
      return res.status(404).json({ message: 'Group chat not found.' });
    }

    const memberIds = chat.memberIds.map((memberId) => memberId.toString());
    if (!memberIds.includes(userId)) {
      return res.status(404).json({ message: 'Member not found in this group chat.' });
    }

    const removingSelf = userId === req.user.id;
    const isOwner = chat.createdBy.toString() === req.user.id;
    if (!removingSelf && !isOwner) {
      return res.status(403).json({ message: 'Only the group chat owner can remove members.' });
    }
    if (memberIds.length <= 1) {
      return res.status(400).json({ message: 'A group chat must keep at least one member.' });
    }

    const remainingIds = memberIds.filter((memberId) => memberId !== userId);
    const update = { memberIds: remainingIds };
    if (chat.createdBy.toString() === userId) {
      update.createdBy = remainingIds[0];
    }

    const updated = await Chat.findByIdAndUpdate(
      chatId,
      { $set: update },
      { returnNewDocument: true, runValidators: true },
    );

    const remover = await User.findById(req.user.id).select(
      'displayName username avatarUrl',
    );
    if (!removingSelf) {
      await sendNotification({
        userId,
        actorId: req.user.id,
        type: NOTIFICATION_TYPES.CHAT_MEMBER_REMOVED,
        payload: {
          chatId,
          chatName: chatTitle(chat),
          ...(remover ? actorSnapshot(remover) : {}),
          navigationTarget: {
            route: 'MESSAGES',
          },
        },
      });
    }

    const [summary] = await buildChatSummaries([updated], req.user.id);
    return res.json({
      message: removingSelf ? 'Left group chat.' : 'Member removed.',
      chat: summary,
    });
  }),
);

router.get(
  '/:chatId/messages',
  asyncHandler(async (req, res) => {
    const { chatId } = req.params;
    if (!isValidObjectId(chatId)) {
      return res.status(400).json({ message: 'Invalid chatId.' });
    }

    const chat = await Chat.findOne({ _id: chatId, memberIds: req.user.id });
    if (!chat) {
      return res.status(404).json({ message: 'Chat not found.' });
    }
    if (!(await canUseChat(chat, req.user.id))) {
      const message =
        chat.type === 'SOCIAL_GROUP'
          ? 'You must be an active group member to use this chat.'
          : 'You can only chat with friends.';
      return res.status(403).json({ message });
    }

    const limit = Math.min(
      Math.max(1, parseInt(req.query.limit, 10) || 50),
      200,
    );
    const beforeRaw = String(req.query.before || '').trim();
    const beforeDate = beforeRaw ? new Date(beforeRaw) : null;
    if (beforeRaw && Number.isNaN(beforeDate.getTime())) {
      return res.status(400).json({ message: 'Invalid before cursor.' });
    }

    const query = { chatId, status: 'SENT' };
    if (beforeDate) {
      query.createdAt = { $lt: beforeDate };
    }

    const messages = await Message.find(query)
      .sort({ createdAt: -1 })
      .limit(limit + 1);

    const hasMore = messages.length > limit;
    const page = hasMore ? messages.slice(0, limit) : messages;
    const nextBefore =
      hasMore && page.length > 0
        ? page[page.length - 1].createdAt.toISOString()
        : null;

    // Messages are returned newest-first so the UI can prepend older messages
    // as the user scrolls up.
    const items = page.reverse().map(serializeMessage);
    return res.json({ items, hasMore, nextBefore });
  }),
);

router.post(
  '/:chatId/messages',
  asyncHandler(async (req, res) => {
    const { chatId } = req.params;
    const { content = '', postId = null } = req.body;
    const mediaUrls = readMediaUrls(req.body.mediaUrls);
    const cleanContent = String(content).trim();

    if (!isValidObjectId(chatId)) {
      return res.status(400).json({ message: 'Invalid chatId.' });
    }
    if (!cleanContent && mediaUrls.length === 0 && !postId) {
      return res.status(400).json({ message: 'content, mediaUrls, or postId is required.' });
    }

    const chat = await Chat.findOne({ _id: chatId, memberIds: req.user.id });
    if (!chat) {
      return res.status(404).json({ message: 'Chat not found.' });
    }
    if (!(await canUseChat(chat, req.user.id))) {
      const message =
        chat.type === 'SOCIAL_GROUP'
          ? 'You must be an active group member to use this chat.'
          : 'You can only chat with friends.';
      return res.status(403).json({ message });
    }

    if (cleanContent) {
      await assertContentAllowed({
        text: cleanContent,
        userId: req.user.id,
        targetType: 'MESSAGE',
        targetId: `blocked-message:${chatId}:${req.user.id}:${Date.now()}`,
        action: 'send message',
      });
    }

    const messageType = postId ? 'POST_SHARE' : 'TEXT';

    const message = await Message.create({
      chatId,
      senderId: req.user.id,
      content: cleanContent,
      mediaUrls,
      type: messageType,
      postId: postId || undefined,
      status: 'SENT',
    });

    await Chat.updateOne({ _id: chatId }, { $set: { updatedAt: new Date() } });
    const data = serializeMessage(message);

    emitToChat(
      chatId,
      chat.memberIds.map((memberId) => memberId.toString()),
      'chat:message',
      {
        chatId,
        message: data,
      },
    );

    // Persist a notification row for every recipient so they see
    // the new message in their inbox even if they were offline when
    // the realtime event fired. Skip the sender.
    const sender = await User.findById(req.user.id).select(
      'displayName username avatarUrl',
    );
    const recipientIds = chat.memberIds
      .map((memberId) => memberId.toString())
      .filter((id) => id !== req.user.id);
    if (recipientIds.length > 0) {
      await broadcastNotification({
        userIds: recipientIds,
        actorId: req.user.id,
        type: NOTIFICATION_TYPES.CHAT_MESSAGE,
        payload: {
          chatId,
          chatName: chatTitle(chat),
          messageId: message._id.toString(),
          contentSnippet: cleanContent.slice(0, 200),
          hasMedia: mediaUrls.length > 0,
          ...(sender ? actorSnapshot(sender) : {}),
          navigationTarget: {
            route: 'CHAT_DETAIL',
            chatId,
            messageId: message._id.toString(),
          },
        },
      });
    }

    return res.status(201).json({ message: 'Message sent.', data });
  }),
);

router.post(
  '/:chatId/messages/:messageId/read',
  asyncHandler(async (req, res) => {
    const { chatId, messageId } = req.params;
    if (!isValidObjectId(chatId) || !isValidObjectId(messageId)) {
      return res.status(400).json({ message: 'Invalid chatId or messageId.' });
    }

    const chat = await Chat.findOne({ _id: chatId, memberIds: req.user.id });
    if (!chat) {
      return res.status(404).json({ message: 'Chat not found.' });
    }
    const message = await Message.findOne({ _id: messageId, chatId });
    if (!message) {
      return res.status(404).json({ message: 'Message not found.' });
    }

    const readers = Array.isArray(message.readBy) ? message.readBy : [];
    const alreadyRead = readers.some(
      (reader) => reader.userId.toString() === req.user.id,
    );
    if (!alreadyRead) {
      readers.push({ userId: req.user.id, readAt: new Date() });
      message.readBy = readers;
      await message.save();

      if (message.senderId.toString() !== req.user.id) {
        const reader = await User.findById(req.user.id).select(
          'displayName username avatarUrl',
        );
        await sendNotification({
          userId: message.senderId,
          actorId: req.user.id,
          type: NOTIFICATION_TYPES.CHAT_MESSAGE_READ,
          payload: {
            chatId,
            messageId,
            ...(reader ? actorSnapshot(reader) : {}),
            navigationTarget: {
              route: 'CHAT_DETAIL',
              chatId,
              messageId,
            },
          },
        });
        emitToUser(message.senderId.toString(), 'chat:message_read', {
          chatId,
          messageId,
          readerId: req.user.id,
        });
      }
    }

    return res.json({ message: 'Marked as read.', readBy: message.readBy });
  }),
);

module.exports = router;
