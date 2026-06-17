const mongoose = require('mongoose');

const reportSchema = new mongoose.Schema(
  {
    // Where the report came from. USER = a real person flagged
    // something; AUTO_MODERATION = the content moderation pipeline
    // blocked the content before it was saved and asked admins to
    // review. The two are surfaced differently in the admin UI.
    source: {
      type: String,
      enum: ['USER', 'AUTO_MODERATION'],
      default: 'USER',
      index: true,
    },
    reporterId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    // The user who *wrote* the offending content. For USER reports
    // this is the same as `reporterId` most of the time, but admins
    // sometimes report on behalf of a victim, so we keep it separate.
    // For AUTO_MODERATION this is the only meaningful "who" since the
    // reporter is effectively the system.
    targetAuthorId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
      index: true,
    },
    targetType: {
      type: String,
      enum: ['USER', 'POST', 'COMMENT', 'GROUP', 'MESSAGE'],
      required: true,
      index: true,
    },
    targetId: {
      type: String,
      required: true,
      index: true,
    },
    // Snapshot of the offending content. For AUTO_MODERATION this
    // is essential because the original post / message was never
    // persisted — the moderation pipeline stores the snippet here so
    // admins can still see what the user tried to send.
    targetContent: {
      type: String,
      default: '',
      maxlength: 2000,
    },
    category: {
      type: String,
      enum: ['BULLYING', 'UNSAFE_CONTENT', 'PRIVATE_INFO', 'SPAM', 'OTHER'],
      required: true,
      index: true,
    },
    details: {
      type: String,
      default: '',
      maxlength: 2000,
    },
    urgency: {
      type: Number,
      default: 2,
      min: 1,
      max: 5,
      index: true,
    },
    status: {
      type: String,
      enum: ['PENDING', 'REVIEWING', 'RESOLVED', 'DISMISSED'],
      default: 'PENDING',
      index: true,
    },
  },
  { timestamps: true },
);

reportSchema.index({ status: 1, urgency: -1, createdAt: -1 });
reportSchema.index({ source: 1, status: 1, urgency: -1, createdAt: -1 });

module.exports = mongoose.model('Report', reportSchema);

