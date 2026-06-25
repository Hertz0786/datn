const Message = require('../models/Message');
const User = require('../models/User');
const { toPublicUser } = require('./public-user');

function serializeMessage(message) {
  if (!message) {
    return null;
  }

  const base = {
    _id: message._id.toString(),
    chatId: message.chatId.toString(),
    senderId: message.senderId.toString(),
    content: message.content,
    mediaUrls: message.mediaUrls,
    type: message.type || 'TEXT',
    postId: message.postId ? message.postId.toString() : null,
    status: message.status,
    createdAt: message.createdAt,
    updatedAt: message.updatedAt,
  };

  // Expose call metadata for `type: 'CALL'` messages so the client can render
  // the call-history banner without an extra round-trip to CallLog.
  if (message.type === 'CALL' && message.callMeta) {
    base.callMeta = {
      callId: message.callMeta.callId || '',
      callType: message.callMeta.callType || 'voice',
      status: message.callMeta.status || 'ended',
      durationSeconds: message.callMeta.durationSeconds || 0,
      initiatorId: message.callMeta.initiatorId
        ? message.callMeta.initiatorId.toString()
        : null,
    };
  }

  return base;
}

function fallbackGroupTitle(memberUsers, currentUserId) {
  const names = memberUsers
    .filter((user) => user.id !== currentUserId)
    .map((user) => user.displayName || user.username)
    .filter(Boolean);

  if (names.length === 0) {
    return 'Group chat';
  }
  if (names.length <= 3) {
    return names.join(', ');
  }
  return `${names.slice(0, 3).join(', ')} +${names.length - 3}`;
}

async function buildChatSummaries(chats, currentUserId) {
  const memberIds = [
    ...new Set(
      chats.flatMap((chat) =>
        chat.memberIds.map((memberId) => memberId.toString()),
      ),
    ),
  ];

  const users = await User.find({ _id: { $in: memberIds }, isActive: true });
  const usersById = new Map(
    users.map((user) => [user._id.toString(), toPublicUser(user)]),
  );

  const chatIds = chats.map((c) => c._id);
  const lastMessagesMap = new Map();
  const raw = await Message.aggregate([
    { $match: { chatId: { $in: chatIds }, status: 'SENT' } },
    { $sort: { createdAt: -1 } },
    { $group: { _id: '$chatId', lastMessage: { $first: '$$ROOT' } } },
  ]);
  for (const row of raw) {
    lastMessagesMap.set(row._id.toString(), row.lastMessage);
  }

  return chats.map((chat) => {
    const memberIdStrings = chat.memberIds.map((memberId) =>
      memberId.toString(),
    );
    const otherUserId = memberIdStrings.find(
      (memberId) => memberId !== currentUserId,
    );
    const lastMessage = lastMessagesMap.get(chat._id.toString()) || null;
    const memberUsers = memberIdStrings
      .map((memberId) => usersById.get(memberId))
      .filter(Boolean);
    const isConversationGroup = ['GROUP', 'SOCIAL_GROUP'].includes(chat.type);

    return {
      _id: chat._id.toString(),
      type: chat.type,
      groupId: chat.groupId?.toString() || '',
      title: isConversationGroup
        ? chat.title || fallbackGroupTitle(memberUsers, currentUserId)
        : '',
      avatarUrl: isConversationGroup ? chat.avatarUrl || '' : '',
      memberIds: memberIdStrings,
      memberUsers,
      memberCount: memberIdStrings.length,
      createdBy: chat.createdBy?.toString() || '',
      otherUser:
        !isConversationGroup && otherUserId
          ? usersById.get(otherUserId) || null
          : null,
      lastMessage: serializeMessage(lastMessage),
      createdAt: chat.createdAt,
      updatedAt: chat.updatedAt,
    };
  });
}

module.exports = {
  buildChatSummaries,
  serializeMessage,
};
