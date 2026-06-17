import { useEffect, useState } from 'react';
import PageHeader from '../components/PageHeader';
import StatusBadge from '../components/StatusBadge';
import { api } from '../services/api';

const DEFAULT_TOPIC = 'Drawing';

export default function GroupsPage() {
  const [groups, setGroups] = useState([]);
  const [error, setError] = useState('');
  const [showForm, setShowForm] = useState(false);
  const [name, setName] = useState('');
  const [topic, setTopic] = useState(DEFAULT_TOPIC);
  const [description, setDescription] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    setError('');
    api
      .listGroups()
      .then((payload) => setGroups(payload.items || []))
      .catch((err) => setError(err.message || 'Failed to load groups.'));
  }, []);

  function toggleGroup(id) {
    const current = groups.find((group) => (group.id || group._id) === id);
    if (!current) return;
    const nextStatus = current.status === 'ACTIVE' ? 'PAUSED' : 'ACTIVE';
    api
      .updateGroupStatus(id, nextStatus)
      .then(() => {
        setGroups((items) =>
          items.map((group) =>
            (group.id || group._id) === id ? { ...group, status: nextStatus } : group,
          ),
        );
      })
      .catch((err) => setError(err.message || 'Failed to update group.'));
  }

  async function createGroup(event) {
    event.preventDefault();
    if (!name.trim() || !topic.trim()) return;
    setSaving(true);
    setError('');
    try {
      await api.createGroup({
        name: name.trim(),
        topic: topic.trim(),
        description: description.trim() || `Admin-created ${topic.trim()} group`,
      });
      const payload = await api.listGroups();
      setGroups(payload.items || []);
      setShowForm(false);
      setName('');
      setTopic(DEFAULT_TOPIC);
      setDescription('');
    } catch (err) {
      setError(err.message || 'Failed to create group.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <section className="page">
      <PageHeader
        title="Groups"
        description="Manage child-safe communities, age ranges, topics and membership health."
        action={
          <button className="primary-button" onClick={() => setShowForm((v) => !v)}>
            {showForm ? 'Cancel' : 'Create group'}
          </button>
        }
      />
      {error && <div className="form-error">{error}</div>}

      {showForm && (
        <form className="panel form-panel" onSubmit={createGroup}>
          <h2>New group</h2>
          <label>
            Name
            <input
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder="e.g. Young Coders"
              required
            />
          </label>
          <label>
            Topic
            <input
              value={topic}
              onChange={(event) => setTopic(event.target.value)}
              placeholder="e.g. Coding"
              required
            />
          </label>
          <label>
            Description
            <textarea
              value={description}
              onChange={(event) => setDescription(event.target.value)}
              placeholder="What is this group about?"
            />
          </label>
          <button className="primary-button" type="submit" disabled={saving}>
            {saving ? 'Creating...' : 'Create group'}
          </button>
        </form>
      )}

      <div className="card-grid">
        {groups.length === 0 && <p>No groups found.</p>}
        {groups.map((group) => {
          const id = (group.id || group._id || '').toString();
          return (
            <article className="panel group-card" key={id}>
              <div className="panel-header">
                <h2>{group.name}</h2>
                <StatusBadge value={group.status} />
              </div>
              <p>
                {group.topic}
                {group.ageRange ? ` / ${group.ageRange} years old` : ''}
              </p>
              {group.description && <p>{group.description}</p>}
              <div className="detail-grid">
                <span>Members</span>
                <strong>{group.members ?? 0}</strong>
                <span>Owner</span>
                <strong>{group.owner || '—'}</strong>
              </div>
              <button onClick={() => toggleGroup(id)}>
                {group.status === 'ACTIVE' ? 'Pause group' : 'Resume group'}
              </button>
            </article>
          );
        })}
      </div>
    </section>
  );
}
