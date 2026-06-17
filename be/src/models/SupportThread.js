const mongoose = require('mongoose');

const supportThreadSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    assignedAdminId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
      index: true,
    },
    subject: {
      type: String,
      default: 'Support request',
      trim: true,
      maxlength: 120,
    },
    category: {
      type: String,
      enum: ['GENERAL', 'SAFETY', 'ACCOUNT', 'TECHNICAL', 'REPORT'],
      default: 'GENERAL',
      index: true,
    },
    status: {
      type: String,
      enum: ['OPEN', 'PENDING_USER', 'RESOLVED'],
      default: 'OPEN',
      index: true,
    },
    lastMessageAt: {
      type: Date,
      default: Date.now,
      index: true,
    },
  },
  { timestamps: true },
);

supportThreadSchema.index({ userId: 1, status: 1, lastMessageAt: -1 });

module.exports = mongoose.model('SupportThread', supportThreadSchema);
