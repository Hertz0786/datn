import { useEffect, useState } from 'react';
import PageHeader from '../components/PageHeader';
import StatusBadge from '../components/StatusBadge';
import { api } from '../services/api';

const SOURCE_LABEL = {
  AVATAR: 'Profile avatar',
  POST: 'Post attachment',
  COVER: 'Cover photo',
  CHAT: 'Chat attachment',
};

export default function MediaPage() {
  const [media, setMedia] = useState([]);
  const [error, setError] = useState('');

  useEffect(() => {
    setError('');
    api
      .listMedia()
      .then((payload) => setMedia(payload.items || []))
      .catch((err) => setError(err.message || 'Failed to load media.'));
  }, []);

  function setStatus(id, status) {
    api
      .updateMediaStatus(id, status)
      .then(() => {
        setMedia((items) =>
          items.map((item) => ((item.id || item._id) === id ? { ...item, status } : item)),
        );
      })
      .catch((err) => setError(err.message || 'Failed to update media.'));
  }

  function isVideo(item) {
    if (item.resourceType === 'video') return true;
    const url = (item.url || '').toLowerCase();
    return (
      url.includes('/video/upload/') ||
      url.endsWith('.mp4') ||
      url.endsWith('.mov') ||
      url.endsWith('.webm')
    );
  }

  return (
    <section className="page">
      <PageHeader
        title="Media library"
        description="Review profile and post images before they spread across the app."
      />
      {error && <div className="form-error">{error}</div>}
      <div className="media-grid">
        {media.length === 0 && <p>No media found.</p>}
        {media.map((item) => {
          const id = (item.id || item._id || '').toString();
          const sourceLabel = SOURCE_LABEL[item.source] || item.source || 'Unknown';
          return (
            <article className="media-card" key={id}>
              {item.url ? (
                isVideo(item) ? (
                  <div className="video-thumb">
                    <span>▶</span>
                    <small>{sourceLabel}</small>
                  </div>
                ) : (
                  <img src={item.url} alt={item.owner || 'media'} loading="lazy" />
                )
              ) : (
                <div className="video-thumb">
                  <span>📁</span>
                  <small>{sourceLabel}</small>
                </div>
              )}
              <div>
                <strong>{item.owner || '—'}</strong>
                <span>{sourceLabel}</span>
                <StatusBadge value={item.status} />
              </div>
              <div className="button-row">
                <button onClick={() => setStatus(id, 'APPROVED')}>Approve</button>
                <button className="danger" onClick={() => setStatus(id, 'REMOVED')}>Remove</button>
              </div>
            </article>
          );
        })}
      </div>
    </section>
  );
}
