import { useEffect, useState, useCallback } from 'react';
import PageHeader from '../components/PageHeader';
import StatusBadge from '../components/StatusBadge';
import { api } from '../services/api';

export default function SupportPage() {
  const [threads, setThreads] = useState([]);
  const [selected, setSelected] = useState(null);
  const [messages, setMessages] = useState([]);
  const [reply, setReply] = useState('');
  const [statusFilter, setStatusFilter] = useState('ALL');
  const [error, setError] = useState('');

  const loadThreads = useCallback((status = statusFilter) => {
    api
      .listSupportThreads(status)
      .then((payload) => {
        const items = payload.items || [];
        setThreads(items);
        // Only auto-select if nothing is selected yet.
        setSelected((current) => current || items[0] || null);
      })
      .catch((err) => setError(err.message || 'Failed to load support threads.'));
  }, [statusFilter]);

  useEffect(() => {
    setError('');
    loadThreads(statusFilter);
  }, [statusFilter, loadThreads]);

  useEffect(() => {
    if (!selected?.id) return;
    setError('');
    api
      .listSupportMessages(selected.id)
      .then((payload) => {
        setSelected(payload.thread || selected);
        setMessages(payload.messages || []);
      })
      .catch((err) => setError(err.message || 'Failed to load support messages.'));
  }, [selected?.id]);

  function sendReply(event) {
    event.preventDefault();
    const content = reply.trim();
    if (!selected?.id || !content) return;
    setReply('');
    api
      .replySupport(selected.id, content)
      .then((payload) => {
        setMessages((items) => [...items, payload.message]);
        setSelected(payload.thread || selected);
        loadThreads();
      })
      .catch((err) => setError(err.message || 'Failed to send reply.'));
  }

  function setThreadStatus(status) {
    if (!selected?.id) return;
    api
      .updateSupportStatus(selected.id, status)
      .then((payload) => {
        setSelected(payload.thread || selected);
        setThreads((items) =>
          items.map((item) => {
            const sid = item.id || item._id;
            return sid === selected.id ? { ...item, status } : item;
          }),
        );
      })
      .catch((err) => setError(err.message || 'Failed to update support status.'));
  }

  function formatTime(value) {
    if (!value) return '';
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? value : parsed.toLocaleString();
  }

  const selectedId = selected ? (selected.id || selected._id || '').toString() : '';

  return (
    <section className="page">
      <PageHeader
        title="Admin support"
        description="Reply to children who need help with safety, account issues, or app problems."
        action={
          <select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)}>
            <option value="ALL">All</option>
            <option value="OPEN">Open</option>
            <option value="PENDING_USER">Pending user</option>
            <option value="RESOLVED">Resolved</option>
          </select>
        }
      />
      {error && <div className="form-error">{error}</div>}
      <div className="support-grid">
        <div className="panel list-panel">
          {threads.length === 0 && <p>No support requests.</p>}
          {threads.map((thread) => {
            const tid = (thread.id || thread._id || '').toString();
            const threadUser = thread.user;
            return (
              <button
                key={tid}
                className={`list-row ${tid === selectedId ? 'selected' : ''}`}
                onClick={() => setSelected(thread)}
              >
                <div>
                  <strong>{thread.subject}</strong>
                  <span>
                    {threadUser?.displayName || threadUser?.username || 'Unknown user'} / {thread.category}
                  </span>
                  <small>{thread.lastMessage?.content || 'No messages yet'}</small>
                </div>
                <StatusBadge value={thread.status} />
              </button>
            );
          })}
        </div>
        <div className="panel support-detail">
          {selected ? (
            <>
              <div className="panel-header">
                <div>
                  <h2>{selected.subject}</h2>
                  <p>
                    {selected.user?.displayName || selected.user?.username || 'Unknown user'} /{' '}
                    {selected.category}
                  </p>
                </div>
                <StatusBadge value={selected.status} />
              </div>
              <div className="support-messages">
                {messages.length === 0 && <p style={{ color: '#637392', textAlign: 'center', padding: '24px' }}>No messages in this thread.</p>}
                {messages.map((message) => (
                  <div
                    key={message.id || message._id}
                    className={`support-message ${
                      message.senderRole === 'ADMIN' ? 'admin-message' : 'user-message'
                    }`}
                  >
                    <strong>{message.senderRole === 'ADMIN' ? 'Admin' : 'User'}</strong>
                    <p>{message.content}</p>
                    <span>{formatTime(message.createdAt)}</span>
                  </div>
                ))}
              </div>
              <form className="support-reply" onSubmit={sendReply}>
                <textarea
                  value={reply}
                  onChange={(event) => setReply(event.target.value)}
                  placeholder="Write a helpful, child-safe reply..."
                />
                <div className="button-row">
                  <button type="button" onClick={() => setThreadStatus('OPEN')}>Mark open</button>
                  <button type="button" onClick={() => setThreadStatus('RESOLVED')}>Resolve</button>
                  <button className="primary-button" type="submit">Send reply</button>
                </div>
              </form>
            </>
          ) : (
            <p style={{ color: '#637392', textAlign: 'center', padding: '24px' }}>Select a support request to read and reply.</p>
          )}
        </div>
      </div>
    </section>
  );
}
