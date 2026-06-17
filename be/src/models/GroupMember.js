const mongoose = require('mongoose');

const groupMemberSchema = new mongoose.Schema(
  {
    groupId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Group',
      required: true,
      index: true,
    },
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    role: {
      type: String,
      enum: ['OWNER', 'MEMBER'],
      default: 'MEMBER',
    },
    status: {
      type: String,
      enum: ['ACTIVE', 'PENDING', 'LEFT'],
      default: 'ACTIVE',
      index: true,
    },
  },
  { timestamps: true },
);

groupMemberSchema.index({ groupId: 1, userId: 1 }, { unique: true });

module.exports = mongoose.model('GroupMember', groupMemberSchema);
