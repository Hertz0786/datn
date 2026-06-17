const express = require('express');

const Post = require('../models/Post');
const User = require('../models/User');
const asyncHandler = require('../utils/async-handler');
const { requireAuth } = require('../middlewares/auth');

const router = express.Router();

router.use(requireAuth);

router.get(
  '/me',
  asyncHandler(async (req, res) => {
    const [user, posts] = await Promise.all([
      User.findById(req.user.id),
      Post.find({
        authorId: req.user.id,
        status: 'PUBLISHED',
        mediaUrls: { $exists: true, $ne: [] },
      }).sort({ createdAt: -1 }),
    ]);

    const items = [];

    if (user?.avatarUrl) {
      items.push({
        id: `avatar:${user._id.toString()}`,
        url: user.avatarUrl,
        caption: 'Profile photo',
        sourceType: 'PROFILE',
        createdAt: user.updatedAt,
      });
    }

    for (const post of posts) {
      for (const [index, url] of post.mediaUrls.entries()) {
        items.push({
          id: `${post._id.toString()}:${index}`,
          url,
          caption: post.content,
          sourceType: 'POST',
          postId: post._id.toString(),
          createdAt: post.createdAt,
        });
      }
    }

    return res.json({ items });
  }),
);

module.exports = router;
