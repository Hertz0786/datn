const express = require('express');
const bcrypt = require('bcryptjs');
const crypto = require('crypto');

const User = require('../models/User');
const PasswordResetToken = require('../models/PasswordResetToken');
const asyncHandler = require('../utils/async-handler');
const { requireAuth } = require('../middlewares/auth');
const { createAuthToken } = require('../utils/token');
const { toPublicUser } = require('../utils/public-user');

const router = express.Router();

router.post(
  '/register',
  asyncHandler(async (req, res) => {
    const { displayName, username, age, password, favoriteTopics } = req.body;

    if (!displayName || !username || !password || age === undefined) {
      return res.status(400).json({
        message: 'displayName, username, age, password are required.',
      });
    }

    if (typeof age !== 'number' || age < 7 || age > 14) {
      return res.status(400).json({ message: 'Age must be between 7 and 14.' });
    }

    if (typeof password !== 'string' || password.length < 6) {
      return res
        .status(400)
        .json({ message: 'Password must have at least 6 characters.' });
    }

    const usernameValue = String(username).toLowerCase().trim();
    const existing = await User.findOne({ username: usernameValue });
    if (existing) {
      return res.status(409).json({ message: 'Username is already taken.' });
    }

    const passwordHash = await bcrypt.hash(password, 10);

    const user = await User.create({
      displayName: String(displayName).trim(),
      username: usernameValue,
      age,
      passwordHash,
      favoriteTopics: Array.isArray(favoriteTopics)
        ? favoriteTopics.map((item) => String(item).trim()).filter(Boolean)
        : [],
    });

    const token = createAuthToken(user);

    return res.status(201).json({
      message: 'Registered successfully.',
      token,
      user: toPublicUser(user),
    });
  }),
);

router.post(
  '/login',
  asyncHandler(async (req, res) => {
    const { username, password } = req.body;

    if (!username || !password) {
      return res
        .status(400)
        .json({ message: 'username and password are required.' });
    }

    const user = await User.findOne({ username: String(username).toLowerCase() });
    if (!user) {
      return res.status(401).json({ message: 'Invalid credentials.' });
    }

    const passwordMatched = await bcrypt.compare(password, user.passwordHash);
    if (!passwordMatched) {
      return res.status(401).json({ message: 'Invalid credentials.' });
    }

    if (!user.isActive) {
      return res.status(403).json({ message: 'Account is inactive.' });
    }

    const token = createAuthToken(user);

    return res.json({
      message: 'Logged in successfully.',
      token,
      user: toPublicUser(user),
    });
  }),
);

router.post(
  '/password/forgot',
  asyncHandler(async (req, res) => {
    const { username } = req.body;

    if (!username || !String(username).trim()) {
      return res.status(400).json({ message: 'username is required.' });
    }

    const user = await User.findOne({
      username: String(username).toLowerCase().trim(),
      isActive: true,
    });

    if (!user) {
      return res.json({
        message: 'If the account exists, reset instructions have been created.',
      });
    }

    const resetToken = crypto.randomBytes(24).toString('hex');
    const tokenHash = await bcrypt.hash(resetToken, 10);

    await PasswordResetToken.create({
      userId: user._id,
      tokenHash,
      expiresAt: new Date(Date.now() + 15 * 60 * 1000),
    });

    const response = {
      message: 'If the account exists, reset instructions have been created.',
    };

    if (process.env.NODE_ENV !== 'production') {
      response.resetToken = resetToken;
    }

    return res.status(201).json(response);
  }),
);

router.post(
  '/password/reset',
  asyncHandler(async (req, res) => {
    const { username, token, password } = req.body;

    if (!username || !token || !password) {
      return res
        .status(400)
        .json({ message: 'username, token, password are required.' });
    }
    if (typeof password !== 'string' || password.length < 6) {
      return res
        .status(400)
        .json({ message: 'Password must have at least 6 characters.' });
    }

    const user = await User.findOne({
      username: String(username).toLowerCase().trim(),
      isActive: true,
    });
    if (!user) {
      return res.status(400).json({ message: 'Invalid reset token.' });
    }

    const candidates = await PasswordResetToken.find({
      userId: user._id,
      usedAt: null,
      expiresAt: { $gt: new Date() },
    }).sort({ createdAt: -1 });

    let matchedToken = null;
    for (const candidate of candidates) {
      const matched = await bcrypt.compare(String(token), candidate.tokenHash);
      if (matched) {
        matchedToken = candidate;
        break;
      }
    }

    if (!matchedToken) {
      return res.status(400).json({ message: 'Invalid reset token.' });
    }

    user.passwordHash = await bcrypt.hash(password, 10);
    await user.save();

    matchedToken.usedAt = new Date();
    await matchedToken.save();

    await PasswordResetToken.updateMany(
      { userId: user._id, usedAt: null },
      { $set: { usedAt: new Date() } },
    );

    return res.json({ message: 'Password reset successfully.' });
  }),
);

router.get(
  '/me',
  requireAuth,
  asyncHandler(async (req, res) => {
    const user = await User.findById(req.user.id);
    if (!user) {
      return res.status(404).json({ message: 'User not found.' });
    }

    return res.json({ user: toPublicUser(user) });
  }),
);

module.exports = router;
