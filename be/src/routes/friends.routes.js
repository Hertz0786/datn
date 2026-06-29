const express = require('express');

const User = require('../models/User');
const Block = require('../models/Block');
const Friendship = require('../models/Friendship');
const FriendRequest = require('../models/FriendRequest');
const asyncHandler = require('../utils/async-handler');
const { requireAuth } = require('../middlewares/auth');
const { isValidObjectId } = require('../middlewares/object-id');
const { normalizeFriendPair } = require('../utils/friendship');
const { toPublicUser } = require('../utils/public-user');
const {
  sendNotification,
  NOTIFICATION_TYPES,
  serializeNotification,
} = require('../services/notification-service');

const router = express.Router();

router.use(requireAuth);

async function hasBlockBetween(userIdA, userIdB) {
  const block = await Block.findOne({
    $or: [
      { blockerId: userIdA, blockedId: userIdB },
      { blockerId: userIdB, blockedId: userIdA },
    ],
  });
  return !!block;
}

function actorSnapshot(user) {
  return {
    actorId: user._id.toString(),
    actorName: user.displayName || user.username || 'Ai đó',
    actorUsername: user.username || '',
    actorAvatarUrl: user.avatarUrl || '',
  };
}

function serializeFriendRequest(request) {
  if (!request) {
    return null;
  }

  return {
    _id: request._id.toString(),
    senderId: request.senderId.toString(),
    receiverId: request.receiverId.toString(),
    status: request.status,
    createdAt:
      request.createdAt instanceof Date
        ? request.createdAt.toISOString()
        : request.createdAt,
    updatedAt:
      request.updatedAt instanceof Date
        ? request.updatedAt.toISOString()
        : request.updatedAt,
  };
}

router.post(
  '/requests',
  asyncHandler(async (req, res) => {
    const { receiverId } = req.body;
    if (!isValidObjectId(receiverId)) {
      return res.status(400).json({ message: 'Invalid receiverId.' });
    }
    if (receiverId === req.user.id) {
      return res.status(400).json({ message: 'You cannot send request to yourself.' });
    }

    const receiver = await User.findById(receiverId);
    if (!receiver || !receiver.isActive) {
      return res.status(404).json({ message: 'Receiver not found.' });
    }

    if (!receiver.privacy.allowFriendRequests) {
      return res.status(403).json({ message: 'This user does not accept friend requests.' });
    }

    const blocked = await hasBlockBetween(req.user.id, receiverId);
    if (blocked) {
      return res.status(403).json({ message: 'Cannot send request due to block settings.' });
    }

    const pair = normalizeFriendPair(req.user.id, receiverId);
    const friendship = await Friendship.findOne(pair);
    if (friendship) {
      return res.status(409).json({ message: 'You are already friends.' });
    }

    const reversePending = await FriendRequest.findOne({
      senderId: receiverId,
      receiverId: req.user.id,
      status: 'PENDING',
    });

    if (reversePending) {
      // Defensively handle the unlikely race where another request
      // created the friendship between the check and now.  Silently
      // ignore duplicate-key errors — the friendship already exists.
      const existing = await Friendship.findOne(pair);
      if (!existing) {
        await Friendship.create({
          userAId: pair.userAId,
          userBId: pair.userBId,
        });
      }
      reversePending.status = 'ACCEPTED';
      await reversePending.save();

      const senderInfo = await User.findById(req.user.id).select(
        'displayName username avatarUrl',
      );
      const senderSnapshot = senderInfo ? actorSnapshot(senderInfo) : {
        actorId: req.user.id,
        actorName: 'Ai đó',
        actorUsername: '',
        actorAvatarUrl: '',
      };

      const notification = await sendNotification({
        userId: receiverId,
        actorId: req.user.id,
        type: NOTIFICATION_TYPES.FRIEND_REQUEST_ACCEPTED,
        payload: {
          byUserId: req.user.id,
          requestId: reversePending._id.toString(),
          ...senderSnapshot,
          navigationTarget: {
            route: 'PROFILE',
            userId: req.user.id,
          },
        },
      });

      return res.json({ message: 'Friend request auto-accepted from reverse request.' });
    }

    const request = await FriendRequest.findOneAndUpdate(
      {
        senderId: req.user.id,
        receiverId,
      },
      {
        $set: {
          senderId: req.user.id,
          receiverId,
          status: 'PENDING',
        },
      },
      {
        upsert: true,
        returnNewDocument: true,
        runValidators: true,
      },
    );

    const senderInfo = await User.findById(req.user.id).select(
      'displayName username avatarUrl',
    );
    const senderSnapshot = senderInfo ? actorSnapshot(senderInfo) : {
      actorId: req.user.id,
      actorName: 'Ai đó',
      actorUsername: '',
      actorAvatarUrl: '',
    };

    await sendNotification({
      userId: receiverId,
      actorId: req.user.id,
      type: NOTIFICATION_TYPES.FRIEND_REQUEST_RECEIVED,
      payload: {
        fromUserId: req.user.id,
        requestId: request._id.toString(),
        ...senderSnapshot,
        navigationTarget: {
          route: 'FRIEND_REQUESTS',
        },
      },
    });

    return res.status(201).json({ message: 'Friend request sent.', request });
  }),
);

router.get(
  '/status/:userId',
  asyncHandler(async (req, res) => {
    const { userId } = req.params;
    if (!isValidObjectId(userId)) {
      return res.status(400).json({ message: 'Invalid userId.' });
    }

    if (userId === req.user.id) {
      return res.json({ userId, status: 'SELF', request: null });
    }

    const target = await User.findById(userId);
    if (!target || !target.isActive) {
      return res.status(404).json({ message: 'User not found.' });
    }

    const friendship = await Friendship.findOne(normalizeFriendPair(req.user.id, userId));
    if (friendship) {
      return res.json({ userId, status: 'FRIENDS', request: null });
    }

    const request = await FriendRequest.findOne({
      status: 'PENDING',
      $or: [
        { senderId: req.user.id, receiverId: userId },
        { senderId: userId, receiverId: req.user.id },
      ],
    }).sort({ updatedAt: -1 });

    if (!request) {
      return res.json({ userId, status: 'NONE', request: null });
    }

    const status =
      request.senderId.toString() === req.user.id
        ? 'OUTGOING_PENDING'
        : 'INCOMING_PENDING';

    return res.json({ userId, status, request: serializeFriendRequest(request) });
  }),
);

router.get(
  '/users/:userId',
  asyncHandler(async (req, res) => {
    const { userId } = req.params;
    if (!isValidObjectId(userId)) {
      return res.status(400).json({ message: 'Invalid userId.' });
    }

    const target = await User.findById(userId);
    if (!target || !target.isActive) {
      return res.status(404).json({ message: 'User not found.' });
    }

    const limit = Math.max(1, Math.min(50, Number(req.query.limit) || 20));
    const beforeRaw = String(req.query.before || '').trim();
    const beforeDate = beforeRaw ? new Date(beforeRaw) : null;
    if (beforeRaw && Number.isNaN(beforeDate.getTime())) {
      return res.status(400).json({ message: 'Invalid before cursor.' });
    }

    const allPairs = await Friendship.find({
      $or: [{ userAId: userId }, { userBId: userId }],
    }).sort({ createdAt: -1 });

    const pairs =
      beforeDate !== null
        ? allPairs.filter((pair) => pair.createdAt < beforeDate)
        : allPairs;

    const page = pairs.slice(0, limit + 1);
    const hasMore = page.length > limit;
    const pageSlice = hasMore ? page.slice(0, limit) : page;

    if (pageSlice.length === 0) {
      return res.json({ items: [], nextBefore: null, hasMore: false });
    }

    const otherIds = pageSlice.map((pair) =>
      pair.userAId.toString() === userId ? pair.userBId : pair.userAId,
    );
    const friends = await User.find({
      _id: { $in: otherIds },
      isActive: true,
    });

    const items = pageSlice
      .map((pair) => {
        const otherId =
          pair.userAId.toString() === userId
            ? pair.userBId.toString()
            : pair.userAId.toString();
        const friend = friends.find((user) => user._id.toString() === otherId);
        return friend ? toPublicUser(friend) : null;
      })
      .filter(Boolean);

    const nextBefore = hasMore
      ? new Date(pageSlice[pageSlice.length - 1].createdAt).toISOString()
      : null;

    return res.json({ items, nextBefore, hasMore });
  }),
);

router.get(
  '/mutual/:userId',
  asyncHandler(async (req, res) => {
    const { userId } = req.params;
    if (!isValidObjectId(userId)) {
      return res.status(400).json({ message: 'Invalid userId.' });
    }

    if (userId === req.user.id) {
      return res.json({ items: [] });
    }

    const target = await User.findById(userId);
    if (!target || !target.isActive) {
      return res.status(404).json({ message: 'User not found.' });
    }

    const limit = Math.max(1, Math.min(30, Number(req.query.limit) || 12));
    const [myPairs, targetPairs] = await Promise.all([
      Friendship.find({
        $or: [{ userAId: req.user.id }, { userBId: req.user.id }],
      }).select('userAId userBId'),
      Friendship.find({
        $or: [{ userAId: userId }, { userBId: userId }],
      }).select('userAId userBId'),
    ]);

    const myFriendIds = new Set(
      myPairs.map((pair) =>
        pair.userAId.toString() === req.user.id
          ? pair.userBId.toString()
          : pair.userAId.toString(),
      ),
    );
    const mutualIds = targetPairs
      .map((pair) =>
        pair.userAId.toString() === userId
          ? pair.userBId.toString()
          : pair.userAId.toString(),
      )
      .filter((id) => myFriendIds.has(id))
      .slice(0, limit);

    if (mutualIds.length === 0) {
      return res.json({ items: [] });
    }

    const users = await User.find({
      _id: { $in: mutualIds },
      isActive: true,
    }).select('displayName username age role avatarUrl coverUrl bio favoriteTopics lastActiveAt privacy');

    const byId = new Map(users.map((user) => [user._id.toString(), user]));
    const items = mutualIds
      .map((id) => byId.get(id))
      .filter(Boolean)
      .map(toPublicUser);

    return res.json({ items });
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

    const allPairs = await Friendship.find({
      $or: [{ userAId: req.user.id }, { userBId: req.user.id }],
    }).sort({ createdAt: -1 });

    const pairs =
      beforeDate !== null
        ? allPairs.filter((pair) => pair.createdAt < beforeDate)
        : allPairs;

    const page = pairs.slice(0, limit + 1);
    const hasMore = page.length > limit;
    const pageSlice = hasMore ? page.slice(0, limit) : page;

    if (pageSlice.length === 0) {
      return res.json({ items: [], nextBefore: null, hasMore: false });
    }

    const otherIds = pageSlice.map((pair) =>
      pair.userAId.toString() === req.user.id ? pair.userBId : pair.userAId,
    );
    const friends = await User.find({ _id: { $in: otherIds } });

    const items = pageSlice.map((pair) => {
      const otherId =
        pair.userAId.toString() === req.user.id
          ? pair.userBId.toString()
          : pair.userAId.toString();
      const friend = friends.find((user) => user._id.toString() === otherId);
      return friend ? toPublicUser(friend) : null;
    }).filter(Boolean);

    const nextBefore = hasMore
      ? new Date(pageSlice[pageSlice.length - 1].createdAt).toISOString()
      : null;

    return res.json({ items, nextBefore, hasMore });
  }),
);

router.get(
  '/requests/incoming',
  asyncHandler(async (req, res) => {
    const limit = Math.max(1, Math.min(50, Number(req.query.limit) || 20));
    const beforeRaw = String(req.query.before || '').trim();
    const beforeDate = beforeRaw ? new Date(beforeRaw) : null;
    if (beforeRaw && Number.isNaN(beforeDate.getTime())) {
      return res.status(400).json({ message: 'Invalid before cursor.' });
    }

    const query = {
      receiverId: req.user.id,
      status: 'PENDING',
    };
    if (beforeDate) {
      query.createdAt = { $lt: beforeDate };
    }

    const requests = await FriendRequest.find(query)
      .sort({ createdAt: -1 })
      .populate(
        'senderId',
        'displayName username avatarUrl age favoriteTopics',
      )
      .limit(limit + 1);

    const items = requests.map((request) => {
      const serialized = serializeFriendRequest(request);
      if (!serialized) {
        return null;
      }
      const sender = request.senderId && request.senderId._id
        ? toPublicUser(request.senderId)
        : null;
      return { ...serialized, sender };
    }).filter(Boolean);

    const hasMore = items.length > limit;
    const page = hasMore ? items.slice(0, limit) : items;
    const nextBefore = hasMore
      ? page[page.length - 1].createdAt
      : null;

    return res.json({
      items: page,
      nextBefore: nextBefore
        ? new Date(nextBefore).toISOString()
        : null,
      hasMore,
    });
  }),
);

router.get(
  '/requests/outgoing',
  asyncHandler(async (req, res) => {
    const items = await FriendRequest.find({
      senderId: req.user.id,
      status: 'PENDING',
    }).sort({ createdAt: -1 });

    return res.json({ items });
  }),
);

router.patch(
  '/requests/:requestId',
  asyncHandler(async (req, res) => {
    const { requestId } = req.params;
    const { action } = req.body;

    if (!isValidObjectId(requestId)) {
      return res.status(400).json({ message: 'Invalid requestId.' });
    }
    if (!['accept', 'reject', 'cancel'].includes(action)) {
      return res.status(400).json({ message: 'action must be accept/reject/cancel.' });
    }

    const request = await FriendRequest.findById(requestId);
    if (!request) {
      return res.status(404).json({ message: 'Friend request not found.' });
    }

    // Graceful: if request was already accepted/rejected/cancelled, treat as success
    // instead of 404. This prevents "pending not found" errors when the request
    // was auto-accepted or handled by another action.
    if (request.status !== 'PENDING') {
      return res.json({
        message: `Friend request already ${request.status.toLowerCase()}.`,
        status: request.status,
      });
    }

    const isReceiver = request.receiverId.toString() === req.user.id;
    const isSender = request.senderId.toString() === req.user.id;

    if (!isReceiver && !isSender) {
      return res.status(403).json({ message: 'You cannot update this request.' });
    }

    if (action === 'cancel' && !isSender) {
      return res.status(403).json({ message: 'Only sender can cancel request.' });
    }

    if (action === 'accept') {
      if (!isReceiver) {
        return res.status(403).json({ message: 'Only receiver can accept request.' });
      }

      const pair = normalizeFriendPair(request.senderId, request.receiverId);
      await Friendship.findOneAndUpdate(
        pair,
        { $set: pair },
        { upsert: true, returnNewDocument: true, setDefaultsOnInsert: true },
      );

      request.status = 'ACCEPTED';
      await request.save();

      const acceptorInfo = await User.findById(req.user.id).select(
        'displayName username avatarUrl',
      );
      const acceptorSnapshot = acceptorInfo
        ? actorSnapshot(acceptorInfo)
        : {
            actorId: req.user.id,
            actorName: 'Ai đó',
            actorUsername: '',
            actorAvatarUrl: '',
          };

      await sendNotification({
        userId: request.senderId,
        actorId: req.user.id,
        type: NOTIFICATION_TYPES.FRIEND_REQUEST_ACCEPTED,
        payload: {
          byUserId: req.user.id,
          requestId: request._id.toString(),
          ...acceptorSnapshot,
          navigationTarget: {
            route: 'PROFILE',
            userId: req.user.id,
          },
        },
      });

      return res.json({ message: 'Friend request accepted.' });
    }

    if (action === 'reject' && isReceiver) {
      const rejectorInfo = await User.findById(req.user.id).select(
        'displayName username avatarUrl',
      );
      const rejectorSnapshot = rejectorInfo
        ? actorSnapshot(rejectorInfo)
        : {
            actorId: req.user.id,
            actorName: 'Ai đó',
            actorUsername: '',
            actorAvatarUrl: '',
          };
      await sendNotification({
        userId: request.senderId,
        actorId: req.user.id,
        type: NOTIFICATION_TYPES.FRIEND_REQUEST_REJECTED,
        payload: {
          byUserId: req.user.id,
          requestId: request._id.toString(),
          ...rejectorSnapshot,
        },
      });
    }

    request.status = action === 'reject' ? 'REJECTED' : 'CANCELLED';
    await request.save();

    return res.json({ message: `Friend request ${request.status.toLowerCase()}.` });
  }),
);

router.delete(
  '/:friendId',
  asyncHandler(async (req, res) => {
    const { friendId } = req.params;
    if (!isValidObjectId(friendId)) {
      return res.status(400).json({ message: 'Invalid friendId.' });
    }

    const pair = normalizeFriendPair(req.user.id, friendId);
    const friendship = await Friendship.findOneAndDelete(pair);

    if (!friendship) {
      return res.status(404).json({ message: 'Friendship not found.' });
    }

    // Optional: Clean up any pending friend requests between them
    await FriendRequest.deleteMany({
      $or: [
        { senderId: pair.userAId, receiverId: pair.userBId },
        { senderId: pair.userBId, receiverId: pair.userAId },
      ],
    });

    // We intentionally do NOT send a FRIEND_REMOVED notification:
    // removing a friend should be silent from the recipient's
    // perspective to avoid awkward / confrontational UX.

    return res.json({ message: 'Friend removed successfully.' });
  }),
);

module.exports = router;
