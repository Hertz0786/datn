const mongoose = require('mongoose');

const postSchema = new mongoose.Schema(
  {
    authorId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    authorSnapshot: {
      displayName: { type: String, required: true },
      username: { type: String, required: true },
      avatarUrl: { type: String, default: '' },
    },
    content: {
      type: String,
      required: true,
      trim: true,
      maxlength: 2000,
    },
    topics: {
      type: [String],
      default: [],
      index: true,
    },
    mood: {
      type: String,
      default: '',
      maxlength: 40,
    },
    mediaUrls: {
      type: [String],
      default: [],
    },
    audience: {
      type: String,
      enum: ['PUBLIC', 'FRIENDS', 'GROUP'],
      default: 'FRIENDS',
    },
    allowComments: {
      type: Boolean,
      default: true,
    },
    allowReactions: {
      type: Boolean,
      default: true,
    },
    groupId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Group',
      default: null,
      index: true,
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
    reactionCount: {
      type: Number,
      default: 0,
      min: 0,
    },
    commentCount: {
      type: Number,
      default: 0,
      min: 0,
    },
    status: {
      type: String,
      enum: ['PUBLISHED', 'HIDDEN', 'DELETED'],
      default: 'PUBLISHED',
      index: true,
    },
    // When a post is created with image attachments whose AI
    // moderation score crossed the configured threshold, we hold the
    // post back as HIDDEN and surface it on the admin "Posts &
    // comments" tab. `pendingMediaReview = true` tells the admin
    // Posts page (and the user's own post list) that this post is
    // waiting for human review — not just a normal auto-hide.
    pendingMediaReview: {
      type: Boolean,
      default: false,
      index: true,
    },
    // Highest score of any attached image at create time. Stored
    // so the admin can sort the review queue without re-fetching
    // every MediaAsset row.
    mediaModerationScore: {
      type: Number,
      default: 0,
      min: 0,
      max: 1,
    },
    mediaModerationLabel: {
      type: String,
      default: '',
      maxlength: 120,
    },
    // Set when an admin publishes the post after review (or
    // deletes it). Surfaced to the client via the realtime event
    // and on subsequent fetches.
    moderationDecisionAt: {
      type: Date,
      default: null,
    },
    moderationDecisionBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    moderationDecisionNote: {
      type: String,
      default: '',
      maxlength: 240,
    },
  },
  { timestamps: true },
);

postSchema.pre('validate', function (next) {
  if (this.ageMin > this.ageMax) {
    this.invalidate('ageMin', 'ageMin cannot be greater than ageMax.');
  }
  next();
});

postSchema.index({ topics: 1, ageMin: 1, ageMax: 1, status: 1 });
postSchema.index({ authorId: 1, createdAt: -1 });
postSchema.index({ groupId: 1, createdAt: -1 });

module.exports = mongoose.model('Post', postSchema);
