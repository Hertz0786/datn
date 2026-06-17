const mongoose = require('mongoose');

const chatSchema = new mongoose.Schema(
  {
    type: {
      type: String,
      enum: ['DIRECT', 'GROUP', 'SOCIAL_GROUP'],
      default: 'DIRECT',
    },
    title: {
      type: String,
      default: '',
      trim: true,
      maxlength: 80,
    },
    avatarUrl: {
      type: String,
      default: '',
      trim: true,
    },
    groupId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Group',
      default: null,
      index: true,
    },
    memberIds: {
      type: [mongoose.Schema.Types.ObjectId],
      ref: 'User',
      default: [],
      index: true,
    },
    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
  },
  { timestamps: true },
);

chatSchema.index({ memberIds: 1, createdAt: -1 });
chatSchema.index(
  { type: 1, groupId: 1 },
  {
    unique: true,
    partialFilterExpression: { type: 'SOCIAL_GROUP', groupId: { $exists: true } },
  },
);

module.exports = mongoose.model('Chat', chatSchema);
