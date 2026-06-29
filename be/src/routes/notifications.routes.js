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
      { returnNewDocument: true },
    );

    if (!notification) {
      return res.status(404).json({ message: 'Notification not found.' });
    }

    return res.json({ message: 'Notification marked as read.', notification });
  }),
);

router.delete(
  '/:notificationId',
  asyncHandler(async (req, res) => {
    const { notificationId } = req.params;
    if (!isValidObjectId(notificationId)) {
      return res.status(400).json({ message: 'Invalid notificationId.' });
    }

    const result = await Notification.deleteOne({
      _id: notificationId,
      userId: req.user.id,
    });

    if (result.deletedCount === 0) {
      return res.status(404).json({ message: 'Notification not found.' });
    }

    return res.json({ message: 'Notification deleted.' });
  }),
);

router.delete(
  '/',
  asyncHandler(async (req, res) => {
    const body = req.body ?? {};
    const ids = body.ids;

    if (Array.isArray(ids) && ids.length > 0) {
      const validIds = ids.filter((id) => isValidObjectId(id));
      if (validIds.length === 0) {
        return res.status(400).json({ message: 'No valid ids provided.' });
      }
      await Notification.deleteMany({
        _id: { $in: validIds },
        userId: req.user.id,
      });
      return res.json({
        message: `${validIds.length} notifications deleted.`,
        deletedCount: validIds.length,
      });
    }

    await Notification.deleteMany({ userId: req.user.id });
    return res.json({ message: 'All notifications deleted.' });
  }),
);

module.exports = router;

