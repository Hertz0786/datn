const mongoose = require('mongoose');
const { ALLOWED_REACTIONS } = require('./PostReaction');

const commentReactionSchema = new mongoose.Schema(
  {
    commentId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Comment',
      required: true,
      index: true,
    },
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    reaction: {
      type: String,
      enum: ALLOWED_REACTIONS,
      default: 'heart',
      required: true,
    },
  },
  { timestamps: true },
);

commentReactionSchema.index({ commentId: 1, userId: 1 }, { unique: true });

module.exports = mongoose.model('CommentReaction', commentReactionSchema);
