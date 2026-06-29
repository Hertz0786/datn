import { useEffect, useState } from 'react';
import MetricCard from '../components/MetricCard';
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

function ReportCard({ report }) {
  // AUTO_MODERATION = content was blocked before it was saved; the
  // "reporter" is the system and the interesting person is the
  // author who tried to send it.
  const isAuto = report.source === 'AUTO_MODERATION';
  const subject = isAuto
    ? report.author?.displayName || report.author?.username || 'Unknown user'
    : report.reporter?.displayName || report.reporter?.username || 'Unknown user';
  const subjectLabel = isAuto ? 'Offender' : 'Reporter';

  // Prefer the snapshot the moderation pipeline saved on the
  // Report, then fall back to whatever the post/comment lookup
  // produced.
  const snippet = report.target?.content || report.targetContent || report.details || '';

  return (
    <div className="review-card report-card">
      <div className="report-card-main">
        <div className="report-card-headline">
          <SourceBadge source={report.source} />
          <strong className="report-card-category">{report.category}</strong>
          {report.duplicateCount > 1 && (
            <span className="duplicate-pill" title="Multiple reports on the same target">
              ×{report.duplicateCount}
            </span>
          )}
        </div>
        <p className="report-card-snippet" title={snippet}>
          “{snippet}”
        </p>
        <div className="report-card-meta">
          <span className="report-card-subject">
            <em>{subjectLabel}:</em> <strong>{subject}</strong>
          </span>
          <span className="report-card-time">
            {formatRelativeTime(report.lastReportedAt)}
          </span>
        </div>
      </div>
      <div className="report-card-side">
        <UrgencyMeter value={report.urgency} />
        <StatusBadge value={report.status} />
      </div>
    </div>
  );
}

export default function DashboardPage({ onNavigate }) {
  const [data, setData] = useState({
    stats: [],
    topReports: [],
    flaggedPosts: [],
    watchedUsers: [],
    auditEvents: [],
  });
  const [error, setError] = useState('');

  useEffect(() => {
    let active = true;
    setError('');
    api
      .getDashboard()
      .then((payload) => {
        if (!active) return;
        setData({
          stats: payload.stats || [],
          topReports: payload.topReports || [],
          flaggedPosts: payload.flaggedPosts || [],
          watchedUsers: payload.watchedUsers || [],
          auditEvents: payload.auditEvents || [],
        });
      })
      .catch((err) => {
        if (active) setError(err.message || 'Failed to load dashboard data.');
      });
    return () => {
      active = false;
    };
  }, []);

  return (
    <section className="page">
      <PageHeader
        title="Operations dashboard"
        description="High-level health view for moderation, safety and user activity."
        action={<button className="primary-button" onClick={() => onNavigate('reports')}>Review reports</button>}
      />
      {error && <div className="form-error">{error}</div>}
      <div className="metrics-grid">
        {data.stats.map((item) => (
          <MetricCard key={item.label} {...item} />
        ))}
      </div>
      <div className="dashboard-grid">
        <article className="panel">
          <div className="panel-header">
            <h2>Highest priority reports</h2>
            <button onClick={() => onNavigate('reports')}>Open</button>
          </div>
          <div className="stack">
            {data.topReports.length === 0 && <p>No priority reports.</p>}
            {data.topReports.slice(0, 5).map((report) => (
              <ReportCard
                key={report.id || report._id}
                report={report}
              />
            ))}
          </div>
        </article>
        <article className="panel">
          <div className="panel-header">
            <h2>Flagged content</h2>
            <button onClick={() => onNavigate('content')}>Open</button>
          </div>
          <div className="stack">
            {data.flaggedPosts.length === 0 && <p>No flagged content.</p>}
            {data.flaggedPosts.map((flag) => {
              // Backend wraps the actual content under `target`. The
              // shape of `target` varies by `sourceType`:
              //   POST/COMMENT/MESSAGE → { kind, content, author, ... }
              //   MEDIA                → { kind, url, author, reason, ... }
              // We must read from `flag.target` — there is no
              // `flag.content` / `flag.author` at the top level.
              const target = flag.target || {};
              const isMedia = target.kind === 'MEDIA';
              const snippet = isMedia
                ? `AI: ${target.reason || 'unsafe'}`
                : (target.content || '');
              return (
                <div className="review-card flagged-card" key={flag.id}>
                  {isMedia && target.url ? (
                    <img
                      className="flagged-thumb"
                      src={target.url}
                      alt={`Flagged media by ${target.author || ''}`}
                      loading="lazy"
                    />
                  ) : (
                    <div className="flagged-thumb flagged-thumb-placeholder">
                      {isMedia ? '📁' : '📝'}
                    </div>
                  )}
                  <div className="flagged-card-main">
                    <div className="flagged-card-headline">
                      <StatusBadge value={target.kind || flag.sourceType || 'POST'} />
                      <strong>{target.author || '—'}</strong>
                      <span className="flagged-card-snippet">“{snippet}”</span>
                    </div>
                    <div className="flagged-card-meta">
                      <span>
                        {flag.flagCount > 1 ? `${flag.flagCount} flags` : '1 flag'}
                      </span>
                      {flag.userReportCount > 0 && (
                        <span className="flagged-card-user-reports">
                          + {flag.userReportCount} user report{flag.userReportCount > 1 ? 's' : ''}
                        </span>
                      )}
                    </div>
                  </div>
                  <div className="flagged-card-side">
                    <span className="flagged-score" title="AI safety score (0-1)">
                      {Number(flag.score).toFixed(2)}
                    </span>
                    <StatusBadge value={target.status || 'PENDING'} />
                  </div>
                </div>
              );
            })}
          </div>
        </article>
        <article className="panel">
          <div className="panel-header">
            <h2>Watched accounts</h2>
            <button onClick={() => onNavigate('users')}>Open</button>
          </div>
          <div className="stack">
            {data.watchedUsers.length === 0 && <p>No watched accounts.</p>}
            {data.watchedUsers.map((user) => (
              <div className="review-card" key={user.id || user._id}>
                <div>
                  <strong>{user.name || user.displayName}</strong>
                  <p>@{user.username} / age {user.age}</p>
                </div>
                <StatusBadge value={user.risk} />
              </div>
            ))}
          </div>
        </article>
        <article className="panel">
          <div className="panel-header">
            <h2>Audit trail</h2>
            <button onClick={() => onNavigate('audit')}>View all</button>
          </div>
          <div className="stack">
            {data.auditEvents.length === 0 && <p className="muted">No audit events.</p>}
            {data.auditEvents.map((event) => {
              const actionLower = (event.action || '').toLowerCase();
              const actionColor = actionLower.includes('delete') || actionLower.includes('ban') || actionLower.includes('remove') || actionLower.includes('block')
                ? '#a01843'
                : actionLower.includes('approve') || actionLower.includes('publish') || actionLower.includes('allow')
                ? '#0a7550'
                : '#21385f';
              const icon = actionLower.includes('delete') || actionLower.includes('remove') ? '🗑'
                : actionLower.includes('ban') || actionLower.includes('suspend') ? '⛔'
                : actionLower.includes('hide') || actionLower.includes('block') ? '👁'
                : actionLower.includes('approve') || actionLower.includes('publish') || actionLower.includes('allow') ? '✅'
                : actionLower.includes('warn') ? '⚠'
                : '📋';

              return (
                <div className="audit-dash-item" key={event.id || event._id}>
                  <span className="audit-dash-icon">{icon}</span>
                  <div className="audit-dash-content">
                    <div className="audit-dash-top">
                      <strong className="audit-actor">{event.actorUsername || event.actorId || '—'}</strong>
                      <span className="audit-dash-time">
                        {(() => {
                          const d = new Date(event.createdAt);
                          if (Number.isNaN(d.getTime())) return '';
                          const diffMs = Date.now() - d.getTime();
                          const minutes = Math.floor(diffMs / 60000);
                          if (minutes < 1) return 'just now';
                          if (minutes < 60) return `${minutes}m ago`;
                          const hours = Math.floor(minutes / 60);
                          if (hours < 24) return `${hours}h ago`;
                          return `${Math.floor(hours / 24)}d ago`;
                        })()}
                      </span>
                    </div>
                    <p className="audit-action" style={{ color: actionColor }}>{event.action}</p>
                    {event.targetType && (
                      <span className="audit-target">{event.targetType}{event.targetId ? `/${event.targetId.slice(-8)}` : ''}</span>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </article>
      </div>
    </section>
  );
}
