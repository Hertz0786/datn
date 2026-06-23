const mongoose = require('mongoose');

const friendRequestSchema = new mongoose.Schema(
  {
    senderId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    receiverId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    status: {
      type: String,
      enum: ['PENDING', 'ACCEPTED', 'REJECTED', 'CANCELLED'],
      default: 'PENDING',
      index: true,
    },
  },
  { timestamps: true },
);

friendRequestSchema.pre('validate', function (next) {
  if (this.senderId.toString() === this.receiverId.toString()) {
    this.invalidate('receiverId', 'Cannot send a friend request to yourself.');
  }
  next();
});

friendRequestSchema.index({ senderId: 1, receiverId: 1 }, { unique: true });
friendRequestSchema.index(
  { senderId: 1, receiverId: 1, status: 1 },
  { unique: true, partialFilterExpression: { status: 'PENDING' } },
);

module.exports = mongoose.model('FriendRequest', friendRequestSchema);

