import { useEffect, useMemo, useState } from 'react';
import PageHeader from '../components/PageHeader';
import StatusBadge from '../components/StatusBadge';
import SourceBadge from '../components/SourceBadge';
import UrgencyMeter from '../components/UrgencyMeter';
import { api } from '../services/api';

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

function describeTarget(report) {
  if (!report) return '';
  if (report.targetType === 'MESSAGE') return 'Chat message';
  if (report.targetType === 'POST') return 'Post';
  if (report.targetType === 'COMMENT') return 'Comment';
  if (report.targetType === 'USER') return 'User';
  if (report.targetType === 'GROUP') return 'Group';
  return report.targetType || 'Unknown';
}

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
              <div className="video-thumb small">
                <span>▶</span>
              </div>
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

function TargetDetail({ target, targetType, onOpenPost, onOpenComment }) {
  // Render the offending content depending on what the report was
  // about. Posts show full body + media + audience stats; comments
  // show the comment body + a deep link to the parent post; users
  // show a small profile card; synthetic blocked-* targets just
  // show the snippet that the moderation pipeline captured.
  if (!target) {
    return (
      <p className="muted">
        The reported content is no longer available (deleted before the report
        was reviewed).
      </p>
    );
  }

  if (target.kind === 'POST') {
    return (
      <div className="target-card target-post">
        <header>
          <strong>{target.author || 'Unknown author'}</strong>
          {target.authorHandle && <small>@{target.authorHandle}</small>}
          <StatusBadge value={target.status} />
          <span className="muted">{formatTime(target.createdAt)}</span>
        </header>
        <p className="target-content">{target.content || '—'}</p>
        <MediaPreview urls={target.mediaUrls} />
        <div className="target-stats">
          <span>👀 {target.audience || '—'}</span>
          <span>❤ {target.reactions ?? 0}</span>
          <span>💬 {target.commentCount ?? 0}</span>
          {(target.topics || []).length > 0 && (
            <span>🏷 {target.topics.join(', ')}</span>
          )}
        </div>
      </div>
    );
  }

  if (target.kind === 'COMMENT') {
    return (
      <div className="target-card target-comment">
        <header>
          <strong>{target.author || 'Unknown author'}</strong>
          {target.authorHandle && <small>@{target.authorHandle}</small>}
          <StatusBadge value={target.status} />
          <span className="muted">{formatTime(target.createdAt)}</span>
        </header>
        <p className="target-content">{target.content || '—'}</p>
        {target.postId && (
          <button
            type="button"
            className="link-button"
            onClick={() => onOpenPost && onOpenPost(target.postId)}
          >
            ↗ Open parent post ({target.postId.slice(-6)})
          </button>
        )}
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
            <strong>{target.displayName || target.username}</strong>
            {target.username && <small>@{target.username}</small>}
          </div>
          <StatusBadge value={target.moderationStatus || 'ACTIVE'} />
        </header>
        <div className="target-stats">
          <span>Role: {target.role || '—'}</span>
          <span>Age: {target.age ?? '—'}</span>
          <span>Joined: {formatTime(target.createdAt)}</span>
        </div>
      </div>
    );
  }

  // Synthetic blocked-* target. The actual content was blocked
  // before save, so all we have is the captured snippet.
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

export default function ReportsPage() {
  const [reports, setReports] = useState([]);
  const [selected, setSelected] = useState(null);
  const [error, setError] = useState('');
  // When the admin clicks "Open parent post" from a COMMENT report,
  // we look up that post on demand and surface it in the same panel.
  const [linkedPost, setLinkedPost] = useState(null);
  const [linkedPostLoading, setLinkedPostLoading] = useState(false);
  const [linkedPostError, setLinkedPostError] = useState('');

  useEffect(() => {
    let active = true;
    setError('');
    api
      .listReports()
      .then((payload) => {
        if (!active) return;
        const items = payload.items || [];
        setReports(items);
        setSelected(items[0] || null);
      })
      .catch((err) => {
        if (active) setError(err.message || 'Failed to load reports.');
      });
    return () => {
      active = false;
    };
  }, []);

  // Reset the linked-post panel whenever the selected report changes.
  useEffect(() => {
    setLinkedPost(null);
    setLinkedPostError('');
    setLinkedPostLoading(false);
  }, [selected?.id || selected?._id]);

  function setStatus(id, status) {
    api.updateReport(id, status).catch(() => {});
    setReports((items) =>
      items.map((report) => ((report.id || report._id) === id ? { ...report, status } : report)),
    );
    setSelected((item) => ((item?.id || item?._id) === id ? { ...item, status } : item));
  }

  function openParentPost(postId) {
    setLinkedPost(null);
    setLinkedPostError('');
    setLinkedPostLoading(true);
    // The admin endpoints don't expose a "get one post" route, so we
    // list all posts and find it. This is fine for a moderator-only
    // view since the list is already cached client-side.
    api
      .listPosts()
      .then((payload) => {
        const post = (payload.items || []).find(
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
      .finally(() => {
        setLinkedPostLoading(false);
      });
  }

  // Use the backend-enriched target preview when present, otherwise
  // fall back to the raw `targetContent` / `details` snippet the
  // moderation pipeline captured at flag time.
  const activeTarget = useMemo(() => {
    if (linkedPost) {
      return {
        kind: 'POST',
        author: linkedPost.author,
        authorHandle: linkedPost.authorId ? linkedPost.authorId.slice(-6) : '',
        content: linkedPost.content,
        mediaUrls: linkedPost.mediaUrls || [],
        status: linkedPost.status,
        audience: linkedPost.visibility,
        reactions: linkedPost.reactions,
        commentCount: linkedPost.comments,
        topics: linkedPost.topics || [],
        createdAt: linkedPost.createdAt,
      };
    }
    return selected?.target;
  }, [linkedPost, selected]);

  return (
    <section className="page">
      <PageHeader
        title="Safety reports"
        description="Triage user reports and record moderation outcomes."
      />
      {error && <div className="form-error">{error}</div>}
      <div className="split-grid">
        <div className="panel list-panel">
          {reports.length === 0 && <p>No reports found.</p>}
          {reports.map((report) => {
            const isAuto = report.source === 'AUTO_MODERATION';
            const subjectName = isAuto
              ? report.author?.displayName || report.author?.username
              : report.reporter?.displayName || report.reporter?.username;
            const snippet =
              report.target?.content || report.targetContent || report.details || '';
            return (
              <button
                className={`list-row ${(selected?.id || selected?._id) === (report.id || report._id) ? 'selected' : ''}`}
                key={report.id || report._id}
                onClick={() => setSelected(report)}
              >
                <div className="list-row-content">
                  <div className="list-row-headline">
                    <SourceBadge source={report.source} />
                    <strong>{report.category}</strong>
                    <UrgencyMeter value={report.urgency} />
                  </div>
                  <span className="list-row-snippet">
                    {describeTarget(report)} · {isAuto ? 'Offender' : 'Reporter'}: {subjectName || 'Unknown'}
                  </span>
                  {snippet && (
                    <span className="list-row-quote">
                      "{snippet.slice(0, 80)}{snippet.length > 80 ? '…' : ''}"
                    </span>
                  )}
                </div>
                <StatusBadge value={report.status} />
              </button>
            );
          })}
        </div>
        <div className="panel detail-panel">
          {selected && (() => {
            const isAuto = selected.source === 'AUTO_MODERATION';
            const fallbackSnippet = selected.targetContent || selected.details || '';
            return (
              <>
                <div className="panel-header">
                  <h2>
                    {selected.category}
                    <SourceBadge source={selected.source} />
                  </h2>
                  <StatusBadge value={selected.status} />
                </div>

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

                  <span>{isAuto ? 'Offender' : 'Reporter'}</span>
                  <strong>
                    {isAuto
                      ? selected.author?.displayName || selected.author?.username || 'Unknown user'
                      : selected.reporter?.displayName || selected.reporter?.username || 'Unknown user'}
                  </strong>

                  {isAuto && selected.author?.username && (
                    <>
                      <span>Offender handle</span>
                      <strong>@{selected.author.username}</strong>
                    </>
                  )}

                  {!isAuto && selected.reporter?.username && (
                    <>
                      <span>Reporter handle</span>
                      <strong>@{selected.reporter.username}</strong>
                    </>
                  )}

                  <span>Target</span>
                  <strong>
                    {describeTarget(selected)} · {selected.targetId}
                  </strong>

                  <span>Reported</span>
                  <strong>{formatRelativeTime(selected.createdAt)}</strong>
                </div>

                <h3 className="section-title">Reported content</h3>
                <TargetDetail
                  target={activeTarget}
                  targetType={selected.targetType}
                  onOpenPost={openParentPost}
                />

                {!activeTarget && fallbackSnippet && (
                  <blockquote className="report-detail-snippet">
                    {fallbackSnippet}
                  </blockquote>
                )}

                {linkedPostLoading && (
                  <p className="muted">Loading parent post…</p>
                )}
                {linkedPostError && (
                  <div className="form-error">{linkedPostError}</div>
                )}

                {selected.details && !activeTarget && (
                  <div className="detail-grid">
                    <span>Notes</span>
                    <strong>{selected.details}</strong>
                  </div>
                )}

                <div className="button-row">
                  <button onClick={() => setStatus(selected.id || selected._id, 'REVIEWING')}>Mark reviewing</button>
                  <button onClick={() => setStatus(selected.id || selected._id, 'RESOLVED')}>Resolve</button>
                  <button className="danger" onClick={() => setStatus(selected.id || selected._id, 'DISMISSED')}>Dismiss</button>
                </div>
              </>
            );
          })()}
        </div>
      </div>
    </section>
  );
}
