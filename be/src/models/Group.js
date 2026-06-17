const mongoose = require('mongoose');

const groupSchema = new mongoose.Schema(
  {
    name: {
      type: String,
      required: true,
      trim: true,
      maxlength: 80,
    },
    topic: {
      type: String,
      required: true,
      trim: true,
      index: true,
    },
    description: {
      type: String,
      default: '',
      maxlength: 500,
    },
    avatarUrl: {
      type: String,
      default: '',
      trim: true,
    },
    ageMin: {
      type: Number,
      default: 7,
      min: 7,
      max: 14,
    },
    ageMax: {
      type: Number,
      default: 14,
      min: 7,
      max: 14,
    },
    ownerId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    memberCount: {
      type: Number,
      default: 1,
      min: 0,
    },
    status: {
      type: String,
      enum: ['ACTIVE', 'PAUSED', 'ARCHIVED'],
      default: 'ACTIVE',
      index: true,
    },
  },
  { timestamps: true },
);

groupSchema.index({ topic: 1, ageMin: 1, ageMax: 1, status: 1 });

module.exports = mongoose.model('Group', groupSchema);
