const mongoose = require('mongoose');

const friendshipSchema = new mongoose.Schema(
  {
    userAId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    userBId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
  },
  { timestamps: true },
);

friendshipSchema.index({ userAId: 1, userBId: 1 }, { unique: true });

module.exports = mongoose.model('Friendship', friendshipSchema);

