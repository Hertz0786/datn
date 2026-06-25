const Chat = require('../models/Chat');
const Message = require('../models/Message');
const { serializeMessage } = require('../utils/chat-summary');
const { emitToChat, emitToUser } = require('../realtime/socket');

/**
 * Ensure a DIRECT chat exists between two users and return its id.
 * Used by the call flow to record a call-summary message in the same
 * conversation where the participants are already chatting.
 */
async function ensureDirectChat(userIdA, userIdB) {
  if (!userIdA || !userIdB || userIdA === userIdB) {
    return null;
  }
  const memberIds = [userIdA, userIdB].sort();
  let chat = await Chat.findOne({ type: 'DIRECT', memberIds });
  if (!chat) {
    chat = await Chat.create({
      type: 'DIRECT',
      memberIds,
      createdBy: userIdA,
    });
  }
  return chat;
}

/**
 * Persist a "call summary" message in the DIRECT chat between the two
 * participants. Emits a `chat:message` event to both users so the
 * conversation updates in realtime on every device.
 *
 * @param {object} call  CallLog mongoose document
 * @param {string} endedByUserId  id of the user who triggered the end
 * @returns {Promise<object|null>} the serialized message or null when
 *   the call is not a 1-1 conversation (we don't summarise group calls
 *   for now because the chat banner model assumes a single peer).
 */
async function recordCallSummaryMessage(call, endedByUserId) {
  if (!call) return null;
  const initiatorId = call.initiator?.toString?.() || '';
  const calleeId = call.callee?.toString?.() || '';
  if (!initiatorId || !calleeId) return null;

  const chat = await ensureDirectChat(initiatorId, calleeId);
  if (!chat) return null;

  const status = (() => {
    if (call.status === 'missed') return 'missed';
    if (call.status === 'rejected') return 'rejected';
    if (call.status === 'cancelled' || call.endReason === 'caller_ended' && !call.acceptedAt) {
      return 'cancelled';
    }
    return 'ended';
  })();

  const message = await Message.create({
    chatId: chat._id,
    senderId: initiatorId,
    content: '',
    mediaUrls: [],
    type: 'CALL',
    status: 'SENT',
    callMeta: {
      callId: call._id.toString(),
      callType: call.callType,
      status,
      durationSeconds: call.durationSeconds || 0,
      initiatorId,
    },
  });

  await Chat.updateOne({ _id: chat._id }, { $set: { updatedAt: new Date() } });

  const data = serializeMessage(message);
  const memberIds = [initiatorId, calleeId];
  emitToChat(chat._id.toString(), memberIds, 'chat:message', {
    chatId: chat._id.toString(),
    message: data,
  });
  return data;
}

module.exports = {
  ensureDirectChat,
  recordCallSummaryMessage,
};
