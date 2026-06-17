const express = require('express');

const Post = require('../models/Post');
const Friendship = require('../models/Friendship');
const GroupMember = require('../models/GroupMember');
const Report = require('../models/Report');
const User = require('../models/User');
const asyncHandler = require('../utils/async-handler');
const { requireAuth } = require('../middlewares/auth');
const { isValidObjectId } = require('../middlewares/object-id');

const router = express.Router();

router.use(requireAuth);

async function buildBadgeCatalog(userId) {
  const [postCount, friendCount, groupCount, reportCount] = await Promise.all([
    Post.countDocuments({ authorId: userId, status: 'PUBLISHED' }),
    Friendship.countDocuments({
      $or: [{ userAId: userId }, { userBId: userId }],
    }),
    GroupMember.countDocuments({ userId, status: 'ACTIVE' }),
    Report.countDocuments({ reporterId: userId }),
  ]);

  return [
    {
      id: 'first-post',
      title: 'First Post',
      description: 'Create your first post.',
      icon: 'post_add',
      earned: postCount >= 1,
      progress: Math.min(postCount, 1),
      target: 1,
    },
    {
      id: 'story-builder',
      title: 'Story Builder',
      description: 'Create 5 posts.',
      icon: 'auto_stories',
      earned: postCount >= 5,
      progress: Math.min(postCount, 5),
      target: 5,
    },
    {
      id: 'friendly',
      title: 'Friendly',
      description: 'Make 3 friends.',
      icon: 'groups',
      earned: friendCount >= 3,
      progress: Math.min(friendCount, 3),
      target: 3,
    },
    {
      id: 'group-explorer',
      title: 'Group Explorer',
      description: 'Join a group.',
      icon: 'explore',
      earned: groupCount >= 1,
      progress: Math.min(groupCount, 1),
      target: 1,
    },
    {
      id: 'safety-helper',
      title: 'Safety Helper',
      description: 'Submit a safety report.',
      icon: 'shield',
      earned: reportCount >= 1,
      progress: Math.min(reportCount, 1),
      target: 1,
    },
  ];
}

router.get(
  '/me',
  asyncHandler(async (req, res) => {
    return res.json({ items: await buildBadgeCatalog(req.user.id) });
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

    return res.json({ items: await buildBadgeCatalog(userId) });
  }),
);

module.exports = router;
