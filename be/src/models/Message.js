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
      enum: ['TEXT', 'POST_SHARE'],
      default: 'TEXT',
    },
    postId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Post',
      default: null,
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
