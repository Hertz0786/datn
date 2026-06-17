const mongoose = require('mongoose');

const supportMessageSchema = new mongoose.Schema(
  {
    threadId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'SupportThread',
      required: true,
      index: true,
    },
    senderId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    senderRole: {
      type: String,
      enum: ['USER', 'ADMIN'],
      required: true,
      index: true,
    },
    content: {
      type: String,
      required: true,
      trim: true,
      maxlength: 2000,
    },
  },
  { timestamps: true },
);

supportMessageSchema.index({ threadId: 1, createdAt: 1 });

module.exports = mongoose.model('SupportMessage', supportMessageSchema);
