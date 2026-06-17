const express = require('express');
const mongoose = require('mongoose');

const Chat = require('../models/Chat');
const Group = require('../models/Group');
const GroupMember = require('../models/GroupMember');
const Notification = require('../models/Notification');
const Post = require('../models/Post');
const User = require('../models/User');
const { withPostMeta } = require('../utils/post-meta');
const { buildChatSummaries } = require('../utils/chat-summary');
const asyncHandler = require('../utils/async-handler');
const { requireAuth } = require('../middlewares/auth');
const { isValidObjectId } = require('../middlewares/object-id');
const {
  sendNotification,
  broadcastNotification,
  NOTIFICATION_TYPES,
} = require('../services/notification-service');

async function filterNonChildAuthorPosts(posts, currentUser) {
  if (currentUser.role !== 'CHILD' || posts.length === 0) {
    return posts;
  }

  const authorIds = [...new Set(posts.map((post) => post.authorId.toString()))];
  const childAuthors = await User.find({
    _id: { $in: authorIds },
    role: 'CHILD',
    isActive: true,
  }).select('_id');
  const childAuthorIds = new Set(childAuthors.map((user) => user._id.toString()));

  return posts.filter((post) => childAuthorIds.has(post.authorId.toString()));
}

function actorSnapshot(user) {
  return {
    actorId: user._id.toString(),
    actorName: user.displayName || user.username || 'Ai đó',
    actorUsername: user.username || '',
    actorAvatarUrl: user.avatarUrl || '',
  };
}

function sameIds(left, right) {
  const a = left.map((id) => id.toString()).sort();
  const b = right.map((id) => id.toString()).sort();
  return a.length === b.length && a.every((id, index) => id === b[index]);
}

async function activeGroupMemberIds(groupId) {
  const members = await GroupMember.find({
    groupId,
    status: 'ACTIVE',
  }).select('userId');
  return members.map((member) => member.userId);
}

async function getOrCreateSocialGroupChat(group) {
  const memberIds = await activeGroupMemberIds(group._id);
  let chat = await Chat.findOne({
    type: 'SOCIAL_GROUP',
    groupId: group._id,
  });

  if (!chat) {
    return Chat.create({
      type: 'SOCIAL_GROUP',
      groupId: group._id,
      title: group.name,
      avatarUrl: group.avatarUrl || '',
      memberIds,
      createdBy: group.ownerId,
    });
  }

  const update = {};
  if (chat.title !== group.name) {
    update.title = group.name;
  }
  if ((chat.avatarUrl || '') !== (group.avatarUrl || '')) {
    update.avatarUrl = group.avatarUrl || '';
  }
  if (!sameIds(chat.memberIds, memberIds)) {
    update.memberIds = memberIds;
  }

  if (Object.keys(update).length === 0) {
    return chat;
  }

  return Chat.findByIdAndUpdate(
    chat._id,
    { $set: update },
    { new: true, runValidators: true },
  );
}

const router = express.Router();

router.use(requireAuth);

router.post(
  '/',
  asyncHandler(async (req, res) => {
    const { name, topic, description, ageMin = 7, ageMax = 14 } = req.body;

    if (!name || !topic) {
      return res.status(400).json({ message: 'name and topic are required.' });
    }
    if (Number(ageMin) > Number(ageMax)) {
      return res.status(400).json({ message: 'ageMin must be <= ageMax.' });
    }

    const group = await Group.create({
      name: String(name).trim(),
      topic: String(topic).trim(),
      description: description ? String(description).trim() : '',
      ageMin: Number(ageMin),
      ageMax: Number(ageMax),
      ownerId: req.user.id,
      memberCount: 1,
    });

    await GroupMember.create({
      groupId: group._id,
      userId: req.user.id,
      role: 'OWNER',
      status: 'ACTIVE',
    });

    // Notify admins so newly created groups appear in the moderation queue.
    const adminDocs = await User.find({ role: 'ADMIN', isActive: true }).select(
      '_id displayName username',
    );
    const owner = await User.findById(req.user.id).select(
      'displayName username avatarUrl',
    );
    if (adminDocs.length > 0) {
      await broadcastNotification({
        userIds: adminDocs.map((admin) => admin._id),
        actorId: req.user.id,
        type: NOTIFICATION_TYPES.ADMIN_MODERATION_ALERT,
        payload: {
          subjectType: 'GROUP',
          subjectId: group._id.toString(),
          groupId: group._id.toString(),
          groupName: group.name,
          actorName: owner?.displayName || owner?.username || 'Ai đó',
          actorUsername: owner?.username || '',
          actorAvatarUrl: owner?.avatarUrl || '',
          reason: 'GROUP_CREATED',
          message: `${owner?.displayName || 'Một người dùng'} vừa tạo nhóm "${group.name}".`,
          navigationTarget: {
            route: 'ADMIN_GROUPS',
            groupId: group._id.toString(),
          },
        },
      });
    }

    return res.status(201).json({ message: 'Group created.', group });
  }),
);

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const q = String(req.query.q || '').trim();
    const topic = String(req.query.topic || '').trim();
    const age = req.query.age !== undefined ? Number(req.query.age) : req.user.age;
    const limit = Math.max(1, Math.min(50, Number(req.query.limit) || 20));
    const beforeRaw = String(req.query.before || '').trim();
    const beforeDate = beforeRaw ? new Date(beforeRaw) : null;
    if (beforeRaw && Number.isNaN(beforeDate.getTime())) {
      return res.status(400).json({ message: 'Invalid before cursor.' });
    }

    const query = {
      status: 'ACTIVE',
      ageMin: { $lte: age },
      ageMax: { $gte: age },
    };

    if (topic) {
      query.topic = topic;
    }

    if (q) {
      query.$or = [
        { name: { $regex: q, $options: 'i' } },
        { description: { $regex: q, $options: 'i' } },
      ];
    }

    if (beforeDate) {
      query.createdAt = { $lt: beforeDate };
    }

    const groups = await Group.find(query)
      .sort({ createdAt: -1 })
      .limit(limit + 1);
    const hasMore = groups.length > limit;
    const page = hasMore ? groups.slice(0, limit) : groups;
    const nextBefore = hasMore
      ? new Date(page[page.length - 1].createdAt).toISOString()
      : null;

    return res.json({ items: page, nextBefore, hasMore });
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

    const limit = Math.max(1, Math.min(50, Number(req.query.limit) || 20));
    const beforeRaw = String(req.query.before || '').trim();
    const beforeDate = beforeRaw ? new Date(beforeRaw) : null;
    if (beforeRaw && Number.isNaN(beforeDate.getTime())) {
      return res.status(400).json({ message: 'Invalid before cursor.' });
    }

    const query = {
      userId,
      status: 'ACTIVE',
    };
    if (beforeDate) {
      query.createdAt = { $lt: beforeDate };
    }

    const memberships = await GroupMember.find(query)
      .sort({ createdAt: -1 })
      .limit(limit + 1);

    const hasMore = memberships.length > limit;
    const page = hasMore ? memberships.slice(0, limit) : memberships;
    if (page.length === 0) {
      return res.json({ items: [], nextBefore: null, hasMore: false });
    }

    const groupIds = page.map((membership) => membership.groupId);
    const groups = await Group.find({
      _id: { $in: groupIds },
      status: 'ACTIVE',
    });
    const groupById = new Map(
      groups.map((group) => [group._id.toString(), group]),
    );
    const items = page
      .map((membership) => groupById.get(membership.groupId.toString()))
      .filter(Boolean);

    const nextBefore = hasMore
      ? new Date(page[page.length - 1].createdAt).toISOString()
      : null;

    return res.json({ items, nextBefore, hasMore });
  }),
);

router.get(
  '/:groupId',
  asyncHandler(async (req, res) => {
    const { groupId } = req.params;
    if (!isValidObjectId(groupId)) {
      return res.status(400).json({ message: 'Invalid groupId.' });
    }

    const group = await Group.findById(groupId);
    if (!group) {
      return res.status(404).json({ message: 'Group not found.' });
    }

    const members = await GroupMember.find({
      groupId,
      status: 'ACTIVE',
    })
      .sort({ createdAt: 1 })
      .limit(50)
      .populate('userId', 'displayName username age avatarUrl');

    const isJoined = members.some(
      (item) => item.userId && item.userId._id.toString() === req.user.id,
    );

    const currentMembership = await GroupMember.findOne({
      groupId,
      userId: req.user.id,
    }).select('status role');

    let pendingMembers = [];
    if (group.ownerId.toString() === req.user.id) {
      pendingMembers = await GroupMember.find({
        groupId,
        status: 'PENDING',
      })
        .sort({ createdAt: 1 })
        .limit(50)
        .populate('userId', 'displayName username age avatarUrl');
    }

    return res.json({
      group,
      members,
      pendingMembers,
      isJoined,
      isPending: currentMembership?.status === 'PENDING',
      membershipStatus: currentMembership?.status || 'NONE',
    });
  }),
);

router.post(
  '/:groupId/chat',
  asyncHandler(async (req, res) => {
    const { groupId } = req.params;
    if (!isValidObjectId(groupId)) {
      return res.status(400).json({ message: 'Invalid groupId.' });
    }

    const group = await Group.findById(groupId);
    if (!group || group.status !== 'ACTIVE') {
      return res.status(404).json({ message: 'Group not found.' });
    }

    const membership = await GroupMember.findOne({
      groupId,
      userId: req.user.id,
      status: 'ACTIVE',
    }).select('_id');
    if (!membership) {
      return res
        .status(403)
        .json({ message: 'You must join the group to use group chat.' });
    }

    const chat = await getOrCreateSocialGroupChat(group);
    const [summary] = await buildChatSummaries([chat], req.user.id);
    return res.json({ chat: summary });
  }),
);

router.delete(
  '/:groupId/members/:userId',
  asyncHandler(async (req, res) => {
    const { groupId, userId } = req.params;
    if (!isValidObjectId(groupId)) {
      return res.status(400).json({ message: 'Invalid groupId.' });
    }
    if (!isValidObjectId(userId)) {
      return res.status(400).json({ message: 'Invalid userId.' });
    }

    const group = await Group.findById(groupId);
    if (!group || group.status !== 'ACTIVE') {
      return res.status(404).json({ message: 'Group not found.' });
    }

    if (group.ownerId.toString() !== req.user.id) {
      return res.status(403).json({ message: 'Only the group owner can remove members.' });
    }

    if (userId === req.user.id || userId === group.ownerId.toString()) {
      return res.status(400).json({ message: 'The group owner cannot be removed.' });
    }

    const member = await GroupMember.findOne({
      groupId,
      userId,
      status: 'ACTIVE',
    });

    if (!member) {
      return res.status(404).json({ message: 'Active group member not found.' });
    }

    if (member.role === 'OWNER') {
      return res.status(400).json({ message: 'The group owner cannot be removed.' });
    }

    const session = await mongoose.startSession();
    await session.withTransaction(async () => {
      await GroupMember.updateOne(
        { _id: member._id },
        { $set: { status: 'LEFT' } },
        { session },
      );
      await Group.updateOne(
        { _id: groupId, memberCount: { $gt: 1 } },
        { $inc: { memberCount: -1 } },
        { session },
      );
    });
    session.endSession();

    await Chat.updateOne(
      { type: 'SOCIAL_GROUP', groupId },
      { $pull: { memberIds: userId } },
    );

    const owner = await User.findById(req.user.id).select(
      'displayName username avatarUrl',
    );
    await sendNotification({
      userId,
      actorId: req.user.id,
      type: NOTIFICATION_TYPES.GROUP_MEMBER_REMOVED,
      payload: {
        groupId,
        groupName: group.name,
        byUserId: req.user.id,
        ...(owner ? actorSnapshot(owner) : {}),
        navigationTarget: {
          route: 'GROUP_DETAIL',
          groupId,
        },
      },
    });

    // Surface the moderation event to admins.
    const adminDocs = await User.find({ role: 'ADMIN', isActive: true }).select(
      '_id',
    );
    if (adminDocs.length > 0) {
      await broadcastNotification({
        userIds: adminDocs.map((admin) => admin._id),
        actorId: req.user.id,
        type: NOTIFICATION_TYPES.ADMIN_MODERATION_ALERT,
        payload: {
          subjectType: 'GROUP',
          subjectId: groupId,
          groupId,
          groupName: group.name,
          removedUserId: userId,
          reason: 'GROUP_MEMBER_REMOVED',
          message: `Một thành viên vừa bị xóa khỏi nhóm "${group.name}".`,
          navigationTarget: {
            route: 'ADMIN_GROUPS',
            groupId,
          },
        },
      });
    }

    return res.json({ message: 'Member removed from group.' });
  }),
);

router.patch(
  '/:groupId/join-requests/:userId',
  asyncHandler(async (req, res) => {
    const { groupId, userId } = req.params;
    const action = String(req.body.action || '').trim().toLowerCase();

    if (!isValidObjectId(groupId)) {
      return res.status(400).json({ message: 'Invalid groupId.' });
    }
    if (!isValidObjectId(userId)) {
      return res.status(400).json({ message: 'Invalid userId.' });
    }
    if (!['accept', 'reject'].includes(action)) {
      return res.status(400).json({ message: 'action must be accept or reject.' });
    }

    const group = await Group.findById(groupId);
    if (!group || group.status !== 'ACTIVE') {
      return res.status(404).json({ message: 'Group not found.' });
    }
    if (group.ownerId.toString() !== req.user.id) {
      return res.status(403).json({ message: 'Only the group owner can review join requests.' });
    }
    if (userId === req.user.id || userId === group.ownerId.toString()) {
      return res.status(400).json({ message: 'Owner request cannot be reviewed.' });
    }

    const nextStatus = action === 'accept' ? 'ACTIVE' : 'LEFT';
    const member = await GroupMember.findOneAndUpdate(
      { groupId, userId, status: 'PENDING' },
      { $set: { status: nextStatus, role: 'MEMBER' } },
      { new: true, runValidators: true },
    );

    if (!member) {
      return res.status(404).json({ message: 'Pending join request not found.' });
    }

    if (action === 'accept') {
      await Group.updateOne({ _id: groupId }, { $inc: { memberCount: 1 } });
      await Chat.updateOne(
        { type: 'SOCIAL_GROUP', groupId },
        { $addToSet: { memberIds: userId } },
      );
    }

    await Notification.updateMany(
      {
        userId: req.user.id,
        type: 'GROUP_JOIN_REQUEST',
        readAt: null,
        'payload.groupId': groupId,
        'payload.fromUserId': userId,
      },
      { $set: { readAt: new Date() } },
    );

    const reviewer = await User.findById(req.user.id).select(
      'displayName username avatarUrl',
    );
    await sendNotification({
      userId,
      actorId: req.user.id,
      type: action === 'accept'
        ? NOTIFICATION_TYPES.GROUP_JOIN_REQUEST_ACCEPTED
        : NOTIFICATION_TYPES.GROUP_JOIN_REQUEST_REJECTED,
      payload: {
        groupId,
        groupName: group.name,
        byUserId: req.user.id,
        ...(reviewer ? actorSnapshot(reviewer) : {}),
        navigationTarget:
          action === 'accept'
            ? {
                route: 'GROUP_DETAIL',
                groupId,
              }
            : {
                route: 'GROUPS',
              },
      },
    });

    if (action === 'accept') {
      // Notify other ACTIVE members that someone new joined.
      const newMember = await User.findById(userId).select(
        'displayName username avatarUrl',
      );
      const memberIds = await activeGroupMemberIds(groupId);
      await broadcastNotification({
        userIds: memberIds,
        actorId: req.user.id,
        type: NOTIFICATION_TYPES.GROUP_MEMBER_JOINED,
        payload: {
          groupId,
          groupName: group.name,
          newMemberId: userId,
          actorName:
            newMember?.displayName || newMember?.username || 'Ai đó',
          actorUsername: newMember?.username || '',
          actorAvatarUrl: newMember?.avatarUrl || '',
          navigationTarget: {
            route: 'GROUP_DETAIL',
            groupId,
          },
        },
      });
    }

    return res.json({
      message: action === 'accept'
        ? 'Join request accepted.'
        : 'Join request rejected.',
      member,
    });
  }),
);

router.get(
  '/:groupId/posts',
  asyncHandler(async (req, res) => {
    const { groupId } = req.params;
    if (!isValidObjectId(groupId)) {
      return res.status(400).json({ message: 'Invalid groupId.' });
    }

    const group = await Group.findById(groupId);
    if (!group || group.status !== 'ACTIVE') {
      return res.status(404).json({ message: 'Group not found.' });
    }

    const membership = await GroupMember.findOne({
      groupId,
      userId: req.user.id,
      status: 'ACTIVE',
    });
    if (!membership) {
      return res
        .status(403)
        .json({ message: 'You must join the group to view its posts.' });
    }

    const limit = Math.max(1, Math.min(50, Number(req.query.limit) || 20));
    const beforeRaw = String(req.query.before || '').trim();
    const beforeDate = beforeRaw ? new Date(beforeRaw) : null;
    if (beforeRaw && Number.isNaN(beforeDate.getTime())) {
      return res.status(400).json({ message: 'Invalid before cursor.' });
    }

    const query = {
      groupId,
      status: 'PUBLISHED',
    };
    if (beforeDate) {
      query.createdAt = { $lt: beforeDate };
    }

    const posts = await Post.find(query)
      .sort({ createdAt: -1 })
      .limit(limit + 1);
    const childAuthorPosts = await filterNonChildAuthorPosts(posts, req.user);
    const hasMore = childAuthorPosts.length > limit;
    const page = hasMore ? childAuthorPosts.slice(0, limit) : childAuthorPosts;
    const nextBefore = hasMore
      ? page[page.length - 1].createdAt.toISOString()
      : null;

    return res.json({
      items: await withPostMeta(page, req.user.id),
      nextBefore,
      hasMore,
    });
  }),
);

router.post(
  '/:groupId/join',
  asyncHandler(async (req, res) => {
    const { groupId } = req.params;
    if (!isValidObjectId(groupId)) {
      return res.status(400).json({ message: 'Invalid groupId.' });
    }

    const group = await Group.findById(groupId);
    if (!group || group.status !== 'ACTIVE') {
      return res.status(404).json({ message: 'Group not found.' });
    }

    if (req.user.age < group.ageMin || req.user.age > group.ageMax) {
      return res.status(403).json({ message: 'Your age is outside this group range.' });
    }

    const session = await mongoose.startSession();
    let alreadyJoined = false;
    let alreadyPending = false;
    let shouldNotifyOwner = false;

    await session.withTransaction(async () => {
      const existing = await GroupMember.findOne({
        groupId,
        userId: req.user.id,
      }).session(session);

      if (existing && existing.status === 'ACTIVE') {
        alreadyJoined = true;
        return;
      }

      if (existing && existing.status === 'PENDING') {
        alreadyPending = true;
        return;
      }

      await GroupMember.findOneAndUpdate(
        { groupId, userId: req.user.id },
        {
          $set: {
            groupId,
            userId: req.user.id,
            status: 'PENDING',
            role: 'MEMBER',
          },
        },
        { upsert: true, new: true, runValidators: true, session },
      );
      shouldNotifyOwner = true;
    });

    session.endSession();

    if (alreadyJoined) {
      return res.json({ message: 'Already joined this group.' });
    }
    if (alreadyPending) {
      return res.json({ message: 'Join request is already pending.' });
    }

    if (shouldNotifyOwner) {
      const requester = await User.findById(req.user.id).select(
        'displayName username avatarUrl',
      );
      await sendNotification({
        userId: group.ownerId,
        actorId: req.user.id,
        type: NOTIFICATION_TYPES.GROUP_JOIN_REQUEST,
        payload: {
          groupId,
          groupName: group.name,
          fromUserId: req.user.id,
          fromUsername: requester?.username || req.user.username,
          ...(requester ? actorSnapshot(requester) : {}),
          navigationTarget: {
            route: 'GROUP_DETAIL',
            groupId,
          },
        },
      });
    }

    return res.status(202).json({ message: 'Join request sent.' });
  }),
);

router.post(
  '/:groupId/leave',
  asyncHandler(async (req, res) => {
    const { groupId } = req.params;
    if (!isValidObjectId(groupId)) {
      return res.status(400).json({ message: 'Invalid groupId.' });
    }

    const member = await GroupMember.findOne({
      groupId,
      userId: req.user.id,
      status: 'ACTIVE',
    });

    if (!member) {
      return res.status(404).json({ message: 'You are not an active member.' });
    }

    if (member.role === 'OWNER') {
      return res
        .status(400)
        .json({ message: 'Owner cannot leave. Transfer ownership first.' });
    }

    const session = await mongoose.startSession();
    await session.withTransaction(async () => {
      await GroupMember.updateOne(
        { _id: member._id },
        { $set: { status: 'LEFT' } },
        { session },
      );
      await Group.updateOne(
        { _id: groupId, memberCount: { $gt: 0 } },
        { $inc: { memberCount: -1 } },
        { session },
      );
    });
    session.endSession();

    await Chat.updateOne(
      { type: 'SOCIAL_GROUP', groupId },
      { $pull: { memberIds: req.user.id } },
    );

    const leaver = await User.findById(req.user.id).select(
      'displayName username avatarUrl',
    );
    await sendNotification({
      userId: group.ownerId,
      actorId: req.user.id,
      type: NOTIFICATION_TYPES.GROUP_MEMBER_LEFT,
      payload: {
        groupId,
        groupName: group.name,
        ...(leaver ? actorSnapshot(leaver) : {}),
        navigationTarget: {
          route: 'GROUP_DETAIL',
          groupId,
        },
      },
    });

    // Surface to admins so they can audit inactive groups.
    const adminDocs = await User.find({ role: 'ADMIN', isActive: true }).select(
      '_id',
    );
    if (adminDocs.length > 0) {
      await broadcastNotification({
        userIds: adminDocs.map((admin) => admin._id),
        actorId: req.user.id,
        type: NOTIFICATION_TYPES.ADMIN_MODERATION_ALERT,
        payload: {
          subjectType: 'GROUP',
          subjectId: groupId,
          groupId,
          groupName: group.name,
          reason: 'GROUP_MEMBER_LEFT',
          message: `${leaver?.displayName || 'Một thành viên'} vừa rời nhóm "${group.name}".`,
          navigationTarget: {
            route: 'ADMIN_GROUPS',
            groupId,
          },
        },
      });
    }

    return res.json({ message: 'Left group successfully.' });
  }),
);

module.exports = router;
