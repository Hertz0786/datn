const env = require('../config/env');

const GEMINI_BASE_URL = 'https://generativelanguage.googleapis.com/v1beta/models';

const SYSTEM_INSTRUCTIONS = [
  'You are AI Helper for a children-focused social network.',
  'Always answer in Vietnamese unless the user asks for another language.',
  'Keep answers short, friendly, safe, and age-appropriate for children from 7 to 14.',
  'Help with creative post ideas, polite comments, online safety, app usage, school-friendly explanations, and emotional support.',
  'Do not ask children for private information such as address, phone number, school name, password, exact location, or secret personal details.',
  'If the user may be in danger, bullied, threatened, or self-harming, tell them to contact a trusted adult immediately and use the app report/safety feature.',
  'Do not generate bullying, sexual, violent, hateful, or privacy-invasive content.',
].join(' ');

function createHttpError(statusCode, message, payload) {
  const error = new Error(message);
  error.statusCode = statusCode;
  if (payload !== undefined) {
    error.payload = payload;
  }
  return error;
}

function sanitizeMessage(value) {
  return String(value || '').trim().slice(0, 1200);
}

function normalizeHistory(messages) {
  if (!Array.isArray(messages)) {
    return [];
  }

  return messages
    .slice(-10)
    .map((item) => ({
      role: item?.role === 'assistant' ? 'assistant' : 'user',
      content: sanitizeMessage(item?.content),
    }))
    .filter((item) => item.content);
}

function buildContents(message, history) {
  const contents = normalizeHistory(history).map((item) => ({
    role: item.role === 'assistant' ? 'model' : 'user',
    parts: [{ text: item.content }],
  }));

  contents.push({
    role: 'user',
    parts: [{ text: message }],
  });

  return contents;
}

function extractResponseText(payload) {
  const parts = [];
  for (const candidate of payload.candidates || []) {
    for (const part of candidate.content?.parts || []) {
      if (part.text) {
        parts.push(part.text);
      }
    }
  }
  return parts.join('\n').trim();
}

async function postJsonWithTimeout(url, { headers, body, timeoutMs = 25000 }) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...headers,
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    const payload = await response.json().catch(() => ({}));
    return { response, payload };
  } catch (error) {
    if (error.name === 'AbortError') {
      throw createHttpError(504, 'LLM provider request timed out.');
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

async function callAssistant({ message, history }) {
  if (!env.geminiApiKey) {
    throw createHttpError(503, 'Gemini is not configured.', {
      provider: 'gemini',
      code: 'missing_api_key',
    });
  }

  const model = env.geminiModel;
  const url = `${GEMINI_BASE_URL}/${encodeURIComponent(model)}:generateContent`;
  const { response, payload } = await postJsonWithTimeout(url, {
    headers: { 'x-goog-api-key': env.geminiApiKey },
    body: {
      systemInstruction: {
        parts: [{ text: SYSTEM_INSTRUCTIONS }],
      },
      contents: buildContents(message, history),
      generationConfig: {
        temperature: 0.6,
        maxOutputTokens: 450,
      },
      safetySettings: [
        { category: 'HARM_CATEGORY_HARASSMENT', threshold: 'BLOCK_MEDIUM_AND_ABOVE' },
        { category: 'HARM_CATEGORY_HATE_SPEECH', threshold: 'BLOCK_MEDIUM_AND_ABOVE' },
        { category: 'HARM_CATEGORY_SEXUALLY_EXPLICIT', threshold: 'BLOCK_MEDIUM_AND_ABOVE' },
        { category: 'HARM_CATEGORY_DANGEROUS_CONTENT', threshold: 'BLOCK_MEDIUM_AND_ABOVE' },
      ],
    },
  });

  if (!response.ok) {
    throw createHttpError(
      response.status >= 500 ? 502 : response.status,
      payload.error?.message || 'Gemini request failed.',
      { provider: 'gemini', code: payload.error?.status || payload.error?.code || '' },
    );
  }

  const reply = extractResponseText(payload);
  if (!reply) {
    throw createHttpError(502, 'Gemini returned an empty response.', {
      provider: 'gemini',
      code: 'empty_response',
    });
  }

  return {
    provider: 'gemini',
    model,
    reply,
  };
}

module.exports = {
  callAssistant,
};
