const Chat = require('../models/Chat');
const Comment = require('../models/Comment');
const Group = require('../models/Group');
const Message = require('../models/Message');
const Post = require('../models/Post');
const User = require('../models/User');
const { emitGlobal, emitToChat, emitToPost, emitToUser } = require('../realtime/socket');

async function attachMediaToSource(asset) {
  const sourceId = asset.sourceId?.toString();
  const mediaUrl = asset.secureUrl;

  if (asset.sourceType === 'PROFILE') {
    await User.findByIdAndUpdate(asset.ownerId, { $set: { avatarUrl: mediaUrl } });
    emitToUser(asset.ownerId.toString(), 'profile:updated', { avatarUrl: mediaUrl });
    return;
  }

  if (asset.sourceType === 'PROFILE_COVER') {
    await User.findByIdAndUpdate(asset.ownerId, { $set: { coverUrl: mediaUrl } });
    emitToUser(asset.ownerId.toString(), 'profile:updated', { coverUrl: mediaUrl });
    return;
  }

  if (asset.sourceType === 'POST' && sourceId) {
    await Post.findByIdAndUpdate(sourceId, { $addToSet: { mediaUrls: mediaUrl } });
    emitToPost(sourceId, 'post:media_added', { postId: sourceId, mediaUrl });
    emitGlobal('feed:changed', { reason: 'post_media_added', postId: sourceId });
    return;
  }

  if (asset.sourceType === 'COMMENT' && sourceId) {
    const comment = await Comment.findByIdAndUpdate(
      sourceId,
      { $addToSet: { mediaUrls: mediaUrl } },
      { new: true },
    );
    if (comment) {
      emitToPost(comment.postId.toString(), 'comment:updated', {
        postId: comment.postId.toString(),
        comment,
      });
    }
    return;
  }

  if (asset.sourceType === 'MESSAGE' && sourceId) {
    const message = await Message.findByIdAndUpdate(
      sourceId,
      { $addToSet: { mediaUrls: mediaUrl } },
      { new: true },
    );
    if (message) {
      const chat = await Chat.findById(message.chatId);
      emitToChat(
        message.chatId.toString(),
        chat?.memberIds.map((memberId) => memberId.toString()) || [],
        'chat:message_updated',
        { chatId: message.chatId.toString(), message },
      );
    }
    return;
  }

  if (asset.sourceType === 'GROUP' && sourceId) {
    await Group.findByIdAndUpdate(sourceId, { $set: { avatarUrl: mediaUrl } });
    await Chat.updateOne(
      { type: 'SOCIAL_GROUP', groupId: sourceId },
      { $set: { avatarUrl: mediaUrl } },
    );
  }
}

async function detachMediaFromSource(asset) {
  const sourceId = asset.sourceId?.toString();
  const mediaUrl = asset.secureUrl;

  if (asset.sourceType === 'PROFILE') {
    await User.updateOne(
      { _id: asset.ownerId, avatarUrl: mediaUrl },
      { $set: { avatarUrl: '' } },
    );
    emitToUser(asset.ownerId.toString(), 'profile:updated', { avatarUrl: '' });
    return;
  }

  if (asset.sourceType === 'PROFILE_COVER') {
    await User.updateOne(
      { _id: asset.ownerId, coverUrl: mediaUrl },
      { $set: { coverUrl: '' } },
    );
    emitToUser(asset.ownerId.toString(), 'profile:updated', { coverUrl: '' });
    return;
  }

  if (asset.sourceType === 'POST' && sourceId) {
    await Post.findByIdAndUpdate(sourceId, { $pull: { mediaUrls: mediaUrl } });
    emitToPost(sourceId, 'post:media_removed', { postId: sourceId, mediaUrl });
    emitGlobal('feed:changed', { reason: 'post_media_removed', postId: sourceId });
    return;
  }

  if (asset.sourceType === 'COMMENT' && sourceId) {
    const comment = await Comment.findByIdAndUpdate(
      sourceId,
      { $pull: { mediaUrls: mediaUrl } },
      { new: true },
    );
    if (comment) {
      emitToPost(comment.postId.toString(), 'comment:updated', {
        postId: comment.postId.toString(),
        comment,
      });
    }
    return;
  }

  if (asset.sourceType === 'MESSAGE' && sourceId) {
    const message = await Message.findByIdAndUpdate(
      sourceId,
      { $pull: { mediaUrls: mediaUrl } },
      { new: true },
    );
    if (message) {
      const chat = await Chat.findById(message.chatId);
      emitToChat(
        message.chatId.toString(),
        chat?.memberIds.map((memberId) => memberId.toString()) || [],
        'chat:message_updated',
        { chatId: message.chatId.toString(), message },
      );
    }
    return;
  }

  if (asset.sourceType === 'GROUP' && sourceId) {
    await Group.updateOne(
      { _id: sourceId, avatarUrl: mediaUrl },
      { $set: { avatarUrl: '' } },
    );
    await Chat.updateOne(
      { type: 'SOCIAL_GROUP', groupId: sourceId, avatarUrl: mediaUrl },
      { $set: { avatarUrl: '' } },
    );
  }
}

module.exports = {
  attachMediaToSource,
  detachMediaFromSource,
};
