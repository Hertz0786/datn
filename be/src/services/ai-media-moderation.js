const env = require('../config/env');

function createHttpError(statusCode, message, payload) {
  const error = new Error(message);
  error.statusCode = statusCode;
  if (payload !== undefined) {
    error.payload = payload;
  }
  return error;
}

function normalizeBaseUrl(value) {
  return String(value || '').trim().replace(/\/+$/, '');
}

function buildModerationSnapshot(payload, skippedReason = '') {
  return {
    provider: 'kiddo-ai-server',
    decision: payload?.decision || (skippedReason ? 'SKIPPED' : 'UNKNOWN'),
    mediaType: payload?.mediaType || '',
    topLabel: payload?.topLabel || '',
    topScore: Number(payload?.topScore || 0),
    unsafeLabel: payload?.unsafeLabel || '',
    unsafeScore: Number(payload?.unsafeScore || 0),
    framesChecked: Number(payload?.framesChecked || 0),
    skippedReason,
    checkedAt: new Date(),
    details: payload || {},
  };
}

async function postMediaToAiServer(file) {
  const baseUrl = normalizeBaseUrl(env.aiModerationUrl);
  if (!baseUrl) {
    return buildModerationSnapshot(null, 'AI_MODERATION_URL is not configured.');
  }

  const controller = new AbortController();
  const timeout = setTimeout(
    () => controller.abort(),
    env.aiModerationTimeoutMs,
  );
  timeout.unref?.();

  try {
    const form = new FormData();
    const blob = new Blob([file.buffer], {
      type: file.mimetype || 'application/octet-stream',
    });
    form.append('file', blob, file.originalname || 'upload');

    const response = await fetch(`${baseUrl}/moderate`, {
      method: 'POST',
      body: form,
      signal: controller.signal,
    });

    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw createHttpError(
        response.status >= 500 ? 502 : response.status,
        payload.detail || payload.message || 'AI media moderation failed.',
        payload,
      );
    }

    return buildModerationSnapshot(payload);
  } catch (error) {
    if (error.name === 'AbortError') {
      throw createHttpError(504, 'AI media moderation timed out.');
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

async function assertMediaAllowed(file) {
  if (!env.aiModerationEnabled) {
    return buildModerationSnapshot(null, 'AI moderation is disabled.');
  }

  if (!normalizeBaseUrl(env.aiModerationUrl)) {
    if (env.aiModerationFailOpen) {
      return buildModerationSnapshot(
        null,
        'AI_MODERATION_URL is not configured but fail-open is enabled.',
      );
    }
    throw createHttpError(503, 'AI_MODERATION_URL is not configured.');
  }

  try {
    const moderation = await postMediaToAiServer(file);
    if (moderation.decision === 'SKIPPED') {
      return moderation;
    }

    return moderation;
  } catch (error) {
    if (error.payload?.code === 'MEDIA_BLOCKED') {
      throw error;
    }

    if (env.aiModerationFailOpen) {
      return buildModerationSnapshot(
        { error: error.message },
        'AI moderation failed but fail-open is enabled.',
      );
    }

    throw createHttpError(
      error.statusCode || 503,
      error.message || 'AI media moderation is unavailable.',
      error.payload,
    );
  }
}

module.exports = {
  assertMediaAllowed,
};
