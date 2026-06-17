const mongoose = require('mongoose');

const mediaAssetSchema = new mongoose.Schema(
  {
    ownerId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    sourceType: {
      type: String,
      enum: ['PROFILE', 'PROFILE_COVER', 'POST', 'COMMENT', 'MESSAGE', 'GROUP', 'OTHER'],
      default: 'OTHER',
      index: true,
    },
    sourceId: {
      type: mongoose.Schema.Types.ObjectId,
      default: null,
      index: true,
    },
    publicId: {
      type: String,
      required: true,
      unique: true,
      index: true,
    },
    secureUrl: {
      type: String,
      required: true,
    },
    resourceType: {
      type: String,
      enum: ['image', 'video', 'raw'],
      default: 'image',
    },
    format: {
      type: String,
      default: '',
    },
    originalFilename: {
      type: String,
      default: '',
      maxlength: 255,
    },
    mimeType: {
      type: String,
      default: '',
      maxlength: 120,
    },
    bytes: {
      type: Number,
      default: 0,
      min: 0,
    },
    width: {
      type: Number,
      default: 0,
      min: 0,
    },
    height: {
      type: Number,
      default: 0,
      min: 0,
    },
    duration: {
      type: Number,
      default: 0,
      min: 0,
    },
    status: {
      type: String,
      enum: ['APPROVED', 'REVIEW', 'BLOCKED', 'REMOVED'],
      default: 'APPROVED',
      index: true,
    },
    moderation: {
      provider: { type: String, default: '' },
      decision: { type: String, default: '' },
      mediaType: { type: String, default: '' },
      topLabel: { type: String, default: '' },
      topScore: { type: Number, default: 0 },
      unsafeLabel: { type: String, default: '' },
      unsafeScore: { type: Number, default: 0 },
      framesChecked: { type: Number, default: 0 },
      skippedReason: { type: String, default: '' },
      checkedAt: { type: Date, default: null },
      details: { type: mongoose.Schema.Types.Mixed, default: {} },
    },
  },
  { timestamps: true },
);

mediaAssetSchema.index({ ownerId: 1, createdAt: -1 });
mediaAssetSchema.index({ sourceType: 1, sourceId: 1 });

module.exports = mongoose.model('MediaAsset', mediaAssetSchema);
