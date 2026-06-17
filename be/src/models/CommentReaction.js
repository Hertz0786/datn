const mongoose = require('mongoose');

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
  },
  { timestamps: true },
);

commentReactionSchema.index({ commentId: 1, userId: 1 }, { unique: true });

module.exports = mongoose.model('CommentReaction', commentReactionSchema);
