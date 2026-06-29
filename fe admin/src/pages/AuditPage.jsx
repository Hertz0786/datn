import { useEffect, useState, useCallback } from 'react';
import PageHeader from '../components/PageHeader';
import { api } from '../services/api';

const ACTION_COLORS = {
  ban: '#a01843',
  delete: '#a01843',
  remove: '#a01843',
  suspend: '#bd2b71',
  hide: '#a05a00',
  approve: '#0a7550',
  publish: '#0a7550',
  allow: '#0a7550',
  warn: '#8a5600',
  block: '#a01843',
  unblock: '#0a7550',
  create: '#18345f',
  update: '#18345f',
  set: '#18345f',
  unsuspend: '#0a7550',
  reactivate: '#0a7550',
};

function getActionColor(action = '') {
  const lower = action.toLowerCase();
  for (const [key, color] of Object.entries(ACTION_COLORS)) {
    if (lower.includes(key)) return color;
  }
  return '#21385f';
}

function getActionIcon(action = '') {
  const lower = action.toLowerCase();
  if (lower.includes('delete') || lower.includes('remove')) return '🗑';
  if (lower.includes('ban') || lower.includes('suspend')) return '⛔';
  if (lower.includes('hide') || lower.includes('block')) return '👁';
  if (lower.includes('approve') || lower.includes('publish') || lower.includes('allow')) return '✅';
  if (lower.includes('warn')) return '⚠';
  if (lower.includes('create')) return '🆕';
  if (lower.includes('update') || lower.includes('set')) return '✏';
  if (lower.includes('unblock') || lower.includes('unban') || lower.includes('unsuspend') || lower.includes('reactivate')) return '🔓';
  if (lower.includes('verify')) return '🎖';
  if (lower.includes('report')) return '🚩';
  return '📋';
}

const ACTION_LABELS = {
  'user_ban': 'Cấm người dùng',
  'user_unban': 'Bỏ cấm người dùng',
  'user_suspend': 'Đình chỉ người dùng',
  'user_unsuspend': 'Bỏ đình chỉ người dùng',
  'user_delete': 'Xóa tài khoản',
  'user_warn': 'Cảnh báo người dùng',
  'user_reactivate': 'Kích hoạt lại tài khoản',
  'post_delete': 'Xóa bài viết',
  'post_hide': 'Ẩn bài viết',
  'post_approve': 'Phê duyệt bài viết',
  'post_restore': 'Khôi phục bài viết',
  'post_flag': 'Báo cáo bài viết',
  'comment_delete': 'Xóa bình luận',
  'comment_hide': 'Ẩn bình luận',
  'comment_approve': 'Phê duyệt bình luận',
  'comment_restore': 'Khôi phục bình luận',
  'comment_flag': 'Báo cáo bình luận',
  'group_create': 'Tạo nhóm',
  'group_delete': 'Xóa nhóm',
  'group_update': 'Cập nhật nhóm',
  'group_hide': 'Ẩn nhóm',
  'group_approve': 'Phê duyệt nhóm',
  'group_join_approve': 'Phê duyệt tham gia nhóm',
  'friend_request_block': 'Chặn kết bạn',
  'friend_request_unblock': 'Bỏ chặn kết bạn',
  'media_delete': 'Xóa media',
  'media_hide': 'Ẩn media',
  'media_approve': 'Phê duyệt media',
  'report_resolve': 'Giải quyết báo cáo',
  'report_dismiss': 'Bỏ qua báo cáo',
  'user_verify': 'Xác minh người dùng',
  'user_unverify': 'Hủy xác minh người dùng',
  'safety_rule_update': 'Cập nhật quy tắc an toàn',
  'badge_update': 'Cập nhật huy hiệu',
  'admin_role_grant': 'Cấp quyền admin',
  'admin_role_revoke': 'Thu hồi quyền admin',
};

function getActionLabel(action = '') {
  if (ACTION_LABELS[action]) return ACTION_LABELS[action];
  if (ACTION_LABELS[action.toLowerCase()]) return ACTION_LABELS[action.toLowerCase()];
  return action
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

function formatDate(dateStr) {
  const d = new Date(dateStr);
  if (Number.isNaN(d.getTime())) return '—';
  const diffMs = Date.now() - d.getTime();
  const minutes = Math.floor(diffMs / 60000);
  if (minutes < 1) return 'Vừa xong';
  if (minutes < 60) return `${minutes} phút trước`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} giờ trước`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days} ngày trước`;
  return d.toLocaleString('vi-VN', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

function formatFullDate(dateStr) {
  const d = new Date(dateStr);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleString('vi-VN', {
    weekday: 'long',
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
}

function formatMetaValue(key, value) {
  if (value === null || value === undefined) return '—';
  if (typeof value === 'boolean') return value ? 'Có' : 'Không';
  if (typeof value === 'string') return value;
  if (typeof value === 'number') return String(value);
  return JSON.stringify(value);
}

function AuditCard({ event, expanded, onToggle }) {
  const actionColor = getActionColor(event.action);
  const icon = getActionIcon(event.action);
  const actionLabel = getActionLabel(event.action);
  const metaEntries = event.metadata ? Object.entries(event.metadata) : [];

  const targetUser = event._targetUser;

  return (
    <div className="audit-card" onClick={onToggle} role="button" tabIndex={0} onKeyDown={(e) => e.key === 'Enter' && onToggle()}>
      <div className="audit-card-header">
        <div className="audit-card-left">
          <span className="audit-icon">{icon}</span>
          <div className="audit-card-info">
            <div className="audit-card-meta">
              <strong className="audit-card-actor">{event.actorUsername || '—'}</strong>
              <span className="audit-card-time">{formatDate(event.createdAt)}</span>
            </div>
            <p className="audit-card-action" style={{ color: actionColor }}>
              {actionLabel}
            </p>
          </div>
        </div>
        <div className="audit-card-right">
          {event.targetType && (
            <span className="audit-target-badge">
              {event.targetType}
              {targetUser
                ? <span className="audit-target-id">#{targetUser.displayName || targetUser.username || String(event.targetId || '').slice(-8)}</span>
                : event.targetId
                  ? <span className="audit-target-id">#{String(event.targetId).slice(-8)}</span>
                  : null}
            </span>
          )}
          <span className="audit-expand-icon">{expanded ? '▲' : '▼'}</span>
        </div>
      </div>

      {expanded && (
        <div className="audit-card-detail">
          <div className="audit-detail-grid">
            <div className="audit-detail-row">
              <span className="audit-detail-label">Mã hành động</span>
              <code className="audit-detail-value">{event.action}</code>
            </div>
            {event.actorId && (
              <div className="audit-detail-row">
                <span className="audit-detail-label">Actor ID</span>
                <code className="audit-detail-value">{event.actorId}</code>
              </div>
            )}
            <div className="audit-detail-row">
              <span className="audit-detail-label">Người thực hiện</span>
              <span className="audit-detail-value">{event.actorUsername || '—'}</span>
            </div>
            <div className="audit-detail-row">
              <span className="audit-detail-label">Loại mục tiêu</span>
              <span className="audit-detail-value">{event.targetType || '—'}</span>
            </div>
            <div className="audit-detail-row">
              <span className="audit-detail-label">ID mục tiêu</span>
              <code className="audit-detail-value">{event.targetId || '—'}</code>
            </div>
            {targetUser && (
              <div className="audit-detail-row">
                <span className="audit-detail-label">Người dùng liên quan</span>
                <span className="audit-detail-value">
                  {targetUser.displayName || targetUser.username || '—'}
                  {targetUser.username ? ` (@${targetUser.username})` : ''}
                </span>
              </div>
            )}
            {metaEntries.find(([k]) => /targetUsername|targetUser|targetName/i.test(k)) && (
              <div className="audit-detail-row">
                <span className="audit-detail-label">Tên mục tiêu</span>
                <span className="audit-detail-value">
                  {(() => {
                    const entry = metaEntries.find(([k]) => /targetUsername|targetUser|targetName/i.test(k));
                    return entry ? formatMetaValue(entry[0], entry[1]) : '—';
                  })()}
                </span>
              </div>
            )}
            {metaEntries.find(([k]) => /reason/i.test(k)) && (
              <div className="audit-detail-row">
                <span className="audit-detail-label">Lý do</span>
                <span className="audit-detail-value">
                  {(() => {
                    const entry = metaEntries.find(([k]) => /reason/i.test(k));
                    return entry ? formatMetaValue(entry[0], entry[1]) : '—';
                  })()}
                </span>
              </div>
            )}
            {metaEntries.find(([k]) => /note|notes|comment/i.test(k)) && (
              <div className="audit-detail-row">
                <span className="audit-detail-label">Ghi chú</span>
                <span className="audit-detail-value">
                  {(() => {
                    const entry = metaEntries.find(([k]) => /note|notes|comment/i.test(k));
                    return entry ? formatMetaValue(entry[0], entry[1]) : '—';
                  })()}
                </span>
              </div>
            )}
            {metaEntries.find(([k]) => /content|text|post|body/i.test(k)) && (
              <div className="audit-detail-row audit-detail-row-full">
                <span className="audit-detail-label">Nội dung</span>
                <pre className="audit-detail-meta">
                  {(() => {
                    const entry = metaEntries.find(([k]) => /content|text|post|body/i.test(k));
                    return entry ? formatMetaValue(entry[0], entry[1]) : '—';
                  })()}
                </pre>
              </div>
            )}
            <div className="audit-detail-row">
              <span className="audit-detail-label">Thời gian</span>
              <span className="audit-detail-value">{formatFullDate(event.createdAt)}</span>
            </div>
            {metaEntries.length > 0 && (
              <div className="audit-detail-row audit-detail-row-full">
                <span className="audit-detail-label">Toàn bộ metadata</span>
                <pre className="audit-detail-meta">
                  {JSON.stringify(event.metadata, null, 2)}
                </pre>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

const FILTER_OPTIONS = [
  { value: '', label: 'Tất cả' },
  { value: 'user', label: 'Người dùng' },
  { value: 'post', label: 'Bài viết' },
  { value: 'comment', label: 'Bình luận' },
  { value: 'group', label: 'Nhóm' },
  { value: 'media', label: 'Media' },
  { value: 'report', label: 'Báo cáo' },
  { value: 'badge', label: 'Huy hiệu' },
  { value: 'safety', label: 'An toàn' },
  { value: 'admin', label: 'Admin' },
];

export default function AuditPage() {
  const [events, setEvents] = useState([]);
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [expandedId, setExpandedId] = useState(null);
  const [filter, setFilter] = useState('');
  const [search, setSearch] = useState('');
  const [searchInput, setSearchInput] = useState('');

  const loadPage = useCallback((pg) => {
    setLoading(true);
    setError('');
    api
      .listAudit(pg)
      .then((payload) => {
        setEvents(payload.items || []);
        setPage(payload.page || 1);
        setTotalPages(payload.totalPages || 1);
        setTotal(payload.total || 0);
      })
      .catch((err) => setError(err.message || 'Không thể tải nhật ký kiểm tra.'))
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    loadPage(1);
  }, [loadPage]);

  const handleToggle = (id) => {
    setExpandedId((prev) => (prev === id ? null : id));
  };

  const handleSearch = (e) => {
    e.preventDefault();
    setSearch(searchInput);
  };

  const handleSearchKeyDown = (e) => {
    if (e.key === 'Escape') {
      setSearchInput('');
      setSearch('');
    }
  };

  const filteredEvents = events.filter((event) => {
    if (filter && !event.targetType?.toLowerCase().includes(filter.toLowerCase()) && !event.action?.toLowerCase().includes(filter.toLowerCase())) {
      return false;
    }
    if (search) {
      const q = search.toLowerCase();
      const matchActor = event.actorUsername?.toLowerCase().includes(q);
      const matchTarget = event.targetId?.toString().toLowerCase().includes(q);
      const matchAction = event.action?.toLowerCase().includes(q);
      const matchMeta = event.metadata
        ? Object.values(event.metadata).some((v) => String(v).toLowerCase().includes(q))
        : false;
      if (!matchActor && !matchTarget && !matchAction && !matchMeta) return false;
    }
    return true;
  });

  return (
    <section className="page">
      <PageHeader
        title="Audit Log"
        description={`${total} hành động kiểm duyệt — theo dõi trách nhiệm và tuân thủ bảo vệ trẻ em.`}
      />

      <div className="audit-toolbar">
        <form className="audit-search" onSubmit={handleSearch}>
          <input
            type="text"
            placeholder="Tìm theo username, action, ID..."
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            onKeyDown={handleSearchKeyDown}
          />
          {searchInput && (
            <button type="button" className="audit-search-clear" onClick={() => { setSearchInput(''); setSearch(''); }}>
              ✕
            </button>
          )}
          <button type="submit" className="ghost-button">Tìm</button>
        </form>
        <div className="audit-filters">
          {FILTER_OPTIONS.map((opt) => (
            <button
              key={opt.value}
              className={`audit-filter-btn ${filter === opt.value ? 'active' : ''}`}
              onClick={() => setFilter(filter === opt.value ? '' : opt.value)}
            >
              {opt.label}
            </button>
          ))}
        </div>
      </div>

      {error && <div className="form-error">{error}</div>}

      {loading && <div className="audit-loading">Đang tải...</div>}

      {!loading && filteredEvents.length === 0 && !error && (
        <div className="panel">
          <p className="audit-empty">
            {search || filter ? 'Không tìm thấy hành động nào phù hợp.' : 'Chưa có hành động kiểm duyệt nào được ghi lại.'}
          </p>
        </div>
      )}

      {!loading && filteredEvents.length > 0 && (
        <>
          <div className="audit-list">
            {filteredEvents.map((event) => (
              <AuditCard
                key={event.id || event._id}
                event={event}
                expanded={expandedId === (event.id || event._id)}
                onToggle={() => handleToggle(event.id || event._id)}
              />
            ))}
          </div>

          {totalPages > 1 && (
            <div className="audit-pagination">
              <button
                className="ghost-button"
                disabled={page <= 1}
                onClick={() => {
                  const prev = page - 1;
                  setPage(prev);
                  loadPage(prev);
                  setExpandedId(null);
                  window.scrollTo({ top: 0, behavior: 'smooth' });
                }}
              >
                ← Trước
              </button>
              <span className="audit-page-info">
                Trang {page} / {totalPages} &nbsp;|&nbsp; {total} tổng số
              </span>
              <button
                className="ghost-button"
                disabled={page >= totalPages}
                onClick={() => {
                  const next = page + 1;
                  setPage(next);
                  loadPage(next);
                  setExpandedId(null);
                  window.scrollTo({ top: 0, behavior: 'smooth' });
                }}
              >
                Sau →
              </button>
            </div>
          )}
        </>
      )}
    </section>
  );
}
