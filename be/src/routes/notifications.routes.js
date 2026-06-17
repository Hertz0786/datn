const express = require('express');

const Notification = require('../models/Notification');
const asyncHandler = require('../utils/async-handler');
const { requireAuth } = require('../middlewares/auth');
const { isValidObjectId } = require('../middlewares/object-id');

const router = express.Router();

router.use(requireAuth);

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const items = await Notification.find({ userId: req.user.id })
      .sort({ createdAt: -1 })
      .limit(100);

    return res.json({ items });
  }),
);

router.patch(
  '/read-all',
  asyncHandler(async (req, res) => {
    await Notification.updateMany(
      { userId: req.user.id, readAt: null },
      { $set: { readAt: new Date() } },
    );
    return res.json({ message: 'All notifications marked as read.' });
  }),
);

router.patch(
  '/:notificationId/read',
  asyncHandler(async (req, res) => {
    const { notificationId } = req.params;
    if (!isValidObjectId(notificationId)) {
      return res.status(400).json({ message: 'Invalid notificationId.' });
    }

    const notification = await Notification.findOneAndUpdate(
      { _id: notificationId, userId: req.user.id },
      { $set: { readAt: new Date() } },
      { new: true },
    );

    if (!notification) {
      return res.status(404).json({ message: 'Notification not found.' });
    }

    return res.json({ message: 'Notification marked as read.', notification });
  }),
);

module.exports = router;

