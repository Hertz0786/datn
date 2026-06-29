const express = require('express');
const bcrypt = require('bcryptjs');

const User = require('../models/User');
const PasswordResetToken = require('../models/PasswordResetToken');
const EmailVerificationToken = require('../models/EmailVerificationToken');
const asyncHandler = require('../utils/async-handler');
const { requireAuth } = require('../middlewares/auth');
const { createAuthToken } = require('../utils/token');
const { toPublicUser } = require('../utils/public-user');
const emailService = require('../services/email.service');

const router = express.Router();

function generateCode(length = 6) {
  return Array.from({ length }, () => Math.floor(Math.random() * 10)).join('');
}

// ---------- Send verification code (before registration) ----------

router.post(
  '/send-verification',
  asyncHandler(async (req, res) => {
    const { email } = req.body;

    if (!email || !String(email).trim()) {
      return res.status(400).json({ message: 'email is required.' });
    }

    const emailValue = String(email).toLowerCase().trim();
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(emailValue)) {
      return res.status(400).json({ message: 'Invalid email format.' });
    }

    const existingEmail = await User.findOne({ email: emailValue });
    if (existingEmail) {
      return res.status(409).json({ message: 'This email is already registered.' });
    }

    await EmailVerificationToken.deleteMany({
      email: emailValue,
      type: 'REGISTER',
      usedAt: null,
    });

    const code = generateCode();
    const codeHash = await bcrypt.hash(code, 10);
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000);

    await EmailVerificationToken.create({
      email: emailValue,
      codeHash,
      type: 'REGISTER',
      expiresAt,
    });

    try {
      await emailService.sendVerificationCode(emailValue, code);
    } catch (emailError) {
      console.error('Failed to send verification email:', emailError.message);
      return res.status(503).json({
        message: 'Could not send verification email. Please try again later.',
      });
    }

    const response = {
      message: 'Verification code sent. Check your email.',
    };

    if (process.env.NODE_ENV !== 'production') {
      response.debugCode = code;
    }

    return res.status(200).json(response);
  }),
);

// ---------- Register with email verification ----------

router.post(
  '/register',
  asyncHandler(async (req, res) => {
    const { displayName, username, birthDate, password, email, verificationCode, favoriteTopics } = req.body;

    if (!displayName || !username || !password || birthDate === undefined) {
      return res.status(400).json({
        message: 'displayName, username, birthDate, password are required.',
      });
    }

    let birthDateValue;
    if (birthDate instanceof Date) {
      birthDateValue = birthDate;
    } else if (typeof birthDate === 'string' || typeof birthDate === 'number') {
      birthDateValue = new Date(birthDate);
    }
    if (!birthDateValue || isNaN(birthDateValue.getTime())) {
      return res.status(400).json({ message: 'Invalid birthDate format.' });
    }

    const today = new Date();
    let age = today.getFullYear() - birthDateValue.getFullYear();
    const monthDiff = today.getMonth() - birthDateValue.getMonth();
    if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDateValue.getDate())) {
      age--;
    }
    if (age < 7 || age > 14) {
      return res.status(400).json({ message: 'Age must be between 7 and 14.' });
    }

    if (typeof password !== 'string' || password.length < 6) {
      return res
        .status(400)
        .json({ message: 'Password must have at least 6 characters.' });
    }

    const emailValue = String(email || '').toLowerCase().trim();

    if (emailValue) {
      const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
      if (!emailRegex.test(emailValue)) {
        return res.status(400).json({ message: 'Invalid email format.' });
      }

      if (!verificationCode || typeof verificationCode !== 'string') {
        return res.status(400).json({ message: 'verificationCode is required when providing email.' });
      }

      const candidates = await EmailVerificationToken.find({
        email: emailValue,
        type: 'REGISTER',
        usedAt: null,
        expiresAt: { $gt: new Date() },
      }).sort({ createdAt: -1 });

      let matchedToken = null;
      for (const candidate of candidates) {
        const matched = await bcrypt.compare(String(verificationCode), candidate.codeHash);
        if (matched) {
          matchedToken = candidate;
          break;
        }
      }

      if (!matchedToken) {
        return res.status(400).json({ message: 'Invalid or expired verification code.' });
      }

      matchedToken.usedAt = new Date();
      await matchedToken.save();

      const existingEmail = await User.findOne({ email: emailValue });
      if (existingEmail) {
        return res.status(409).json({ message: 'This email is already registered.' });
      }
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
      birthDate: birthDateValue,
      age,
      passwordHash,
      email: emailValue || null,
      emailVerified: Boolean(emailValue),
      loginProvider: 'LOCAL',
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

// ---------- Login (username only) ----------

router.post(
  '/login',
  asyncHandler(async (req, res) => {
    const { username, password } = req.body;

    if (!username || !password) {
      return res.status(400).json({
        code: 'MISSING_CREDENTIALS',
        message: 'Please enter both username and password.',
      });
    }

    const loginValue = String(username).toLowerCase().trim();

    // Login is username-only: reject anything that looks like an email so
    // we don't accidentally log users in by their email address.
    if (loginValue.includes('@')) {
      return res.status(400).json({
        code: 'USERNAME_INVALID',
        message: 'Please log in with your username, not your email.',
      });
    }

    const user = await User.findOne({ username: loginValue });

    if (!user) {
      // Username not found — return a distinct code so the client can show
      // a clear error message ("Account does not exist") instead of a
      // generic "wrong credentials" notice.
      return res.status(404).json({
        code: 'USER_NOT_FOUND',
        message: 'Account does not exist.',
      });
    }

    if (!user.passwordHash) {
      // Username exists but no local password set (legacy / external account).
      // Treat as bad password to avoid leaking which case happened.
      return res.status(401).json({
        code: 'BAD_PASSWORD',
        message: 'Incorrect password.',
      });
    }

    const passwordMatched = await bcrypt.compare(password, user.passwordHash);
    if (!passwordMatched) {
      return res.status(401).json({
        code: 'BAD_PASSWORD',
        message: 'Incorrect password.',
      });
    }

    if (!user.isActive) {
      return res.status(403).json({
        code: 'ACCOUNT_INACTIVE',
        message: 'This account is inactive. Please contact support.',
      });
    }

    const token = createAuthToken(user);

    return res.json({
      message: 'Logged in successfully.',
      token,
      user: toPublicUser(user),
    });
  }),
);

// ---------- Forgot password (send OTP via email) ----------

router.post(
  '/password/forgot',
  asyncHandler(async (req, res) => {
    const { email } = req.body;

    if (!email || !String(email).trim()) {
      return res.status(400).json({ message: 'email is required.' });
    }

    const emailValue = String(email).toLowerCase().trim();
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(emailValue)) {
      return res.status(400).json({ message: 'Invalid email format.' });
    }

    const user = await User.findOne({
      email: emailValue,
      isActive: true,
    });

    if (!user) {
      return res.json({
        message: 'If the account exists, a reset code has been sent.',
      });
    }

    await PasswordResetToken.deleteMany({
      userId: user._id,
      usedAt: null,
    });

    const code = generateCode();
    const codeHash = await bcrypt.hash(code, 10);

    await PasswordResetToken.create({
      userId: user._id,
      tokenHash: codeHash,
      expiresAt: new Date(Date.now() + 15 * 60 * 1000),
    });

    try {
      await emailService.sendPasswordResetCode(emailValue, code);
    } catch (emailError) {
      console.error('Failed to send reset email:', emailError.message);
      return res.status(503).json({
        message: 'Could not send reset email. Please try again later.',
      });
    }

    const response = {
      message: 'If the account exists, a reset code has been sent.',
    };

    if (process.env.NODE_ENV !== 'production') {
      response.debugCode = code;
    }

    return res.status(200).json(response);
  }),
);

// ---------- Reset password (using OTP from email) ----------

router.post(
  '/password/reset',
  asyncHandler(async (req, res) => {
    const { email, code, password } = req.body;

    if (!email || !code || !password) {
      return res
        .status(400)
        .json({ message: 'email, code, password are required.' });
    }
    if (typeof password !== 'string' || password.length < 6) {
      return res
        .status(400)
        .json({ message: 'Password must have at least 6 characters.' });
    }

    const emailValue = String(email).toLowerCase().trim();
    const user = await User.findOne({
      email: emailValue,
      isActive: true,
    });
    if (!user) {
      return res.status(400).json({ message: 'Invalid reset code.' });
    }

    const tokens = await PasswordResetToken.find({
      userId: user._id,
      usedAt: null,
    }).sort({ createdAt: -1 });

    let matchedToken = null;
    for (const tokenDoc of tokens) {
      const isMatch = await bcrypt.compare(code, tokenDoc.tokenHash);
      if (isMatch) {
        matchedToken = tokenDoc;
        break;
      }
    }

    if (!matchedToken) {
      return res.status(400).json({ message: 'Invalid or expired reset code.' });
    }

    if (new Date() > matchedToken.expiresAt) {
      return res.status(400).json({ message: 'Reset code has expired.' });
    }

    user.passwordHash = await bcrypt.hash(password, 10);
    await user.save();

    await PasswordResetToken.updateMany(
      { userId: user._id },
      { $set: { usedAt: new Date() } },
    );

    return res.json({ message: 'Password reset successfully.' });
  }),
);

// ---------- /me ----------

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

// ---------- /me/email ----------
// Returns the current user's verified email address. Email is
// intentionally excluded from the default `/me` payload (it is PII).
// This endpoint is only called when the user explicitly opens the
// change-password flow, and only returns the address when it has been
// verified so we can reliably deliver an OTP there.
router.get(
  '/me/email',
  requireAuth,
  asyncHandler(async (req, res) => {
    const user = await User.findById(req.user.id);
    if (!user || !user.isActive) {
      return res.status(404).json({ message: 'User not found.' });
    }

    const verified = Boolean(user.email && user.emailVerified);
    return res.json({
      hasEmail: verified,
      email: verified ? user.email : null,
    });
  }),
);

module.exports = router;
