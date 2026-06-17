import { useEffect, useState } from 'react';
import PageHeader from '../components/PageHeader';
import StatusBadge from '../components/StatusBadge';
import { api } from '../services/api';

export default function MessagesPage() {
  const [messages, setMessages] = useState([]);
  const [error, setError] = useState('');

  useEffect(() => {
    let active = true;
    setError('');
    api
      .listMessages()
      .then((payload) => {
        if (active) setMessages(payload.items || []);
      })
      .catch((err) => {
        if (active) setError(err.message || 'Failed to load messages.');
      });
    return () => { active = false; };
  }, []);

  function markSafe(id) {
    api.updateMessageStatus(id, 'SENT').catch(() => {});
    setMessages((items) =>
      items.map((m) => ((m.id || m._id) === id ? { ...m, status: 'SAFE' } : m)),
    );
  }

  function markRemoved(id) {
    api.updateMessageStatus(id, 'REMOVED').catch(() => {});
    setMessages((items) =>
      items.map((m) => ((m.id || m._id) === id ? { ...m, status: 'REMOVED' } : m)),
    );
  }

  function formatTime(value) {
    if (!value) return '';
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? value : parsed.toLocaleString();
  }

  return (
    <section className="page">
      <PageHeader
        title="Chat moderation"
        description="Review flagged chat snippets and detect private information requests."
      />
      {error && <div className="form-error">{error}</div>}
      <div className="table-card">
        <table>
          <thead>
            <tr>
              <th>Sender</th>
              <th>Snippet</th>
              <th>Severity</th>
              <th>Status</th>
              <th>Time</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {messages.length === 0 && (
              <tr>
                <td colSpan="6">No messages found.</td>
              </tr>
            )}
            {messages.map((message) => {
              const id = message.id || message._id;
              return (
                <tr key={id}>
                  <td>{message.sender || '—'}</td>
                  <td className="wide-cell">{message.snippet || message.content || '—'}</td>
                  <td><StatusBadge value={message.severity} /></td>
                  <td><StatusBadge value={message.status} /></td>
                  <td>{formatTime(message.createdAt)}</td>
                  <td className="actions">
                    <button onClick={() => markSafe(id)}>Safe</button>
                    <button className="danger" onClick={() => markRemoved(id)}>Remove</button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </section>
  );
}
