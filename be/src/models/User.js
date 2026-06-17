const mongoose = require('mongoose');

const userSchema = new mongoose.Schema(
  {
    displayName: {
      type: String,
      required: true,
      trim: true,
      maxlength: 40,
    },
    username: {
      type: String,
      required: true,
      unique: true,
      lowercase: true,
      trim: true,
      minlength: 3,
      maxlength: 24,
      match: /^[a-z0-9_]+$/,
    },
    age: {
      type: Number,
      required: true,
      min: 7,
      max: 14,
    },
    passwordHash: {
      type: String,
      required: true,
    },
    role: {
      type: String,
      enum: ['CHILD', 'MODERATOR', 'ADMIN'],
      default: 'CHILD',
    },
    moderationStatus: {
      type: String,
      enum: ['ACTIVE', 'WATCHLIST', 'SUSPENDED'],
      default: 'ACTIVE',
      index: true,
    },
    avatarUrl: {
      type: String,
      default: '',
    },
    coverUrl: {
      type: String,
      default: '',
    },
    bio: {
      type: String,
      default: '',
      maxlength: 160,
    },
    favoriteTopics: {
      type: [String],
      default: [],
    },
    privacy: {
      allowFriendRequests: { type: Boolean, default: true },
      allowComments: { type: Boolean, default: true },
      safeSearchOnly: { type: Boolean, default: true },
    },
    isActive: {
      type: Boolean,
      default: true,
    },
    lastActiveAt: {
      type: Date,
      default: null,
      index: true,
    },
  },
  { timestamps: true },
);

userSchema.index({ age: 1, role: 1 });

module.exports = mongoose.model('User', userSchema);
