const mongoose = require('mongoose');

const emailVerificationTokenSchema = new mongoose.Schema(
  {
    email: {
      type: String,
      required: true,
      lowercase: true,
      trim: true,
      maxlength: 254,
    },
    codeHash: {
      type: String,
      required: true,
    },
    type: {
      type: String,
      enum: ['REGISTER', 'RESET'],
      required: true,
    },
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    expiresAt: {
      type: Date,
      required: true,
      // TTL index is added separately below (expireAfterSeconds: 0)
      // so we do NOT use `index: true` here to avoid a duplicate plain index.
    },
    usedAt: {
      type: Date,
      default: null,
    },
  },
  { timestamps: true },
);

emailVerificationTokenSchema.index(
  { expiresAt: 1 },
  { expireAfterSeconds: 0 },
);
emailVerificationTokenSchema.index({ email: 1, type: 1 });

module.exports = mongoose.model('EmailVerificationToken', emailVerificationTokenSchema);
