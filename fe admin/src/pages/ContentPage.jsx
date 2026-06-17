import { useEffect, useState } from 'react';
import PageHeader from '../components/PageHeader';
import StatusBadge from '../components/StatusBadge';
import { api } from '../services/api';

// The Post collection only has 3 statuses: PUBLISHED / HIDDEN /
// DELETED. We expose them as a filter and alias the human label
// "Flagged" → HIDDEN because that is the status a post ends up
// in after the moderation pipeline flags it. The previous version
// sent `status=FLAGGED` to the backend which returned zero rows and
// looked like a bug.
const STATUS_OPTIONS = [
  { value: '', label: 'All statuses' },
  { value: 'PENDING_REVIEW', label: 'Awaiting media review' },
  { value: 'PUBLISHED', label: 'Published' },
  { value: 'HIDDEN', label: 'Flagged / Hidden' },
  { value: 'DELETED', label: 'Deleted' },
];

const AUDIENCE_LABEL = {
  PUBLIC: 'Public',
  FRIENDS: 'Friends only',
  GROUP: 'Group',
};

function formatTime(value) {
  if (!value) return '';
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? value : parsed.toLocaleString();
}

function MediaPreview({ urls }) {
  // A post can have up to a handful of attachments. We render the
  // first four as small thumbnails so the admin can see at a glance
  // whether the post is image-heavy / video-heavy / has nothing.
  if (!urls || urls.length === 0) {
    return <span className="media-empty">—</span>;
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

function PostDetailModal({ post, onClose, onUpdateStatus }) {
  // Lazy-load the comment list when the modal opens. We keep the
  // raw post on the parent so the admin can still act on it from
  // inside the modal (hide / delete the post while reviewing).
  const [comments, setComments] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!post) return undefined;
    let active = true;
    setLoading(true);
    setError('');
    api
      .listComments(post.id || post._id)
      .then((payload) => {
        if (active) setComments(payload.items || []);
      })
      .catch((err) => {
        if (active) setError(err.message || 'Failed to load comments.');
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [post]);

  if (!post) return null;
  const id = post.id || post._id;

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-panel" onClick={(event) => event.stopPropagation()}>
        <header className="modal-header">
          <div>
            <h2>{post.pendingMediaReview ? 'Review post' : 'Post details'}</h2>
            <small>
              by {post.author || '—'} ·{' '}
              {post.createdAt ? formatTime(post.createdAt) : ''}
            </small>
          </div>
          <button className="ghost-button" onClick={onClose}>Close</button>
        </header>

        {post.pendingMediaReview && (
          <div className="review-banner">
            <strong>Sensitive image detected</strong>
            <span>
              {post.mediaModerationLabel
                ? `AI label: ${post.mediaModerationLabel} · `
                : ''}
              score {Number(post.mediaModerationScore || 0).toFixed(2)}
            </span>
            <p>
              The post was auto-hidden because the image score crossed
              the safe-publish threshold. Approve to publish it on the
              feed, or delete to remove it.
            </p>
          </div>
        )}

        <section className="modal-post">
          <p>{post.content || '—'}</p>
          <MediaPreview urls={post.mediaUrls} />
          <div className="modal-post-actions">
            <StatusBadge value={post.status} />
            <button onClick={() => onUpdateStatus(id, 'PUBLISHED')}>Approve</button>
            <button onClick={() => onUpdateStatus(id, 'HIDDEN')}>Hide</button>
            <button className="danger" onClick={() => onUpdateStatus(id, 'DELETED')}>Delete</button>
          </div>
        </section>

        <section className="modal-comments">
          <h3>Comments ({post.comments ?? comments.length})</h3>
          {loading && <p>Loading comments…</p>}
          {error && <div className="form-error">{error}</div>}
          {!loading && comments.length === 0 && (
            <p className="muted">No comments yet for this post.</p>
          )}
          <ul className="comment-list">
            {comments.map((comment) => {
              const cid = comment.id || comment._id;
              const cstatus = (comment.status || 'PUBLISHED').toLowerCase();
              return (
                <li key={cid} className={`comment-item status-${cstatus}`}>
                  <header>
                    <strong>{comment.author || '—'}</strong>
                    <small>
                      {comment.createdAt ? formatTime(comment.createdAt) : ''}
                    </small>
                    <StatusBadge value={comment.status} />
                  </header>
                  <p>{comment.content || '—'}</p>
                </li>
              );
            })}
          </ul>
        </section>
      </div>
    </div>
  );
}

export default function ContentPage() {
  const [posts, setPosts] = useState([]);
  const [filter, setFilter] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [selected, setSelected] = useState(null);

  useEffect(() => {
    let active = true;
    setError('');
    setLoading(true);
    // PENDING_REVIEW is a synthetic filter that the backend maps to
    // `pendingMediaReview = true && status = HIDDEN`. We translate it
    // here so the rest of the page does not need to know about the
    // synthetic value.
    const queryStatus = filter === 'PENDING_REVIEW' ? 'HIDDEN' : filter;
    api
      .listPosts(queryStatus, filter === 'PENDING_REVIEW')
      .then((payload) => {
        if (active) setPosts(payload.items || []);
      })
      .catch((err) => {
        if (active) setError(err.message || 'Failed to load posts.');
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [filter]);

  function updateStatus(id, status) {
    // Optimistic UI update so the table reacts instantly; we
    // re-sync from the server on error to avoid a stale row.
    const previous = posts;
    setPosts((items) =>
      items.map((post) => {
        if ((post.id || post._id) !== id) {
          return post;
        }
        return {
          ...post,
          status,
          // Once the admin has decided, the post is no longer
          // pending review. Keep it HIDDEN only if the admin chose
          // HIDDEN explicitly.
          pendingMediaReview: status === 'HIDDEN',
        };
      }),
    );
    setSelected((post) => {
      if (!post || (post.id || post._id) !== id) {
        return post;
      }
      return { ...post, status, pendingMediaReview: status === 'HIDDEN' };
    });
    api
      .updatePostStatus(id, status)
      .catch((err) => {
        setError(err.message || 'Failed to update post status.');
        setPosts(previous);
      });
  }

  return (
    <section className="page">
      <PageHeader
        title="Posts & comments"
        description="Review posts, hide unsafe content and inspect engagement signals."
        action={
          <select value={filter} onChange={(event) => setFilter(event.target.value)}>
            {STATUS_OPTIONS.map((opt) => (
              <option key={opt.value} value={opt.value}>
                {opt.label}
              </option>
            ))}
          </select>
        }
      />
      {error && <div className="form-error">{error}</div>}
      <div className="table-card">
        <table>
          <thead>
            <tr>
              <th>Author</th>
              <th>Content</th>
              <th>Media</th>
              <th>Topics</th>
              <th>Audience</th>
              <th>Engagement</th>
              <th>Risk</th>
              <th>Status</th>
              <th>Created</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {!loading && posts.length === 0 && (
              <tr>
                <td colSpan="10">No posts found.</td>
              </tr>
            )}
            {loading && (
              <tr>
                <td colSpan="10">Loading…</td>
              </tr>
            )}
            {posts.map((post) => {
              const id = post.id || post._id;
              const isReview = post.pendingMediaReview;
              return (
                <tr key={id} className={isReview ? 'row-review' : ''}>
                  <td>
                    {post.author || '—'}
                    <small>
                      {post.authorId ? `@${post.authorId.slice(-6)}` : 'age —'}
                    </small>
                  </td>
                  <td className="wide-cell">
                    {post.content || '—'}
                    {isReview && (
                      <span className="review-pill">
                        🛡 review · score {Number(post.mediaModerationScore || 0).toFixed(2)}
                      </span>
                    )}
                    {post.comments > 0 && (
                      <button
                        type="button"
                        className="link-button"
                        onClick={() => setSelected(post)}
                      >
                        💬 {post.comments} comment{post.comments === 1 ? '' : 's'}
                      </button>
                    )}
                  </td>
                  <td><MediaPreview urls={post.mediaUrls} /></td>
                  <td>{(post.topics || []).join(', ') || '—'}</td>
                  <td>{AUDIENCE_LABEL[post.visibility] || post.visibility || '—'}</td>
                  <td>
                    {post.reactions ?? 0} likes / {post.comments ?? 0} comments
                  </td>
                  <td><StatusBadge value={post.risk || 'LOW'} /></td>
                  <td>
                    <StatusBadge value={post.status} />
                    {isReview && <small>needs review</small>}
                  </td>
                  <td><small>{formatTime(post.createdAt)}</small></td>
                  <td className="actions">
                    <button onClick={() => setSelected(post)}>Review</button>
                    <button onClick={() => updateStatus(id, 'PUBLISHED')}>Approve</button>
                    <button onClick={() => updateStatus(id, 'HIDDEN')}>Hide</button>
                    <button className="danger" onClick={() => updateStatus(id, 'DELETED')}>Delete</button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      {selected && (
        <PostDetailModal
          post={selected}
          onClose={() => setSelected(null)}
          onUpdateStatus={updateStatus}
        />
      )}
    </section>
  );
}
