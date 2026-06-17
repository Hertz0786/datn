import { useEffect, useState } from 'react';
import PageHeader from '../components/PageHeader';
import StatusBadge from '../components/StatusBadge';
import { api } from '../services/api';

export default function UsersPage() {
  const [users, setUsers] = useState([]);
  const [query, setQuery] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    let active = true;
    const timer = setTimeout(() => {
      setError('');
      api
        .listUsers(query)
        .then((payload) => {
          if (active) setUsers(payload.items || []);
        })
        .catch((err) => {
          if (active) setError(err.message || 'Failed to load users.');
        });
    }, 250);
    return () => {
      active = false;
      clearTimeout(timer);
    };
  }, [query]);

  const visibleUsers = users.filter((user) =>
    `${user.name || user.displayName || ''} ${user.username || ''}`
      .toLowerCase()
      .includes(query.toLowerCase()),
  );

  function setStatus(id, status) {
    api
      .updateUserStatus(id, status)
      .then(() => {
        setUsers((items) =>
          items.map((user) => ((user.id || user._id) === id ? { ...user, status } : user)),
        );
      })
      .catch((err) => setError(err.message || 'Failed to update user status.'));
  }

  return (
    <section className="page">
      <PageHeader
        title="User management"
        description="Search children accounts, monitor risk and apply safety restrictions."
        action={<input placeholder="Search users..." value={query} onChange={(event) => setQuery(event.target.value)} />}
      />
      {error && <div className="form-error">{error}</div>}
      <div className="table-card">
        <table>
          <thead>
            <tr>
              <th>Name</th>
              <th>Age</th>
              <th>Friends</th>
              <th>Posts</th>
              <th>Risk</th>
              <th>Status</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {visibleUsers.length === 0 && (
              <tr>
                <td colSpan="7">No users found.</td>
              </tr>
            )}
            {visibleUsers.map((user) => (
              <tr key={user.id || user._id}>
                <td>{user.name || user.displayName}<small>@{user.username}</small></td>
                <td>{user.age}</td>
                <td>{user.friends}</td>
                <td>{user.posts}</td>
                <td><StatusBadge value={user.risk} /></td>
                <td><StatusBadge value={user.status} /></td>
                <td className="actions">
                  <button onClick={() => setStatus(user.id || user._id, 'ACTIVE')}>Activate</button>
                  <button onClick={() => setStatus(user.id || user._id, 'WATCHLIST')}>Watch</button>
                  <button className="danger" onClick={() => setStatus(user.id || user._id, 'SUSPENDED')}>Suspend</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
