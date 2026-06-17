const Message = require('../models/Message');
const User = require('../models/User');
const { toPublicUser } = require('./public-user');

function serializeMessage(message) {
  if (!message) {
    return null;
  }

  return {
    _id: message._id.toString(),
    chatId: message.chatId.toString(),
    senderId: message.senderId.toString(),
    content: message.content,
    mediaUrls: message.mediaUrls,
    status: message.status,
    createdAt: message.createdAt,
    updatedAt: message.updatedAt,
  };
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

  const lastMessages = await Promise.all(
    chats.map((chat) =>
      Message.findOne({ chatId: chat._id, status: 'SENT' }).sort({
        createdAt: -1,
      }),
    ),
  );

  return chats.map((chat, index) => {
    const memberIdStrings = chat.memberIds.map((memberId) =>
      memberId.toString(),
    );
    const otherUserId = memberIdStrings.find(
      (memberId) => memberId !== currentUserId,
    );
    const lastMessage = lastMessages[index];
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
