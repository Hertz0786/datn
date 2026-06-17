const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');

const Chat = require('../models/Chat');
const Block = require('../models/Block');
const Friendship = require('../models/Friendship');
const GroupMember = require('../models/GroupMember');
const Post = require('../models/Post');
const User = require('../models/User');
const env = require('../config/env');
const { normalizeFriendPair } = require('../utils/friendship');

let io;

function initRealtime(server) {
  io = new Server(server, {
    cors: {
      origin: env.clientOrigin === '*' ? true : env.clientOrigin,
    },
  });

  io.use((socket, next) => {
    const token = socket.handshake.auth?.token;
    if (!token) {
      return next(new Error('Authentication required.'));
    }

    try {
      const decoded = jwt.verify(token, env.jwtSecret);
      socket.user = {
        id: decoded.sub,
        role: decoded.role,
        age: decoded.age,
        username: decoded.username,
      };
    } catch (_) {
      return next(new Error('Invalid or expired token.'));
    }

    return next();
  });

  io.on('connection', (socket) => {
    if (socket.user?.id) {
      socket.join(userRoom(socket.user.id));
    }

    socket.on('chat:join', async (chatId, ack) => {
      const canJoin = await canJoinChat(socket.user?.id, chatId);
      if (!canJoin.allowed) {
        if (typeof ack === 'function') {
          ack({ ok: false, message: canJoin.message });
        }
        return;
      }

      socket.join(chatRoom(chatId));
      if (typeof ack === 'function') {
        ack({ ok: true });
      }
    });

    socket.on('chat:leave', (chatId) => {
      if (chatId) {
        socket.leave(chatRoom(chatId));
      }
    });

    socket.on('post:join', async (postId, ack) => {
      const canJoin = await canJoinPost(socket.user?.id, postId);
      if (!canJoin.allowed) {
        if (typeof ack === 'function') {
          ack({ ok: false, message: canJoin.message });
        }
        return;
      }

      socket.join(postRoom(postId));
      if (typeof ack === 'function') {
        ack({ ok: true });
      }
    });

    socket.on('post:leave', (postId) => {
      if (postId) {
        socket.leave(postRoom(postId));
      }
    });
  });

  return io;
}

function userRoom(userId) {
  return `user:${userId}`;
}

function chatRoom(chatId) {
  return `chat:${chatId}`;
}

function postRoom(postId) {
  return `post:${postId}`;
}

async function hasAnyBlock(userIdA, userIdB) {
  const block = await Block.findOne({
    $or: [
      { blockerId: userIdA, blockedId: userIdB },
      { blockerId: userIdB, blockedId: userIdA },
    ],
  }).select('_id');
  return !!block;
}

async function canJoinChat(userId, chatId) {
  if (!userId) {
    return { allowed: false, message: 'Authentication required.' };
  }
  if (!chatId) {
    return { allowed: false, message: 'Missing chatId.' };
  }

  const chat = await Chat.findOne({ _id: chatId, memberIds: userId }).select(
    'type groupId memberIds',
  );
  if (!chat) {
    return { allowed: false, message: 'Chat not found.' };
  }

  if (chat.type === 'SOCIAL_GROUP') {
    const membership = await GroupMember.findOne({
      groupId: chat.groupId,
      userId,
      status: 'ACTIVE',
    }).select('_id');
    return membership
      ? { allowed: true }
      : {
          allowed: false,
          message: 'You must be an active group member to join this chat.',
        };
  }

  if (chat.type !== 'DIRECT') {
    return { allowed: true };
  }

  const memberIds = chat.memberIds.map((memberId) => memberId.toString());
  const otherUserId = memberIds.find((memberId) => memberId !== userId);
  if (!otherUserId) {
    return { allowed: false, message: 'Chat not found.' };
  }

  const [friendship, targetUser] = await Promise.all([
    Friendship.findOne(normalizeFriendPair(userId, otherUserId)).select('_id'),
    User.findById(otherUserId).select('isActive'),
  ]);

  if (!targetUser?.isActive) {
    return { allowed: false, message: 'Chat not found.' };
  }

  if (await hasAnyBlock(userId, otherUserId)) {
    return { allowed: false, message: 'Chat is unavailable.' };
  }

  return friendship
    ? { allowed: true }
    : { allowed: false, message: 'You can only join chats with friends.' };
}

async function canJoinPost(userId, postId) {
  if (!userId) {
    return { allowed: false, message: 'Authentication required.' };
  }
  if (!postId) {
    return { allowed: false, message: 'Missing postId.' };
  }

  const post = await Post.findById(postId).select('authorId audience status');
  if (!post || post.status !== 'PUBLISHED') {
    return { allowed: false, message: 'Post not found.' };
  }

  const authorId = post.authorId.toString();
  if (authorId === userId) {
    return { allowed: true };
  }

  if (await hasAnyBlock(userId, authorId)) {
    return { allowed: false, message: 'Post is unavailable.' };
  }

  if (post.audience === 'PUBLIC') {
    return { allowed: true };
  }

  const friendship = await Friendship.findOne(normalizeFriendPair(userId, authorId)).select(
    '_id',
  );

  return friendship
    ? { allowed: true }
    : { allowed: false, message: 'You can only join posts visible to friends.' };
}

function emitGlobal(event, payload) {
  if (io) {
    io.emit(event, payload);
  }
}

function emitToPost(postId, event, payload) {
  if (io) {
    io.to(postRoom(postId)).emit(event, payload);
  }
}

function emitToChat(chatId, userIds, event, payload) {
  if (!io) {
    return;
  }

  io.to(chatRoom(chatId)).emit(event, payload);
  for (const userId of userIds) {
    io.to(userRoom(userId)).emit(event, payload);
  }
}

function emitToUser(userId, event, payload) {
  if (io) {
    io.to(userRoom(userId)).emit(event, payload);
  }
}

module.exports = {
  initRealtime,
  emitGlobal,
  emitToPost,
  emitToChat,
  emitToUser,
};
