const express = require('express');

const User = require('../models/User');
const Block = require('../models/Block');
const Friendship = require('../models/Friendship');
const Post = require('../models/Post');
const asyncHandler = require('../utils/async-handler');
const { requireAuth } = require('../middlewares/auth');
const { isValidObjectId } = require('../middlewares/object-id');
const { toPublicUser } = require('../utils/public-user');
const {
  sendNotification,
  NOTIFICATION_TYPES,
} = require('../services/notification-service');

const router = express.Router();

router.use(requireAuth);

router.get(
  '/me',
  asyncHandler(async (req, res) => {
    const me = await User.findById(req.user.id);
    if (!me) {
      return res.status(404).json({ message: 'User not found.' });
    }

    return res.json({ user: toPublicUser(me) });
  }),
);

router.patch(
  '/me',
  asyncHandler(async (req, res) => {
    const allowedFields = [
      'displayName',
      'bio',
      'avatarUrl',
      'coverUrl',
      'favoriteTopics',
      'privacy',
    ];

    const update = {};
    for (const field of allowedFields) {
      if (req.body[field] !== undefined) {
        update[field] = req.body[field];
      }
    }

    if (update.favoriteTopics && !Array.isArray(update.favoriteTopics)) {
      return res.status(400).json({ message: 'favoriteTopics must be an array.' });
    }

    const user = await User.findByIdAndUpdate(
      req.user.id,
      { $set: update },
      { new: true, runValidators: true },
    );

    if (!user) {
      return res.status(404).json({ message: 'User not found.' });
    }

    if (update.displayName !== undefined || update.avatarUrl !== undefined) {
      await Post.updateMany(
        { authorId: req.user.id },
        {
          $set: {
            'authorSnapshot.displayName': user.displayName,
            'authorSnapshot.username': user.username,
            'authorSnapshot.avatarUrl': user.avatarUrl,
          },
        },
      );
    }

    return res.json({
      message: 'Profile updated.',
      user: toPublicUser(user),
    });
  }),
);

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const q = String(req.query.q || '').trim();
    const minAge = req.query.minAge !== undefined ? Number(req.query.minAge) : 7;
    const maxAge = req.query.maxAge !== undefined ? Number(req.query.maxAge) : 14;

    const query = {
      age: { $gte: minAge, $lte: maxAge },
      isActive: true,
    };

    if (q) {
      query.$or = [
        { displayName: { $regex: q, $options: 'i' } },
        { username: { $regex: q, $options: 'i' } },
      ];
    }

    const users = await User.find(query).sort({ createdAt: -1 }).limit(50);
    return res.json({ items: users.map(toPublicUser) });
  }),
);

router.get(
  '/:userId/friends',
  asyncHandler(async (req, res) => {
    const { userId } = req.params;
    if (!isValidObjectId(userId)) {
      return res.status(400).json({ message: 'Invalid userId.' });
    }

    const friendships = await Friendship.find({
      $or: [{ userAId: userId }, { userBId: userId }],
    }).sort({ createdAt: -1 });

    const friendIds = friendships.map((item) => {
      const userA = item.userAId.toString();
      return userA === userId ? item.userBId.toString() : userA;
    });

    const users = await User.find({ _id: { $in: friendIds } });
    return res.json({ items: users.map(toPublicUser) });
  }),
);

router.get(
  '/:userId',
  asyncHandler(async (req, res) => {
    const { userId } = req.params;
    if (!isValidObjectId(userId)) {
      return res.status(400).json({ message: 'Invalid userId.' });
    }

    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({ message: 'User not found.' });
    }

    return res.json({ user: toPublicUser(user) });
  }),
);

router.post(
  '/:userId/block',
  asyncHandler(async (req, res) => {
    const { userId } = req.params;
    if (!isValidObjectId(userId)) {
      return res.status(400).json({ message: 'Invalid userId.' });
    }
    if (userId === req.user.id) {
      return res.status(400).json({ message: 'You cannot block yourself.' });
    }

    await Block.findOneAndUpdate(
      { blockerId: req.user.id, blockedId: userId },
      { $set: { blockerId: req.user.id, blockedId: userId } },
      { upsert: true, new: true },
    );

    const blocker = await User.findById(req.user.id).select(
      'displayName username avatarUrl',
    );
    await sendNotification({
      userId,
      actorId: req.user.id,
      type: NOTIFICATION_TYPES.USER_BLOCKED,
      payload: {
        byUserId: req.user.id,
        actorName: blocker?.displayName || blocker?.username || 'Ai đó',
        actorUsername: blocker?.username || '',
        actorAvatarUrl: blocker?.avatarUrl || '',
        navigationTarget: {
          route: 'PROFILE',
          userId: req.user.id,
        },
      },
    });

    return res.json({ message: 'User blocked.' });
  }),
);

router.delete(
  '/:userId/block',
  asyncHandler(async (req, res) => {
    const { userId } = req.params;
    if (!isValidObjectId(userId)) {
      return res.status(400).json({ message: 'Invalid userId.' });
    }

    const removed = await Block.deleteOne({
      blockerId: req.user.id,
      blockedId: userId,
    });

    if (removed && removed.deletedCount > 0) {
      const unblocker = await User.findById(req.user.id).select(
        'displayName username avatarUrl',
      );
      await sendNotification({
        userId,
        actorId: req.user.id,
        type: NOTIFICATION_TYPES.USER_UNBLOCKED,
        payload: {
          byUserId: req.user.id,
          actorName: unblocker?.displayName || unblocker?.username || 'Ai đó',
          actorUsername: unblocker?.username || '',
          actorAvatarUrl: unblocker?.avatarUrl || '',
          navigationTarget: {
            route: 'PROFILE',
            userId: req.user.id,
          },
        },
      });
    }

    return res.json({ message: 'User unblocked.' });
  }),
);

module.exports = router;
