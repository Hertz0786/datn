const express = require('express');

const User = require('../models/User');
const Post = require('../models/Post');
const Group = require('../models/Group');
const asyncHandler = require('../utils/async-handler');
const { requireAuth } = require('../middlewares/auth');
const { toPublicUser } = require('../utils/public-user');
const { withPostMeta } = require('../utils/post-meta');

const router = express.Router();

router.use(requireAuth);

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const q = String(req.query.q || '').trim();
    const type = String(req.query.type || 'all').toLowerCase();
    const topic = String(req.query.topic || '').trim();

    const ageMin = req.query.ageMin !== undefined ? Number(req.query.ageMin) : 7;
    const ageMax = req.query.ageMax !== undefined ? Number(req.query.ageMax) : 14;
    const searchAge = req.query.age !== undefined ? Number(req.query.age) : req.user.age;

    const shouldSearchUsers = type === 'all' || type === 'friend' || type === 'user';
    const shouldSearchGroups = type === 'all' || type === 'group';
    const shouldSearchPosts = type === 'all' || type === 'post';

    let users = [];
    let groups = [];
    let posts = [];

    if (shouldSearchUsers) {
      const userQuery = {
        age: { $gte: ageMin, $lte: ageMax },
        isActive: true,
        role: 'CHILD',
      };
      if (q) {
        userQuery.$or = [
          { displayName: { $regex: q, $options: 'i' } },
          { username: { $regex: q, $options: 'i' } },
        ];
      }
      if (topic) {
        userQuery.favoriteTopics = topic;
      }

      users = await User.find(userQuery).limit(20);
    }

    if (shouldSearchGroups) {
      const groupQuery = {
        status: 'ACTIVE',
        ageMin: { $lte: searchAge },
        ageMax: { $gte: searchAge },
      };
      if (q) {
        groupQuery.$or = [
          { name: { $regex: q, $options: 'i' } },
          { description: { $regex: q, $options: 'i' } },
        ];
      }
      if (topic) {
        groupQuery.topic = topic;
      }

      groups = await Group.find(groupQuery).sort({ memberCount: -1 }).limit(20);
    }

    if (shouldSearchPosts) {
      const postQuery = {
        status: 'PUBLISHED',
        ageMin: { $lte: searchAge },
        ageMax: { $gte: searchAge },
      };
      if (q) {
        postQuery.$or = [{ content: { $regex: q, $options: 'i' } }];
      }
      if (topic) {
        postQuery.topics = topic;
      }

      const rawPosts = await Post.find(postQuery).sort({ createdAt: -1 }).limit(50);
      let filtered = rawPosts;
      if (req.user.role === 'CHILD' && rawPosts.length > 0) {
        const authorIds = [...new Set(rawPosts.map((post) => post.authorId.toString()))];
        const childAuthors = await User.find({
          _id: { $in: authorIds },
          role: 'CHILD',
          isActive: true,
        }).select('_id');
        const childAuthorIds = new Set(childAuthors.map((user) => user._id.toString()));
        filtered = rawPosts
          .filter((post) => childAuthorIds.has(post.authorId.toString()))
          .slice(0, 20);
      } else {
        filtered = rawPosts.slice(0, 20);
      }

      posts = await withPostMeta(filtered, req.user.id);
    }

    return res.json({
      filters: { type, topic, ageMin, ageMax, age: searchAge, q },
      users: users.map(toPublicUser),
      groups,
      posts,
    });
  }),
);

module.exports = router;
