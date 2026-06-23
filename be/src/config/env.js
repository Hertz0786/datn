const dotenv = require('dotenv');

dotenv.config();

const nodeEnv = process.env.NODE_ENV || 'development';
const isProduction = nodeEnv === 'production';

function parsePositiveInt(val, fallback) {
  const n = Number(val);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

if (isProduction && !process.env.JWT_SECRET) {
  throw new Error('Missing JWT_SECRET in production environment.');
}

const jwtSecret = process.env.JWT_SECRET || 'dev_jwt_secret_change_me';

if (isProduction && jwtSecret.length < 32) {
  throw new Error('JWT_SECRET must be at least 32 characters in production.');
}

const env = {
  nodeEnv,
  port: Number(process.env.PORT || 5000),
  mongoUri: process.env.MONGODB_URI || '',
  mongoPassword: process.env.MONGODB_PASSWORD || '',
  jwtSecret,
  clientOrigin: process.env.CLIENT_ORIGIN || '*',
  cloudinaryCloudName: process.env.CLOUDINARY_CLOUD_NAME || '',
  cloudinaryApiKey: process.env.CLOUDINARY_API_KEY || '',
  cloudinaryApiSecret: process.env.CLOUDINARY_API_SECRET || '',
  cloudinaryFolder: process.env.CLOUDINARY_FOLDER || 'kiddo-social',
  geminiApiKey: process.env.GEMINI_API_KEY || process.env.GEMINI_APIKEY || '',
  geminiModel: process.env.GEMINI_MODEL || 'gemini-2.5-flash',
  aiModerationUrl: process.env.AI_MODERATION_URL || '',
  aiModerationEnabled:
    process.env.AI_MODERATION_ENABLED === 'true' || !!process.env.AI_MODERATION_URL,
  aiModerationFailOpen: process.env.AI_MODERATION_FAIL_OPEN === 'true',
  aiModerationTimeoutMs: parsePositiveInt(process.env.AI_MODERATION_TIMEOUT_MS, 60000),
  agora: {
    appId: process.env.AGORA_APP_ID || '',
    appCertificate: process.env.AGORA_APP_CERTIFICATE || '',
    appCertificateSecondary: process.env.AGORA_APP_CERTIFICATE2nd || '',
    tokenExpireSeconds: parsePositiveInt(process.env.AGORA_TOKEN_EXPIRE_SECONDS, 3600),
  },
  // Threshold for auto-publishing a post with image attachments. The
  // AI moderation service returns an `unsafeScore` in [0, 1]; a score
  // at or above this value requires admin review before the post is
  // visible on the feed. Tunable per environment.
  mediaModerationThreshold: parsePositiveInt(
    process.env.MEDIA_MODERATION_THRESHOLD,
    0.65,
  ),
};

module.exports = env;
