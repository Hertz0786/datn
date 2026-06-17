const jwt = require('jsonwebtoken');
const env = require('../config/env');
const User = require('../models/User');

// Throttle writes so we do not hammer Mongo on every single request.
// The value below is in milliseconds: 60_000 = 1 minute. That means a
// user's lastActiveAt is updated at most once per minute even if they
// make hundreds of API calls in that window.
const ACTIVE_WRITE_THROTTLE_MS = 60_000;

function requireAuth(req, res, next) {
  const authHeader = req.headers.authorization || '';
  const [scheme, token] = authHeader.split(' ');

  if (scheme !== 'Bearer' || !token) {
    return res.status(401).json({ message: 'Missing or invalid token.' });
  }

  try {
    const decoded = jwt.verify(token, env.jwtSecret);
    req.user = {
      id: decoded.sub,
      role: decoded.role,
      age: decoded.age,
      username: decoded.username,
    };

    // Fire-and-forget lastActiveAt update. Skipped for read-only / health
    // routes that opt out via x-skip-activity header (none today, but
    // keeps the door open). Throttled per user so we do not pound Mongo.
    const skipActivity = req.headers['x-skip-activity'] === '1';
    if (!skipActivity) {
      touchLastActive(req.user.id);
    }

    return next();
  } catch (error) {
    return res.status(401).json({ message: 'Invalid or expired token.' });
  }
}

// Cache the last write timestamp per user so we only round-trip Mongo
// once per minute. Cleared on server restart which is fine.
const lastWriteCache = new Map();

function touchLastActive(userId) {
  if (!userId) {
    return;
  }
  const now = Date.now();
  const last = lastWriteCache.get(userId) || 0;
  if (now - last < ACTIVE_WRITE_THROTTLE_MS) {
    return;
  }
  lastWriteCache.set(userId, now);
  User.updateOne(
    { _id: userId },
    { $set: { lastActiveAt: new Date(now) } },
  ).catch(() => {
    // Roll back the cache entry so the next request retries instead of
    // skipping for another minute.
    lastWriteCache.delete(userId);
  });
}

function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({ message: 'Unauthorized.' });
    }

    if (!roles.includes(req.user.role)) {
      return res.status(403).json({ message: 'Forbidden.' });
    }

    return next();
  };
}

module.exports = {
  requireAuth,
  requireRole,
  touchLastActive,
  ACTIVE_WRITE_THROTTLE_MS,
};

