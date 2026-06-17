import { useEffect, useState } from 'react';
import PageHeader from '../components/PageHeader';
import { api } from '../services/api';

export default function AuditPage() {
  const [events, setEvents] = useState([]);
  const [error, setError] = useState('');

  useEffect(() => {
    setError('');
    api
      .listAudit()
      .then((payload) => setEvents(payload.items || []))
      .catch((err) => setError(err.message || 'Failed to load audit log.'));
  }, []);

  return (
    <section className="page">
      <PageHeader
        title="Audit log"
        description="Track moderator actions for accountability and child safety compliance."
      />
      {error && <div className="form-error">{error}</div>}
      <div className="panel">
        <div className="stack">
          {events.length === 0 && <p>No audit events.</p>}
          {events.map((event) => (
            <div className="timeline-item" key={event.id || event._id}>
              <span>{new Date(event.createdAt).toLocaleString()}</span>
              <strong className="audit-actor">{event.actorUsername || event.actorId || '—'}</strong>
              <p className="audit-action">{event.action}</p>
              {event.targetType && (
                <span className="audit-target">
                  {event.targetType}{event.targetId ? `/${event.targetId}` : ''}
                </span>
              )}
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
