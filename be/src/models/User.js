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
    birthDate: {
      type: Date,
      required: true,
    },
    age: {
      type: Number,
      required: true,
      min: 7,
      max: 14,
    },
    passwordHash: {
      type: String,
      default: null,
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
    email: {
      type: String,
      default: null,
      lowercase: true,
      trim: true,
      maxlength: 254,
      sparse: true,
    },
    emailVerified: {
      type: Boolean,
      default: false,
    },
    googleId: {
      type: String,
      default: null,
      sparse: true,
    },
    loginProvider: {
      type: String,
      enum: ['LOCAL', 'GOOGLE'],
      default: 'LOCAL',
    },
  },
  { timestamps: true },
);

userSchema.index({ age: 1, role: 1 });

module.exports = mongoose.model('User', userSchema);
