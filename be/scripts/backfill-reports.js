// One-off backfill for moderation reports that were created before
// the Report model learned about `source` / `targetAuthorId` /
// `targetContent`. Every pre-fix auto-flag has:
//   - source: default 'USER' (we want 'AUTO_MODERATION')
//   - targetAuthorId: null  (we can recover it from targetId)
//   - targetContent: ''    (we can recover it from `details`)
//
// We only touch rows whose targetId starts with "blocked-" (those
// are clearly auto-flagged). Real user reports and any other shape
// are left alone.

const mongoose = require('mongoose');
const env = require('../src/config/env');
const Report = require('../src/models/Report');
const User = require('../src/models/User');

const BLOCKED_ID_RE = /^blocked-(?:post|message|comment):([a-f0-9]{24,})(?::([a-f0-9]{24,}))?/i;
const PREVIEW_RE = /Content preview:\s*(.+)$/;

function parseBlockedTarget(targetId) {
  const match = BLOCKED_ID_RE.exec(String(targetId || ''));
  if (!match) return null;
  return {
    sourceId: match[1] || null,
    userId: match[2] || match[1] || null,
  };
}

function extractPreview(details) {
  if (!details) return '';
  const match = PREVIEW_RE.exec(String(details));
  return match ? match[1].trim() : '';
}

(async () => {
  const uri = env.mongoUri.replace(
    /<db_password>|<password>|YOUR_PASSWORD/g,
    encodeURIComponent(String(env.mongoPassword || '')),
  );
  await mongoose.connect(uri);

  const reports = await Report.find({ targetId: { $regex: /^blocked-/ } });
  console.log(`Found ${reports.length} blocked-* reports to inspect`);

  const userIds = new Set();
  const plan = [];

  for (const r of reports) {
    const parsed = parseBlockedTarget(r.targetId);
    if (!parsed || !parsed.userId) continue;
    userIds.add(parsed.userId);

    const needSource = r.source !== 'AUTO_MODERATION';
    const needAuthor = !r.targetAuthorId;
    const needContent = !r.targetContent && extractPreview(r.details);

    if (needSource || needAuthor || needContent) {
      plan.push({ report: r, parsed, needSource, needAuthor, needContent });
    }
  }

  console.log(`Will patch ${plan.length} reports`);

  const users = await User.find({ _id: { $in: [...userIds] } }).select(
    '_id',
  );
  const userById = new Map(users.map((u) => [u._id.toString(), u]));

  let patched = 0;
  for (const { report, parsed, needSource, needAuthor, needContent } of plan) {
    if (needSource) report.source = 'AUTO_MODERATION';
    if (needAuthor) {
      const exists = userById.get(parsed.userId);
      if (exists) {
        report.targetAuthorId = exists._id;
      }
    }
    if (needContent) {
      report.targetContent = extractPreview(report.details);
    }
    await report.save();
    patched += 1;
  }

  console.log(`Patched ${patched} reports.`);
  await mongoose.disconnect();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
