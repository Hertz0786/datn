const mongoose = require('mongoose');

const ALLOWED_REACTIONS = ['heart', 'star', 'laugh', 'wow', 'clap'];

const postReactionSchema = new mongoose.Schema(
  {
    postId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Post',
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

postReactionSchema.index({ postId: 1, userId: 1 }, { unique: true });

module.exports = mongoose.model('PostReaction', postReactionSchema);
module.exports.ALLOWED_REACTIONS = ALLOWED_REACTIONS;
