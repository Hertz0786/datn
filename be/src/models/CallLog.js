const mongoose = require('mongoose');

const callParticipantSchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    joinedAt: { type: Date, default: null },
    leftAt: { type: Date, default: null },
  },
  { _id: false },
);

const callLogSchema = new mongoose.Schema(
  {
    channelName: { type: String, required: true, index: true },
    callType: {
      type: String,
      enum: ['voice', 'video'],
      required: true,
    },
    status: {
      type: String,
      enum: [
        'ringing',
        'accepted',
        'rejected',
        'ended',
        'missed',
        'failed',
        'blocked',
      ],
      default: 'ringing',
      index: true,
    },
    initiator: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    callee: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    participants: { type: [callParticipantSchema], default: [] },
    startedAt: { type: Date, default: () => new Date() },
    acceptedAt: { type: Date, default: null },
    endedAt: { type: Date, default: null },
    durationSeconds: { type: Number, default: 0 },
    endReason: {
      type: String,
      enum: [
        'user_ended',
        'rejected',
        'missed_timeout',
        'caller_ended',
        'callee_ended',
        'error',
        'blocked',
        'parental_blocked',
        'max_duration',
      ],
      default: null,
    },
  },
  { timestamps: true },
);

// Hot lookup: recent calls for a given user (as initiator OR callee).
callLogSchema.index({ initiator: 1, createdAt: -1 });
callLogSchema.index({ callee: 1, createdAt: -1 });

module.exports = mongoose.model('CallLog', callLogSchema);
