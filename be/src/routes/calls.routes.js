const express = require('express');
const mongoose = require('mongoose');

const CallLog = require('../models/CallLog');
const CallSettings = require('../models/CallSettings');
const Friendship = require('../models/Friendship');
const Block = require('../models/Block');
const User = require('../models/User');
const { requireAuth } = require('../middlewares/auth');
const { isValidObjectId } = require('../middlewares/object-id');
const { normalizeFriendPair } = require('../utils/friendship');
const agoraTokenService = require('../services/agora-token.service');
const AgoraTokenService = agoraTokenService.constructor;
const env = require('../config/env');
const { emitToUser } = require('../realtime/socket');

const router = express.Router();

const RING_TIMEOUT_MS = 30 * 1000;

const pendingRings = new Map(); // callId -> timeout handle

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function publicUserPayload(user) {
  if (!user) {
    return null;
  }
  // Accept both a User document (has displayName/avatarUrl) and the minimal
  // payload attached by the auth middleware (id/role/age/username only).
  const idSource = user._id != null ? user._id : user.id;
  const id = idSource != null ? idSource.toString() : '';
  return {
    id,
    displayName: user.displayName || user.username || '',
    username: user.username || '',
    age: user.age || 0,
    role: user.role || 'CHILD',
    avatarUrl: user.avatarUrl || '',
  };
}

async function loadUserSafely(userId) {
  if (!isValidObjectId(userId)) {
    return null;
  }
  return User.findById(userId).select(
    '_id displayName username age role avatarUrl isActive',
  );
}

async function areFriends(userIdA, userIdB) {
  if (!isValidObjectId(userIdA) || !isValidObjectId(userIdB)) {
    return false;
  }
  const friendship = await Friendship.findOne(
    normalizeFriendPair(userIdA, userIdB),
  ).select('_id');
  return Boolean(friendship);
}

async function isBlockedEitherWay(userIdA, userIdB) {
  if (!isValidObjectId(userIdA) || !isValidObjectId(userIdB)) {
    return true;
  }
  const block = await Block.findOne({
    $or: [
      { blockerId: userIdA, blockedId: userIdB },
      { blockerId: userIdB, blockedId: userIdA },
    ],
  }).select('_id');
  return Boolean(block);
}

function getOrCreateSettings(userId) {
  return CallSettings.findOneAndUpdate(
    { user: userId },
    { $setOnInsert: { user: userId } },
      { upsert: true, returnNewDocument: true, setDefaultsOnInsert: true },
  );
}

function clearRingTimeout(callId) {
  const key = callId.toString();
  const handle = pendingRings.get(key);
  if (handle) {
    clearTimeout(handle);
    pendingRings.delete(key);
  }
}

function scheduleRingTimeout(call) {
  const handle = setTimeout(async () => {
    pendingRings.delete(call._id.toString());
    try {
      const fresh = await CallLog.findById(call._id);
      if (!fresh || fresh.status !== 'ringing') {
        return;
      }
      fresh.status = 'missed';
      fresh.endedAt = new Date();
      fresh.endReason = 'missed_timeout';
      await fresh.save();

      emitToUser(call.initiator.toString(), 'call:timeout', {
        callId: call._id.toString(),
      });
      emitToUser(call.callee.toString(), 'call:missed', {
        callId: call._id.toString(),
      });
    } catch (error) {
      // Best-effort: surface but don't crash the timeout.
      console.error('call timeout handling failed:', error.message);
    }
  }, RING_TIMEOUT_MS);
  pendingRings.set(call._id.toString(), handle);
}

function callPayload(call, currentUserId) {
  return {
    id: call._id.toString(),
    channelName: call.channelName,
    callType: call.callType,
    status: call.status,
    initiator: call.initiator.toString(),
    callee: call.callee.toString(),
    startedAt: call.startedAt,
    acceptedAt: call.acceptedAt,
    endedAt: call.endedAt,
    durationSeconds: call.durationSeconds,
    endReason: call.endReason,
    isOutgoing: call.initiator.toString() === currentUserId,
  };
}

// ---------------------------------------------------------------------------
// POST /api/calls/init  - kick off a new call
// ---------------------------------------------------------------------------
router.post('/init', requireAuth, async (req, res) => {
  try {
    const { calleeId, callType } = req.body || {};
    const initiatorId = req.user.id.toString();

    console.log(`[calls/init] initiator=${initiatorId} calleeId="${calleeId}" callType="${callType}"`);

    if (!calleeId) {
      return res.status(400).json({ message: 'Missing callee ID.' });
    }
    if (!['voice', 'video'].includes(callType)) {
      return res.status(400).json({ message: 'Invalid call type. Must be "voice" or "video".' });
    }

    if (!agoraTokenService.isConfigured()) {
      return res.status(503).json({
        message: 'Calling service is not configured.',
      });
    }

    if (calleeId === initiatorId) {
      return res
        .status(400)
        .json({ message: 'You cannot call yourself.' });
    }

    if (!isValidObjectId(calleeId)) {
      return res.status(400).json({ message: 'Invalid callee.' });
    }

    const [callee, isFriend, blocked] = await Promise.all([
      loadUserSafely(calleeId),
      areFriends(initiatorId, calleeId),
      isBlockedEitherWay(initiatorId, calleeId),
    ]);

    if (!callee || !callee.isActive) {
      return res.status(404).json({ message: 'User not found.' });
    }

    if (blocked) {
      return res
        .status(403)
        .json({ message: 'You cannot call this user.' });
    }

    if (!isFriend) {
      return res
        .status(403)
        .json({ message: 'You can only call friends.' });
    }

    const [callerSettings, calleeSettings] = await Promise.all([
      getOrCreateSettings(initiatorId),
      getOrCreateSettings(calleeId),
    ]);

    if (
      !callerSettings.allowedCallTypes.includes(callType) ||
      !calleeSettings.allowedCallTypes.includes(callType)
    ) {
      console.log(
        `[calls/init] call type rejected: callerTypes=${callerSettings.allowedCallTypes} calleeTypes=${calleeSettings.allowedCallTypes} requested=${callType}`,
      );
      return res
        .status(403)
        .json({ message: 'This call type is disabled.' });
    }

    if (callerSettings.whoCanCall === 'nobody') {
      console.log(`[calls/init] caller ${initiatorId} has whoCanCall=nobody`);
      return res
        .status(403)
        .json({ message: 'You are not allowed to make calls.' });
    }

    if (calleeSettings.whoCanCall === 'nobody') {
      console.log(`[calls/init] callee ${calleeId} has whoCanCall=nobody`);
      return res
        .status(403)
        .json({ message: 'User is not accepting calls.' });
    }

    // Refuse the call if the caller is already in an active ringing/accepted
    // call to avoid joining two channels at once.
    const activeCallerCall = await CallLog.findOne({
      initiator: initiatorId,
      status: { $in: ['ringing', 'accepted'] },
    }).select('_id');
    if (activeCallerCall) {
      return res
        .status(409)
        .json({ message: 'You already have an active call.' });
    }

    const callId = new mongoose.Types.ObjectId();
    const channelName = `call_${callId.toHexString()}`;
    const callerUid = AgoraTokenService.userIdToUid(initiatorId);
    const callerToken = agoraTokenService.generateToken(
      channelName,
      callerUid,
      'publisher',
    );

    // Load the full caller record so the callee UI can show displayName
    // and avatar. `req.user` only carries the JWT claim subset.
    const caller = await loadUserSafely(initiatorId);

    const call = await CallLog.create({
      _id: callId,
      channelName,
      callType,
      status: 'ringing',
      initiator: initiatorId,
      callee: calleeId,
      participants: [{ user: initiatorId }, { user: calleeId }],
      startedAt: new Date(),
    });

    scheduleRingTimeout(call);

    if (!caller) {
      console.error(
        'POST /api/calls/init: caller record missing for initiator',
        initiatorId,
      );
      return res
        .status(500)
        .json({ message: 'Caller profile not found.' });
    }

    emitToUser(calleeId, 'call:incoming', {
      callId: call._id.toString(),
      channelName,
      callType,
      caller: publicUserPayload(caller),
    });

    return res.json({
      callId: call._id.toString(),
      channelName,
      callType,
      token: callerToken,
      uid: callerUid,
      appId: env.agora.appId,
      callee: publicUserPayload(callee),
    });
  } catch (error) {
    console.error('POST /api/calls/init failed:', error);
    return res.status(500).json({ message: 'Failed to start call.' });
  }
});

// ---------------------------------------------------------------------------
// POST /api/calls/:id/accept
// ---------------------------------------------------------------------------
router.post('/:id/accept', requireAuth, async (req, res) => {
  try {
    const callId = req.params.id;
    if (!isValidObjectId(callId)) {
      return res.status(400).json({ message: 'Invalid call id.' });
    }

    const userId = req.user.id.toString();
    const call = await CallLog.findById(callId);
    if (!call) {
      return res.status(404).json({ message: 'Call not found.' });
    }
    if (call.callee.toString() !== userId) {
      return res.status(403).json({ message: 'Not your call.' });
    }
    if (call.status !== 'ringing') {
      return res
        .status(409)
        .json({ message: 'Call is no longer available.' });
    }

    const blocked = await isBlockedEitherWay(
      call.initiator.toString(),
      userId,
    );
    if (blocked) {
      call.status = 'blocked';
      call.endedAt = new Date();
      call.endReason = 'blocked';
      await call.save();
      clearRingTimeout(call._id);
      emitToUser(call.initiator.toString(), 'call:rejected', {
        callId: call._id.toString(),
        reason: 'blocked',
      });
      return res.status(403).json({ message: 'Call is unavailable.' });
    }

    const now = new Date();
    call.status = 'accepted';
    call.acceptedAt = now;
    const participant = call.participants.find(
      (entry) => entry.user.toString() === userId,
    );
    if (participant) {
      participant.joinedAt = now;
    }
    await call.save();
    clearRingTimeout(call._id);

    const calleeUid = AgoraTokenService.userIdToUid(userId);
    const calleeToken = agoraTokenService.generateToken(
      call.channelName,
      calleeUid,
      'publisher',
    );

    emitToUser(call.initiator.toString(), 'call:accepted', {
      callId: call._id.toString(),
      channelName: call.channelName,
      callType: call.callType,
      callee: publicUserPayload(req.user),
    });

    return res.json({
      callId: call._id.toString(),
      channelName: call.channelName,
      callType: call.callType,
      token: calleeToken,
      uid: calleeUid,
      appId: env.agora.appId,
    });
  } catch (error) {
    console.error('POST /api/calls/:id/accept failed:', error);
    return res.status(500).json({ message: 'Failed to accept call.' });
  }
});

// ---------------------------------------------------------------------------
// POST /api/calls/:id/reject
// ---------------------------------------------------------------------------
router.post('/:id/reject', requireAuth, async (req, res) => {
  try {
    const callId = req.params.id;
    if (!isValidObjectId(callId)) {
      return res.status(400).json({ message: 'Invalid call id.' });
    }

    const userId = req.user.id.toString();
    const call = await CallLog.findById(callId);
    if (!call) {
      return res.status(404).json({ message: 'Call not found.' });
    }
    if (call.callee.toString() !== userId) {
      return res.status(403).json({ message: 'Not your call.' });
    }
    if (call.status !== 'ringing') {
      return res.status(409).json({ message: 'Call is no longer ringing.' });
    }

    call.status = 'rejected';
    call.endedAt = new Date();
    call.endReason = 'rejected';
    await call.save();
    clearRingTimeout(call._id);

    emitToUser(call.initiator.toString(), 'call:rejected', {
      callId: call._id.toString(),
    });

    return res.json({ success: true });
  } catch (error) {
    console.error('POST /api/calls/:id/reject failed:', error);
    return res.status(500).json({ message: 'Failed to reject call.' });
  }
});

// ---------------------------------------------------------------------------
// POST /api/calls/:id/end  - any participant can end the call
// ---------------------------------------------------------------------------
router.post('/:id/end', requireAuth, async (req, res) => {
  try {
    const callId = req.params.id;
    if (!isValidObjectId(callId)) {
      return res.status(400).json({ message: 'Invalid call id.' });
    }

    const userId = req.user.id.toString();
    const call = await CallLog.findById(callId);
    if (!call) {
      return res.status(404).json({ message: 'Call not found.' });
    }

    const isInitiator = call.initiator.toString() === userId;
    const isCallee = call.callee.toString() === userId;
    if (!isInitiator && !isCallee) {
      return res.status(403).json({ message: 'Not a participant.' });
    }

    // If a call is still ringing and the caller hangs up, count it as
    // cancelled rather than accepted.
    if (call.status === 'ringing') {
      call.status = 'ended';
      call.endedAt = new Date();
      call.endReason = isCallee ? 'rejected' : 'caller_ended';
      await call.save();
      clearRingTimeout(call._id);

      const otherUserId = isInitiator
        ? call.callee.toString()
        : call.initiator.toString();
      emitToUser(otherUserId, 'call:cancelled', {
        callId: call._id.toString(),
      });
      return res.json({ success: true, status: call.status });
    }

    if (call.status === 'ended' || call.status === 'rejected') {
      return res.json({ success: true, status: call.status });
    }

    const now = new Date();
    const start = call.acceptedAt || call.startedAt || now;
    call.status = 'ended';
    call.endedAt = now;
    call.endReason = isInitiator ? 'caller_ended' : 'callee_ended';
    call.durationSeconds = Math.max(
      0,
      Math.floor((now.getTime() - start.getTime()) / 1000),
    );

    const participant = call.participants.find(
      (entry) => entry.user.toString() === userId,
    );
    if (participant) {
      participant.leftAt = now;
    }
    await call.save();
    clearRingTimeout(call._id);

    const otherUserId = isInitiator
      ? call.callee.toString()
      : call.initiator.toString();
    emitToUser(otherUserId, 'call:ended', {
      callId: call._id.toString(),
      durationSeconds: call.durationSeconds,
      endedBy: userId,
    });

    return res.json({
      success: true,
      status: call.status,
      durationSeconds: call.durationSeconds,
    });
  } catch (error) {
    console.error('POST /api/calls/:id/end failed:', error);
    return res.status(500).json({ message: 'Failed to end call.' });
  }
});

// ---------------------------------------------------------------------------
// GET /api/calls/history  - paginated history of recent calls for current user
// ---------------------------------------------------------------------------
router.get('/history', requireAuth, async (req, res) => {
  try {
    const userId = req.user.id.toString();
    const limit = Math.min(parseInt(req.query.limit, 10) || 30, 100);
    const before = req.query.before;

    const query = {
      $or: [{ initiator: userId }, { callee: userId }],
    };
    if (before && isValidObjectId(before)) {
      query._id = { $lt: new mongoose.Types.ObjectId(before) };
    }

    const logs = await CallLog.find(query)
      .sort({ _id: -1 })
      .limit(limit + 1)
      .populate('initiator', 'displayName username age role avatarUrl')
      .populate('callee', 'displayName username age role avatarUrl');

    const hasMore = logs.length > limit;
    const items = logs.slice(0, limit).map((log) => ({
      ...callPayload(log, userId),
      initiatorProfile: publicUserPayload(log.initiator),
      calleeProfile: publicUserPayload(log.callee),
    }));

    return res.json({
      items,
      hasMore,
      nextBefore: hasMore ? items[items.length - 1].id : null,
    });
  } catch (error) {
    console.error('GET /api/calls/history failed:', error);
    return res.status(500).json({ message: 'Failed to load history.' });
  }
});

// ---------------------------------------------------------------------------
// GET /api/calls/settings  - per-user call settings (auto-create defaults)
// ---------------------------------------------------------------------------
router.get('/settings', requireAuth, async (req, res) => {
  try {
    const userId = req.user.id.toString();
    const settings = await getOrCreateSettings(userId);
    return res.json({
      whoCanCall: settings.whoCanCall,
      allowedCallTypes: settings.allowedCallTypes,
      maxCallDurationSeconds: settings.maxCallDurationSeconds,
      notificationsEnabled: settings.notificationsEnabled,
    });
  } catch (error) {
    console.error('GET /api/calls/settings failed:', error);
    return res.status(500).json({ message: 'Failed to load settings.' });
  }
});

router.patch('/settings', requireAuth, async (req, res) => {
  try {
    const userId = req.user.id.toString();
    const update = {};

    if (
      typeof req.body?.whoCanCall === 'string' &&
      ['friends_only', 'everyone', 'nobody'].includes(req.body.whoCanCall)
    ) {
      update.whoCanCall = req.body.whoCanCall;
    }
    if (Array.isArray(req.body?.allowedCallTypes)) {
      const types = req.body.allowedCallTypes.filter((entry) =>
        ['voice', 'video'].includes(entry),
      );
      if (types.length > 0) {
        update.allowedCallTypes = Array.from(new Set(types));
      }
    }
    if (
      typeof req.body?.maxCallDurationSeconds === 'number' &&
      req.body.maxCallDurationSeconds >= 0
    ) {
      update.maxCallDurationSeconds = Math.min(
        Math.floor(req.body.maxCallDurationSeconds),
        60 * 60 * 4,
      );
    }
    if (typeof req.body?.notificationsEnabled === 'boolean') {
      update.notificationsEnabled = req.body.notificationsEnabled;
    }

    const settings = await CallSettings.findOneAndUpdate(
      { user: userId },
      { $set: update, $setOnInsert: { user: userId } },
      { returnNewDocument: true, upsert: true, setDefaultsOnInsert: true },
    );

    return res.json({
      whoCanCall: settings.whoCanCall,
      allowedCallTypes: settings.allowedCallTypes,
      maxCallDurationSeconds: settings.maxCallDurationSeconds,
      notificationsEnabled: settings.notificationsEnabled,
    });
  } catch (error) {
    console.error('PATCH /api/calls/settings failed:', error);
    return res.status(500).json({ message: 'Failed to update settings.' });
  }
});

module.exports = router;
