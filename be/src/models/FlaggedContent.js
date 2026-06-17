const mongoose = require('mongoose');

const flaggedContentSchema = new mongoose.Schema(
  {
    sourceType: {
      type: String,
      enum: ['POST', 'COMMENT', 'MESSAGE', 'MEDIA', 'USER'],
      required: true,
      index: true,
    },
    sourceId: {
      type: String,
      required: true,
      index: true,
    },
    flaggedBy: {
      type: String,
      enum: ['NSFWJS', 'KEYWORD_FILTER', 'CNN_SERVICE', 'USER_REPORT', 'ADMIN'],
      required: true,
      index: true,
    },
    categories: {
      type: [String],
      default: [],
    },
    score: {
      type: Number,
      default: 0,
      min: 0,
      max: 1,
    },
    details: {
      type: mongoose.Schema.Types.Mixed,
      default: {},
    },
    status: {
      type: String,
      enum: ['PENDING', 'CONFIRMED', 'DISMISSED', 'ACTIONED'],
      default: 'PENDING',
      index: true,
    },
    handledBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    handledAt: {
      type: Date,
      default: null,
    },
  },
  { timestamps: true },
);

flaggedContentSchema.index({ sourceType: 1, sourceId: 1 });
flaggedContentSchema.index({ status: 1, createdAt: -1 });

module.exports = mongoose.model('FlaggedContent', flaggedContentSchema);
