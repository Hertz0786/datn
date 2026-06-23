const crypto = require('crypto');
const { RtcTokenBuilder, RtcRole } = require('agora-access-token');

const env = require('../config/env');

/**
 * Mints short-lived Agora RTC tokens for voice/video calls.
 *
 * Tokens are generated server-side so the App Certificate never leaves the
 * backend. The Flutter client only ever sees the App ID (public) and the
 * per-call token (expires in `AGORA_TOKEN_EXPIRE_SECONDS`).
 *
 * Agora projects can have a primary and a secondary App Certificate. We try
 * the primary first and fall back to the secondary if the SDK throws - that
 * way we can rotate certificates without a backend restart.
 */
class AgoraTokenService {
  isConfigured() {
    return Boolean(env.agora.appId) && Boolean(env.agora.appCertificate);
  }

  /**
   * Convert a Mongo ObjectId (24 hex chars) to a signed 32-bit integer that
   * Agora can use as a numeric UID. We keep the result in the positive
   * int32 range to avoid compatibility issues with the SDK.
   */
  static userIdToUid(userId) {
    const source = userId.toString();
    const hash = crypto.createHash('md5').update(source).digest('hex');
    // Take the first 8 hex chars (32 bits) and force the sign bit to 0.
    const raw = parseInt(hash.substring(0, 8), 16);
    return raw & 0x7fffffff;
  }

  /**
   * Build a token for the given channel and numeric UID.
   * @param {string} channelName
   * @param {number} uid numeric Agora UID
   * @param {'publisher'|'subscriber'} role
   */
  generateToken(channelName, uid, role = 'publisher') {
    if (!this.isConfigured()) {
      throw new Error(
        'Agora is not configured. Set AGORA_APP_ID and AGORA_APP_CERTIFICATE.',
      );
    }

    const rtcRole =
      role === 'subscriber' ? RtcRole.SUBSCRIBER : RtcRole.PUBLISHER;
    const expire = Math.floor(env.agora.tokenExpireSeconds);
    const nowSeconds = Math.floor(Date.now() / 1000);
    const privilegeExpiredTs = nowSeconds + expire;

    const candidates = [env.agora.appCertificate];
    if (env.agora.appCertificateSecondary) {
      candidates.push(env.agora.appCertificateSecondary);
    }

    let lastError;
    for (const certificate of candidates) {
      try {
        return RtcTokenBuilder.buildTokenWithUid(
          env.agora.appId,
          certificate,
          channelName,
          uid,
          rtcRole,
          privilegeExpiredTs,
        );
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError || new Error('Failed to build Agora token.');
  }
}

module.exports = new AgoraTokenService();
