const mongoose = require('mongoose');

const callSettingsSchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      unique: true,
      index: true,
    },
    // Who is allowed to place a call to this user.
    whoCanCall: {
      type: String,
      enum: ['friends_only', 'everyone', 'nobody'],
      default: 'friends_only',
    },
    // Which call types the user can receive. Defaults to both voice and video.
    allowedCallTypes: {
      type: [String],
      enum: ['voice', 'video'],
      default: ['voice', 'video'],
    },
    // Maximum seconds a single call can last before being auto-ended.
    // 0 means no limit (caller/network are responsible for hangup).
    maxCallDurationSeconds: { type: Number, default: 0 },
    notificationsEnabled: { type: Boolean, default: true },
  },
  { timestamps: true },
);

module.exports = mongoose.model('CallSettings', callSettingsSchema);
