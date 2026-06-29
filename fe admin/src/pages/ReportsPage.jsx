import { useCallback, useEffect, useMemo, useState } from 'react';
import PageHeader from '../components/PageHeader';
import StatusBadge from '../components/StatusBadge';
import SourceBadge from '../components/SourceBadge';
import UrgencyMeter from '../components/UrgencyMeter';
import { api } from '../services/api';

// ── Formatters ────────────────────────────────────────────────────────

function formatRelativeTime(value) {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  const diffMs = Date.now() - date.getTime();
  const minutes = Math.floor(diffMs / 60000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days}d ago`;
  return date.toLocaleDateString();
}

function formatTime(value) {
  if (!value) return '';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString();
}

// ── Human-readable type / category helpers ───────────────────────────

function describeTarget(reportOrTargetType) {
  if (!reportOrTargetType) return 'Unknown';
  const type = typeof reportOrTargetType === 'string'
    ? reportOrTargetType
    : (reportOrTargetType.targetType || reportOrTargetType.kind || '');
  switch (type.toUpperCase()) {
    case 'MESSAGE': return 'Chat message';
    case 'POST':    return 'Post';
    case 'COMMENT': return 'Comment';
    case 'USER':    return 'User';
    case 'GROUP':   return 'Group';
    default:        return type || 'Unknown';
  }
}

function describeCategory(category) {
  const map = {
    BULLYING: 'Bullying / Harassment',
    UNSAFE_CONTENT: 'Unsafe Content',
    PRIVATE_INFO: 'Private Info Shared',
    SPAM: 'Spam',
    OTHER: 'Other',
  };
  return map[String(category || '').toUpperCase()] || category || 'Unknown';
}

// ── Cross-payload field resolvers ────────────────────────────────────
// The admin panel talks to two endpoints:
//
//   1. GET /api/admin/reports           → field name `author` (targetAuthor)
//   2. GET /api/safety/reports/moderation → field name `targetAuthor`
//
// In an AUTO_MODERATION report the "reporter" is effectively the system
// (no real user submitted it), so for those we surface the offender
// (the user who authored the offending content) as the headline subject.
function getOffender(report) {
  if (!report) return null;
  return report.targetAuthor || report.author || null;
}

function getReporter(report) {
  if (!report) return null;
  return report.reporter || null;
}

// ── Target detail renderer ────────────────────────────────────────────

function MediaPreview({ urls }) {
  if (!urls || urls.length === 0) {
    return <span className="media-empty">No media</span>;
  }
  const visible = urls.slice(0, 4);
  const remaining = urls.length - visible.length;
  return (
    <div className="media-thumbs">
      {visible.map((url, index) => {
        const isVideo = /\.(mp4|webm|mov)(\?|$)/i.test(url) || url.includes('/video/');
        return (
          <a
            key={`${url}-${index}`}
            href={url}
            target="_blank"
            rel="noreferrer noopener"
            className="media-thumb"
          >
            {isVideo ? (
              <div className="video-thumb small"><span>▶</span></div>
            ) : (
              <img src={url} alt={`attachment ${index + 1}`} loading="lazy" />
            )}
          </a>
        );
      })}
      {remaining > 0 && <span className="media-more">+{remaining}</span>}
    </div>
  );
}

function TargetDetail({ target, targetType, onOpenPost, targetId, targetContent }) {
  // The backend tries hard to populate the target with the actual
  // post/comment/user/group/message. When that succeeds we render a
  // rich card with every field we have. When it doesn't (the target
  // was deleted before review), we still show the type + raw id +
  // the snippet the moderation pipeline captured so admins can
  // triage without guessing.
  const typeLabel = describeTarget(targetType || target?.kind);

  if (!target) {
    return (
      <div className="target-card target-unresolved">
        <header>
          <span className="target-type-badge">{typeLabel}</span>
          <StatusBadge value="UNRESOLVED" />
          <span className="muted">Not in DB</span>
        </header>
        <div className="target-detail-grid">
          <span>Raw ID</span>
          <code className="target-id">{targetId || '—'}</code>
          {targetContent && (
            <>
              <span>Captured snippet</span>
              <blockquote className="report-detail-snippet">{targetContent}</blockquote>
            </>
          )}
        </div>
        <p className="muted">
          The reported content is no longer available (deleted before the report
          was reviewed).
        </p>
      </div>
    );
  }

  if (target.kind === 'POST') {
    // Admin payload puts the avatar on `avatarUrl` when the target is
    // a USER, but for POST the snapshot only carries
    // `displayName`/`username`. Use those to build an avatar if needed.
    const postAvatar = target.authorAvatarUrl || '';
    return (
      <div className="target-card target-post">
        <header>
          <div className="target-author-row">
            {postAvatar ? (
              <img className="target-avatar sm" src={postAvatar} alt="" />
            ) : (
              <div className="target-avatar sm placeholder">
                {(target.author || '?').charAt(0).toUpperCase()}
              </div>
            )}
            <div>
              <strong>{target.author || 'Unknown author'}</strong>
              {target.authorHandle && <small>@{target.authorHandle}</small>}
            </div>
          </div>
          <span className="target-type-badge">Post</span>
          <StatusBadge value={target.status} />
          <span className="muted">{formatTime(target.createdAt)}</span>
        </header>
        <p className="target-content">{target.content || '—'}</p>
        <MediaPreview urls={target.mediaUrls} />
        <div className="target-detail-grid">
          <span>Audience</span>
          <strong>{target.audience || '—'}</strong>
          <span>Reactions</span>
          <strong>{target.reactions ?? 0}</strong>
          <span>Comments</span>
          <strong>{target.commentCount ?? 0}</strong>
          {(target.topics || []).length > 0 && (
            <>
              <span>Topics</span>
              <strong>{target.topics.join(', ')}</strong>
            </>
          )}
          <span>Post ID</span>
          <code className="target-id">{targetId || target.id || '—'}</code>
        </div>
      </div>
    );
  }

  if (target.kind === 'COMMENT') {
    const commentAvatar = target.authorAvatarUrl || '';
    return (
      <div className="target-card target-comment">
        <header>
          <div className="target-author-row">
            {commentAvatar ? (
              <img className="target-avatar sm" src={commentAvatar} alt="" />
            ) : (
              <div className="target-avatar sm placeholder">
                {(target.author || '?').charAt(0).toUpperCase()}
              </div>
            )}
            <div>
              <strong>{target.author || 'Unknown author'}</strong>
              {target.authorHandle && <small>@{target.authorHandle}</small>}
            </div>
          </div>
          <span className="target-type-badge">Comment</span>
          <StatusBadge value={target.status || 'PUBLISHED'} />
          <span className="muted">{formatTime(target.createdAt)}</span>
        </header>
        <p className="target-content">{target.content || '—'}</p>
        <div className="target-detail-grid">
          <span>Comment ID</span>
          <code className="target-id">{targetId || target.id || '—'}</code>
          {target.postId && (
            <>
              <span>Parent post</span>
              <strong>
                <button
                  type="button"
                  className="link-button"
                  onClick={() => onOpenPost && onOpenPost(target.postId)}
                >
                  ↗ Open ({String(target.postId).slice(-8)}…)
                </button>
              </strong>
            </>
          )}
        </div>
      </div>
    );
  }

  if (target.kind === 'USER') {
    return (
      <div className="target-card target-user">
        <header>
          {target.avatarUrl ? (
            <img className="target-avatar" src={target.avatarUrl} alt="" />
          ) : (
            <div className="target-avatar placeholder">
              {(target.displayName || target.username || '?').charAt(0).toUpperCase()}
            </div>
          )}
          <div>
            <strong>{target.displayName || target.username || 'Unknown user'}</strong>
            {target.username && <small>@{target.username}</small>}
          </div>
          <span className="target-type-badge">User</span>
          <StatusBadge value={target.moderationStatus || 'ACTIVE'} />
        </header>
        <div className="target-detail-grid">
          <span>Role</span>
          <strong>{target.role || '—'}</strong>
          {target.age != null && (
            <>
              <span>Age</span>
              <strong>{target.age}</strong>
            </>
          )}
          <span>Joined</span>
          <strong>{formatTime(target.createdAt)}</strong>
          <span>User ID</span>
          <code className="target-id">{targetId || target.id || '—'}</code>
        </div>
      </div>
    );
  }

  if (target.kind === 'GROUP') {
    return (
      <div className="target-card target-group">
        <header>
          <div className="target-author-row">
            <div className="target-avatar sm placeholder">G</div>
            <div>
              <strong>{target.name || 'Unnamed group'}</strong>
              {target.topic && <small>{target.topic}</small>}
            </div>
          </div>
          <span className="target-type-badge">Group</span>
          <StatusBadge value="ACTIVE" />
          <span className="muted">{formatTime(target.createdAt)}</span>
        </header>
        {target.description && (
          <p className="target-content">{target.description}</p>
        )}
        <div className="target-detail-grid">
          <span>Members</span>
          <strong>{target.memberCount ?? 0}</strong>
          <span>Topic</span>
          <strong>{target.topic || '—'}</strong>
          <span>Group ID</span>
          <code className="target-id">{targetId || target.id || '—'}</code>
        </div>
      </div>
    );
  }

  if (target.kind === 'MESSAGE') {
    return (
      <div className="target-card target-message">
        <header>
          <div className="target-author-row">
            {target.authorAvatarUrl ? (
              <img className="target-avatar sm" src={target.authorAvatarUrl} alt="" />
            ) : (
              <div className="target-avatar sm placeholder">
                {(target.author || '?').charAt(0).toUpperCase()}
              </div>
            )}
            <div>
              <strong>{target.author || 'Unknown user'}</strong>
              {target.authorHandle && <small>@{target.authorHandle}</small>}
            </div>
          </div>
          <span className="target-type-badge">Message</span>
          <span className="muted">{formatTime(target.createdAt)}</span>
        </header>
        <p className="target-content">{target.content || '—'}</p>
        <div className="target-detail-grid">
          <span>Message ID</span>
          <code className="target-id">{targetId || target.id || '—'}</code>
        </div>
      </div>
    );
  }

  // Synthetic blocked content
  return (
    <div className="target-card target-blocked">
      <header>
        <strong>Blocked {target.kind?.replace('BLOCKED_', '') || targetType}</strong>
        <StatusBadge value="BLOCKED" />
      </header>
      {target.content && <p className="target-content">{target.content}</p>}
      {target.relatedId && (
        <p className="muted">Related id: {target.relatedId}</p>
      )}
    </div>
  );
}

// ── User mini-card (used in list rows) ───────────────────────────────

function UserCard({ user, label }) {
  if (!user) return null;
  return (
    <div className="user-card-inline">
      {user.avatarUrl ? (
        <img className="user-card-avatar" src={user.avatarUrl} alt="" />
      ) : (
        <div className="user-card-avatar placeholder">
          {(user.displayName || user.username || '?').charAt(0).toUpperCase()}
        </div>
      )}
      <div className="user-card-info">
        <span className="user-card-name">{user.displayName || user.username}</span>
        {user.username && <span className="user-card-handle">@{user.username}</span>}
      </div>
    </div>
  );
}

// ── Main page ─────────────────────────────────────────────────────────

const STATUS_OPTIONS = [
  { value: 'ALL', label: 'All' },
  { value: 'PENDING', label: 'Pending' },
  { value: 'REVIEWING', label: 'Reviewing' },
  { value: 'RESOLVED', label: 'Resolved' },
  { value: 'DISMISSED', label: 'Dismissed' },
];

export default function ReportsPage() {
  const [reports, setReports] = useState([]);
  const [selected, setSelected] = useState(null);
  const [error, setError] = useState('');
  const [statusFilter, setStatusFilter] = useState('ALL');
  const [sortMode, setSortMode] = useState('queue');
  const [loading, setLoading] = useState(false);
  // Bump this counter to force a reload (Refresh button).
  const [refreshTick, setRefreshTick] = useState(0);

  // Linked post loaded via the dedicated GET /reports/:id endpoint
  // (instead of the previous listPosts scan).
  const [linkedPost, setLinkedPost] = useState(null);
  const [linkedPostLoading, setLinkedPostLoading] = useState(false);
  const [linkedPostError, setLinkedPostError] = useState('');

  const loadReports = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const payload = await api.listReports(statusFilter, sortMode);
      const items = payload.items || [];
      setReports(items);

      // Auto-select the report most worth the admin's attention:
      //   1. The newest unresolved (PENDING/REVIEWING) report, OR
      //   2. The newest report of any status.
      // This way when a kid files a brand-new report, the detail
      // panel jumps straight to it instead of leaving the admin
      // staring at a year-old dismissed ticket.
      const newest = items.find((r) => r.status === 'PENDING')
        || items.find((r) => r.status === 'REVIEWING')
        || items[0]
        || null;
      setSelected(newest);
    } catch (err) {
      setError(err.message || 'Failed to load reports.');
    } finally {
      setLoading(false);
    }
  }, [statusFilter, sortMode]);

  // Reload whenever the filter / sort changes, or when the admin
  // bumps the refresh counter.
  useEffect(() => {
    let active = true;
    loadReports().then(() => {
      if (!active) return;
    });
    return () => {
      active = false;
    };
  }, [loadReports, refreshTick]);

  function refresh() {
    setRefreshTick((n) => n + 1);
  }

  // Reset linked-post panel whenever the selected report changes.
  useEffect(() => {
    setLinkedPost(null);
    setLinkedPostError('');
    setLinkedPostLoading(false);
  }, [selected?.id]);

  async function setStatus(id, status) {
    api.updateReport(id, status).catch(() => {});
    setReports((items) =>
      items.map((r) => (r.id === id ? { ...r, status } : r)),
    );
    setSelected((item) => (item?.id === id ? { ...item, status } : item));
  }

  function openParentPost(postId) {
    setLinkedPost(null);
    setLinkedPostError('');
    setLinkedPostLoading(true);

    // Use the dedicated GET /reports endpoint that returns the enriched
    // report object including the parent post data when targetType is COMMENT.
    // We fetch all reports (already loaded) and find the parent, but for
    // orphaned comments we fall back to the admin posts list.
    api
      .getReport(selected?.id)
      .then((payload) => {
        const report = payload.item || payload;
        // The backend now resolves post content in the target for COMMENTs.
        if (report?.target?.postId) {
          return api.listPosts('', false).then((postPayload) => {
            const post = (postPayload.items || []).find(
              (p) => (p.id || p._id) === report.target.postId,
            );
            if (post) {
              setLinkedPost(post);
            } else {
              setLinkedPostError('The parent post could not be found.');
            }
          });
        } else {
          setLinkedPostError('No parent post associated with this comment.');
        }
      })
      .catch(() => {
        // Fallback: scan the posts list
        api
          .listPosts()
          .then((postPayload) => {
            const post = (postPayload.items || []).find(
              (p) => (p.id || p._id) === postId,
            );
            if (post) {
              setLinkedPost(post);
            } else {
              setLinkedPostError('The parent post could not be found in the current post list.');
            }
          })
          .catch((err) => {
            setLinkedPostError(err.message || 'Failed to load the parent post.');
          })
          .finally(() => setLinkedPostLoading(false));
      });
  }

  // Build the active target — use the backend-enriched target when available,
  // and fall back to the linkedPost data for COMMENT reports.
  const activeTarget = useMemo(() => {
    if (linkedPost) {
      return {
        kind: 'POST',
        author: linkedPost.author || linkedPost.displayName,
        authorHandle: linkedPost.username || '',
        authorAvatarUrl: linkedPost.avatarUrl || '',
        content: linkedPost.content || '',
        mediaUrls: linkedPost.mediaUrls || [],
        status: linkedPost.status || 'PUBLISHED',
        audience: linkedPost.visibility || 'FRIENDS',
        reactions: linkedPost.reactions || 0,
        commentCount: linkedPost.commentCount || 0,
        topics: linkedPost.topics || [],
        createdAt: linkedPost.createdAt,
      };
    }
    return selected?.target || null;
  }, [linkedPost, selected]);

  return (
    <section className="page">
      <div className="page-toolbar">
        <PageHeader
          title="Safety reports"
          description="Triage user reports and record moderation outcomes."
        />
        <div className="toolbar-actions">
          <button
            className={`ghost-button ${loading ? 'loading' : ''}`}
            onClick={refresh}
            disabled={loading}
            title="Refresh the report list"
          >
            {loading ? '↻ Loading…' : '↻ Refresh'}
          </button>
        </div>
      </div>

      {error && <div className="form-error">{error}</div>}

      <div className="split-grid">
        {/* ── Left: report list ─────────────────────────────────── */}
        <div className="panel list-panel">
          {/* Status filter */}
          <div className="filter-bar">
            {STATUS_OPTIONS.map((opt) => (
              <button
                key={opt.value}
                className={`filter-chip ${statusFilter === opt.value ? 'active' : ''}`}
                onClick={() => setStatusFilter(opt.value)}
              >
                {opt.label}
              </button>
            ))}
            <div className="filter-divider" />
            <select
              className="sort-select"
              value={sortMode}
              onChange={(e) => setSortMode(e.target.value)}
              title="Sort order"
            >
              <option value="queue">Queue (unresolved first)</option>
              <option value="newest">Newest first</option>
              <option value="oldest">Oldest first</option>
            </select>
          </div>

          {reports.length === 0 && (
            <p className="muted" style={{ padding: '16px' }}>
              {statusFilter === 'ALL'
                ? 'No reports found.'
                : `No ${statusFilter.toLowerCase()} reports.`}
            </p>
          )}

          {reports.map((report) => {
            const isAuto = report.source === 'AUTO_MODERATION';
            // For AUTO_MODERATION the "reporter" is the system; we
            // surface the offender instead. For user reports the
            // reporter is the kid who filed the complaint.
            const subject = isAuto ? getOffender(report) : getReporter(report);
            const subjectName = subject?.displayName || subject?.username;
            const snippet =
              report.target?.content || report.targetContent || report.details || '';

            return (
              <button
                className={`list-row ${selected?.id === report.id ? 'selected' : ''}`}
                key={report.id}
                onClick={() => setSelected(report)}
              >
                <div className="list-row-content">
                  <div className="list-row-headline">
                    <SourceBadge source={report.source} />
                    <strong>{describeCategory(report.category)}</strong>
                    <UrgencyMeter value={report.urgency} />
                    {/* NEW badge: PENDING reports from the last 24 hours */}
                    {report.status === 'PENDING' && (() => {
                      const hoursOld = report.createdAt
                        ? (Date.now() - new Date(report.createdAt).getTime()) / 3600000
                        : Infinity;
                      return hoursOld < 24
                        ? <span className="new-badge">NEW</span>
                        : null;
                    })()}
                  </div>

                  {/* Reporter / offender */}
                  <div className="list-row-subject">
                    {isAuto ? 'Offender' : 'Reporter'}:{' '}
                    <strong>{subjectName || 'Unknown'}</strong>
                    {subject?.username && (
                      <span className="muted"> @{subject.username}</span>
                    )}
                  </div>

                  {/* Target summary */}
                  <div className="list-row-target">
                    <span className="target-type-badge">
                      {describeTarget(report)}
                    </span>
                    {report.target?.displayName && (
                      <span>{report.target.displayName}</span>
                    )}
                    {report.target?.author && (
                      <span>{report.target.author}</span>
                    )}
                    {report.target?.username && (
                      <span className="muted">@{report.target.username}</span>
                    )}
                    {report.target?.name && !report.target?.author && (
                      <span>{report.target.name}</span>
                    )}
                  </div>

                  {/* Content snippet */}
                  {snippet && (
                    <span className="list-row-quote">
                      "{snippet.slice(0, 80)}{snippet.length > 80 ? '…' : ''}"
                    </span>
                  )}

                  <div className="list-row-meta">
                    {formatRelativeTime(report.createdAt)}
                  </div>
                </div>
                <StatusBadge value={report.status} />
              </button>
            );
          })}
        </div>

        {/* ── Right: report detail ──────────────────────────────── */}
        <div className="panel detail-panel">
          {selected && (() => {
            const isAuto = selected.source === 'AUTO_MODERATION';

            // Cross-payload field resolvers (admin route uses
            // `author`, safety route uses `targetAuthor`). For
            // AUTO_MODERATION the "reporter" is effectively the
            // system, so we surface the offender as the headline
            // subject. For user reports, the offender is whoever
            // wrote the offending content.
            const offenderInfo = isAuto
              ? getOffender(selected)
              : getOffender(selected);
            const reporterInfo = isAuto
              ? null
              : (getReporter(selected) || getOffender(selected));
            return (
              <>
                <div className="panel-header">
                  <h2>
                    {describeCategory(selected.category)}
                    <SourceBadge source={selected.source} />
                  </h2>
                  <StatusBadge value={selected.status} />
                </div>

                {/* Reported content — the most important section,
                    surfaced first so admins can see exactly what the
                    user / moderator flagged without scrolling. */}
                <h3 className="section-title">Reported content</h3>
                <TargetDetail
                  target={activeTarget}
                  targetType={selected.targetType}
                  onOpenPost={openParentPost}
                  targetId={selected.targetId}
                  targetContent={selected.targetContent}
                />

                {linkedPostLoading && (
                  <p className="muted">Loading parent post…</p>
                )}
                {linkedPostError && (
                  <div className="form-error">{linkedPostError}</div>
                )}

                {/* Who is involved — reporter + offender */}
                <h3 className="section-title">People</h3>
                <div className="people-grid">
                  <div className="person-card">
                    <div className="person-card-label">
                      {isAuto ? 'Offender' : 'Reporter'}
                    </div>
                    <UserCard user={reporterInfo} />
                    {reporterInfo?.role && (
                      <div className="person-card-meta">
                        Role: <strong>{reporterInfo.role}</strong>
                      </div>
                    )}
                  </div>
                  {!isAuto && offenderInfo && (
                    <div className="person-card">
                      <div className="person-card-label">Offender</div>
                      <UserCard user={offenderInfo} />
                      {offenderInfo?.role && (
                        <div className="person-card-meta">
                          Role: <strong>{offenderInfo.role}</strong>
                        </div>
                      )}
                    </div>
                  )}
                </div>

                {/* Report metadata */}
                <h3 className="section-title">Report details</h3>
                <div className="detail-grid">
                  <span>Source</span>
                  <strong>
                    {isAuto
                      ? 'Auto-flagged by content moderation'
                      : 'Reported by a user'}
                  </strong>

                  <span>Urgency</span>
                  <div>
                    <UrgencyMeter value={selected.urgency} />
                    <span className="detail-helper">{selected.urgency}/5</span>
                  </div>

                  <span>Category</span>
                  <strong>{describeCategory(selected.category)}</strong>

                  <span>Target type</span>
                  <strong>{describeTarget(selected)}</strong>

                  <span>Status</span>
                  <StatusBadge value={selected.status} />

                  <span>Created</span>
                  <strong>{formatTime(selected.createdAt)} · {formatRelativeTime(selected.createdAt)}</strong>

                  {selected.updatedAt && selected.updatedAt !== selected.createdAt && (
                    <>
                      <span>Last update</span>
                      <strong>{formatTime(selected.updatedAt)} · {formatRelativeTime(selected.updatedAt)}</strong>
                    </>
                  )}

                  {selected.details && (
                    <>
                      <span>Reporter notes</span>
                      <em className="report-notes">{selected.details}</em>
                    </>
                  )}
                </div>

                {/* Raw identifiers — toggle to inspect exact IDs. */}
                <details className="raw-details">
                  <summary>Show raw identifiers</summary>
                  <div className="detail-grid raw-id-grid">
                    <span>Report ID</span>
                    <code className="target-id">{selected.id}</code>

                    <span>Reporter ID</span>
                    <code className="target-id">{getReporter(selected)?.id || '—'}</code>

                    <span>Target author ID</span>
                    <code className="target-id">{getOffender(selected)?.id || '—'}</code>

                    <span>Target ID</span>
                    <code className="target-id">{selected.targetId}</code>
                  </div>
                </details>

                {/* Action buttons */}
                <div className="button-row">
                  {selected.status === 'PENDING' && (
                    <button
                      onClick={() => setStatus(selected.id, 'REVIEWING')}
                    >
                      Mark reviewing
                    </button>
                  )}
                  {selected.status !== 'RESOLVED' && (
                    <button onClick={() => setStatus(selected.id, 'RESOLVED')}>
                      Resolve
                    </button>
                  )}
                  {selected.status !== 'DISMISSED' && (
                    <button
                      className="danger"
                      onClick={() => setStatus(selected.id, 'DISMISSED')}
                    >
                      Dismiss
                    </button>
                  )}
                </div>
              </>
            );
          })()}
        </div>
      </div>
    </section>
  );
}
