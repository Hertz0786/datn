const mongoose = require('mongoose');

const messageSchema = new mongoose.Schema(
  {
    chatId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Chat',
      required: true,
      index: true,
    },
    senderId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    content: {
      type: String,
      default: '',
      trim: true,
      maxlength: 2000,
    },
    mediaUrls: {
      type: [String],
      default: [],
    },
    type: {
      type: String,
      enum: ['TEXT', 'POST_SHARE', 'CALL'],
      default: 'TEXT',
    },
    postId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Post',
      default: null,
    },
    // Metadata for `type: 'CALL'` messages. Stores the call summary so the
    // chat UI can render a "missed call at 22:41" / "video call · 12s" banner
    // without having to join against CallLog at read time.
    callMeta: {
      callId: { type: String, default: '' },
      callType: {
        type: String,
        enum: ['voice', 'video', null],
        default: null,
      },
      // 'missed' | 'ended' | 'rejected' | 'cancelled'
      status: { type: String, default: '' },
      durationSeconds: { type: Number, default: 0 },
      // Who placed the call (initiator). Useful for labeling the banner.
      initiatorId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        default: null,
      },
    },
    status: {
      type: String,
      enum: ['SENT', 'DELETED'],
      default: 'SENT',
      index: true,
    },
    readBy: {
      type: [
        {
          userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
          readAt: { type: Date, default: Date.now },
        },
      ],
      default: [],
    },
  },
  { timestamps: true },
);

messageSchema.index({ chatId: 1, createdAt: -1 });
messageSchema.index({ 'readBy.userId': 1 });

module.exports = mongoose.model('Message', messageSchema);
