const mongoose = require('mongoose');

const badgeSchema = new mongoose.Schema(
  {
    code: {
      type: String,
      required: true,
      unique: true,
      trim: true,
      maxlength: 60,
      index: true,
    },
    name: {
      type: String,
      required: true,
      trim: true,
      maxlength: 80,
    },
    description: {
      type: String,
      default: '',
      maxlength: 500,
    },
    iconUrl: {
      type: String,
      default: '',
    },
    color: {
      type: String,
      default: '#2563eb',
      maxlength: 20,
    },
    criteria: {
      type: {
        type: String,
        enum: ['POST_COUNT', 'REACTION_COUNT', 'COMMENT_COUNT', 'FRIEND_COUNT', 'GROUP_COUNT', 'CUSTOM'],
        default: 'CUSTOM',
      },
      threshold: { type: Number, default: 1, min: 1 },
    },
    isActive: {
      type: Boolean,
      default: true,
      index: true,
    },
  },
  { timestamps: true },
);

module.exports = mongoose.model('Badge', badgeSchema);
