const mongoose = require('mongoose');

const photoSchema = new mongoose.Schema(
  {
    ownerId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    mediaAssetId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'MediaAsset',
      default: null,
      index: true,
    },
    caption: {
      type: String,
      default: '',
      maxlength: 200,
    },
    album: {
      type: String,
      default: 'default',
      maxlength: 60,
      index: true,
    },
    visibility: {
      type: String,
      enum: ['PUBLIC', 'FRIENDS', 'PRIVATE'],
      default: 'FRIENDS',
    },
    status: {
      type: String,
      enum: ['PUBLISHED', 'HIDDEN', 'DELETED'],
      default: 'PUBLISHED',
      index: true,
    },
  },
  { timestamps: true },
);

photoSchema.index({ ownerId: 1, createdAt: -1 });

module.exports = mongoose.model('Photo', photoSchema);
