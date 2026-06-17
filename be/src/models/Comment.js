const mongoose = require('mongoose');

const commentSchema = new mongoose.Schema(
  {
    postId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Post',
      required: true,
      index: true,
    },
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
    parentCommentId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Comment',
      default: null,
      index: true,
    },
    content: {
      type: String,
      default: '',
      trim: true,
      maxlength: 1000,
    },
    mediaUrls: {
      type: [String],
      default: [],
    },
    likeCount: {
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
  },
  { timestamps: true },
);

commentSchema.index({ postId: 1, createdAt: -1 });

module.exports = mongoose.model('Comment', commentSchema);
