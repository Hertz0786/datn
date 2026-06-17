import { useState } from 'react';
import PageHeader from '../components/PageHeader';
import { api } from '../services/api';

export default function NotificationsPage() {
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [audience, setAudience] = useState('ALL');
  const [history, setHistory] = useState([]);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  async function sendNotification(event) {
    event.preventDefault();
    if (!title.trim() || !body.trim()) return;
    setSending(true);
    setError('');
    setSuccess('');
    try {
      const payload = await api.broadcastNotification({ title, body, audience });
      setHistory((items) => [
        {
          id: Date.now(),
          title,
          body,
          audience,
          count: payload.count || 0,
          time: new Date().toLocaleString(),
        },
        ...items,
      ]);
      setTitle('');
      setBody('');
      setSuccess(`Queued for ${payload.count || 0} users.`);
    } catch (err) {
      setError(err.message || 'Failed to send notification.');
    } finally {
      setSending(false);
    }
  }

  return (
    <section className="page">
      <PageHeader
        title="Notifications"
        description="Create system announcements for children, moderators or specific age bands."
      />
      {error && <div className="form-error">{error}</div>}
      {success && <div className="form-success">{success}</div>}
      <div className="split-grid">
        <form className="panel form-panel" onSubmit={sendNotification}>
          <label>Title<input value={title} onChange={(event) => setTitle(event.target.value)} /></label>
          <label>Message<textarea value={body} onChange={(event) => setBody(event.target.value)} /></label>
          <label>Audience
            <select value={audience} onChange={(event) => setAudience(event.target.value)}>
              <option value="ALL">All users</option>
              <option value="CHILDREN">Children</option>
              <option value="MODERATORS">Moderators</option>
              <option value="AGE_7_10">Age 7-10</option>
              <option value="AGE_11_14">Age 11-14</option>
            </select>
          </label>
          <button className="primary-button" disabled={sending}>
            {sending ? 'Queueing...' : 'Queue notification'}
          </button>
        </form>
        <div className="panel">
          <h2>Recent announcements</h2>
          <div className="stack">
            {history.length === 0 && <p>No announcements queued yet.</p>}
            {history.map((item) => (
              <div className="review-card" key={item.id}>
                <div>
                  <strong>{item.title}</strong>
                  <p>{item.body}</p>
                </div>
                <span>{item.audience} / {item.count} users</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
