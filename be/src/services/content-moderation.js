const AuditLog = require('../models/AuditLog');
const Report = require('../models/Report');
const User = require('../models/User');
const { emitToUser } = require('../realtime/socket');
const {
  broadcastNotification,
  NOTIFICATION_TYPES,
} = require('./notification-service');

const sensitiveWords = require('../../../moderation/sensitiveWords');

const CATEGORY_TO_REPORT = {
  vulgar: 'UNSAFE_CONTENT',
  privacy: 'PRIVATE_INFO',
  racist: 'BULLYING',
  sexist: 'BULLYING',
  suicide: 'UNSAFE_CONTENT',
};

const CATEGORY_LABEL = {
  vulgar: 'Profanity or adult content',
  privacy: 'Private information request',
  racist: 'Hate or discriminatory language',
  sexist: 'Harassment or sexual content',
  suicide: 'Self-harm or suicide content',
};

const MODERATED_CATEGORIES = ['vulgar', 'privacy', 'racist', 'sexist', 'suicide'];

function normalizeText(value) {
  return String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[\u0111\u0110]/g, 'd')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}`~]+/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function buildModerationTerms() {
  const terms = [];
  for (const category of MODERATED_CATEGORIES) {
    const words = Array.isArray(sensitiveWords[category])
      ? sensitiveWords[category]
      : [];

    for (const word of words) {
      const normalized = normalizeText(word);
      if (!normalized) {
        continue;
      }

      terms.push({
        category,
        label: CATEGORY_LABEL[category],
        word: String(word),
        normalized,
        compact: normalized.replace(/\s+/g, ''),
      });
    }
  }

  const seen = new Set();
  return terms.filter((term) => {
    const key = `${term.category}:${term.normalized}`;
    if (seen.has(key)) {
      return false;
    }
    seen.add(key);
    return true;
  });
}

const TERMS = buildModerationTerms();

function termMatches(normalizedText, normalizedTokens, compactText, term) {
  if (term.normalized.length <= 2) {
    return normalizedTokens.has(term.normalized);
  }

  if (term.normalized.includes(' ')) {
    return (
      normalizedText.includes(term.normalized) ||
      (term.compact.length >= 4 && compactText.includes(term.compact))
    );
  }

  const boundaryPattern = new RegExp(
    `(^|\\s)${escapeRegExp(term.normalized)}($|\\s)`,
    'u',
  );
  return boundaryPattern.test(normalizedText);
}

function scanText(text) {
  const normalized = normalizeText(text);
  if (!normalized) {
    return {
      blocked: false,
      categories: [],
      matches: [],
    };
  }

  const normalizedTokens = new Set(normalized.split(/\s+/).filter(Boolean));
  const compactText = normalized.replace(/\s+/g, '');
  const matches = [];

  for (const term of TERMS) {
    if (termMatches(normalized, normalizedTokens, compactText, term)) {
      matches.push({
        category: term.category,
        label: term.label,
        word: term.normalized,
      });
    }
  }

  const uniqueMatches = [];
  const seen = new Set();
  for (const match of matches) {
    const key = `${match.category}:${match.word}`;
    if (!seen.has(key)) {
      uniqueMatches.push(match);
      seen.add(key);
    }
  }

  return {
    blocked: uniqueMatches.length > 0,
    categories: [...new Set(uniqueMatches.map((match) => match.category))],
    matches: uniqueMatches.slice(0, 20),
  };
}

function createModerationError(result) {
  const error = new Error(
    'This content contains blocked language and cannot be sent. The admin team has been notified.',
  );
  error.statusCode = 400;
  error.payload = {
    code: 'CONTENT_BLOCKED',
    categories: result.categories,
  };
  return error;
}

function inferReportCategory(result) {
  const firstCategory = result.categories[0] || 'vulgar';
  return CATEGORY_TO_REPORT[firstCategory] || 'UNSAFE_CONTENT';
}

async function notifyAdminsAboutBlockedContent({
  userId,
  targetType,
  targetId,
  action,
  content,
  result,
}) {
  const [actor, admins] = await Promise.all([
    User.findById(userId),
    User.find({ role: { $in: ['ADMIN', 'MODERATOR'] }, isActive: true }),
  ]);

  const actorSnapshot = actor
    ? {
        id: actor._id.toString(),
        username: actor.username,
        displayName: actor.displayName,
        role: actor.role,
      }
    : { id: userId };

  const report = await Report.create({
    // Mark this as a system-generated report. The dashboard surfaces
    // it under "auto-flagged" with a different colour and a clearer
    // label so admins do not get confused into thinking the author
    // reported themselves.
    source: 'AUTO_MODERATION',
    reporterId: userId,
    targetAuthorId: userId,
    targetType,
    targetId,
    // Persist the offending snippet on the Report itself. The original
    // post / message was blocked before save, so without this field
    // admins have no way to see what the user tried to send.
    targetContent: String(content).slice(0, 1000),
    category: inferReportCategory(result),
    details: `Blocked ${action}. Matched: ${result.matches
      .map((match) => `${match.label}: ${match.word}`)
      .join(', ')}. Content preview: ${String(content).slice(0, 240)}`,
    urgency: result.categories.includes('suicide') || result.categories.includes('privacy')
      ? 5
      : 4,
    status: 'PENDING',
  });

  await AuditLog.create({
    actorId: userId,
    actorUsername: actor?.username || '',
    action: `Blocked ${action} by moderation`,
    targetType,
    targetId,
    metadata: {
      actor: actorSnapshot,
      matches: result.matches,
      reportId: report._id.toString(),
    },
  });

  if (admins.length > 0) {
    await broadcastNotification({
      userIds: admins.map((admin) => admin._id),
      actorId: userId,
      type: NOTIFICATION_TYPES.ADMIN_MODERATION_ALERT,
      payload: {
        subjectType: 'MODERATION_BLOCK',
        subjectId: report._id.toString(),
        reportId: report._id.toString(),
        reason: 'CONTENT_BLOCKED',
        targetType,
        targetId,
        contentSnippet: String(content).slice(0, 240),
        categories: result.categories,
        matches: result.matches,
        actorName:
          actorSnapshot.displayName || actorSnapshot.username || 'A user',
        actorUsername: actorSnapshot.username || '',
        actorAvatarUrl: actor?.avatarUrl || '',
        navigationTarget: {
          route: 'ADMIN_REPORTS',
          reportId: report._id.toString(),
        },
      },
    });

    for (const admin of admins) {
      emitToUser(admin._id.toString(), 'admin:moderation_alert', {
        reportId: report._id.toString(),
        actor: actorSnapshot,
        targetType,
        targetId,
        categories: result.categories,
        matches: result.matches,
      });
    }
  }

  return report;
}

async function assertContentAllowed({ text, userId, targetType, targetId, action }) {
  // Sticker codes are special non-text payloads embedded as message content
  // and do not need moderation scanning.
  if (typeof text === 'string' && text.startsWith('sticker:')) {
    return;
  }
  const result = scanText(text);
  if (!result.blocked) {
    return;
  }

  await notifyAdminsAboutBlockedContent({
    userId,
    targetType,
    targetId,
    action,
    content: text,
    result,
  });

  throw createModerationError(result);
}

module.exports = {
  assertContentAllowed,
  scanText,
};
