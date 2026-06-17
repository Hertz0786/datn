const express = require('express');

const authRoutes = require('./auth.routes');
const userRoutes = require('./users.routes');
const friendRoutes = require('./friends.routes');
const groupRoutes = require('./groups.routes');
const postRoutes = require('./posts.routes');
const commentRoutes = require('./comments.routes');
const searchRoutes = require('./search.routes');
const safetyRoutes = require('./safety.routes');
const notificationRoutes = require('./notifications.routes');
const chatRoutes = require('./chats.routes');
const badgeRoutes = require('./badges.routes');
const photoRoutes = require('./photos.routes');
const mediaRoutes = require('./media.routes');
const assistantRoutes = require('./assistant.routes');
const supportRoutes = require('./support.routes');
const adminRoutes = require('./admin.routes');

const router = express.Router();

router.use('/auth', authRoutes);
router.use('/users', userRoutes);
router.use('/friends', friendRoutes);
router.use('/groups', groupRoutes);
router.use('/posts', postRoutes);
router.use('/comments', commentRoutes);
router.use('/search', searchRoutes);
router.use('/safety', safetyRoutes);
router.use('/notifications', notificationRoutes);
router.use('/chats', chatRoutes);
router.use('/badges', badgeRoutes);
router.use('/photos', photoRoutes);
router.use('/media', mediaRoutes);
router.use('/assistant', assistantRoutes);
router.use('/support', supportRoutes);
router.use('/admin', adminRoutes);

module.exports = router;
