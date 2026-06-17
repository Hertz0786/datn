import { useEffect, useState } from 'react';
import PageHeader from '../components/PageHeader';
import StatusBadge from '../components/StatusBadge';
import { api } from '../services/api';

export default function BadgesPage() {
  const [badges, setBadges] = useState([]);
  const [error, setError] = useState('');
  // Local-only toggle: there is no PATCH /admin/badges endpoint yet,
  // so this just reflects what would happen on the server and warns
  // the admin that nothing was actually persisted.
  const [hint, setHint] = useState('');

  useEffect(() => {
    setError('');
    api
      .listBadges()
      .then((payload) => setBadges(payload.items || []))
      .catch((err) => setError(err.message || 'Failed to load badges.'));
  }, []);

  function toggleBadge(id) {
    setBadges((items) =>
      items.map((badge) =>
        badge.id === id ? { ...badge, enabled: !badge.enabled } : badge,
      ),
    );
    setHint('Badge status is read-only right now — backend persistence is not wired up.');
  }

  return (
    <section className="page">
      <PageHeader
        title="Badge rules"
        description="Manage gamified achievements and safety-positive rewards."
        action={<button className="primary-button" disabled>New badge</button>}
      />
      {error && <div className="form-error">{error}</div>}
      {hint && <div className="form-success">{hint}</div>}
      <div className="card-grid">
        {badges.length === 0 && <p>No badges found.</p>}
        {badges.map((badge) => (
          <article className="panel" key={badge.id}>
            <div className="panel-header">
              <h2>{badge.name}</h2>
              <StatusBadge value={badge.enabled ? 'ENABLED' : 'DISABLED'} />
            </div>
            <p>{badge.rule}</p>
            <strong>{badge.earned ?? 0} children earned</strong>
            <button onClick={() => toggleBadge(badge.id)}>
              {badge.enabled ? 'Disable' : 'Enable'}
            </button>
          </article>
        ))}
      </div>
    </section>
  );
}
