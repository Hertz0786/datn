const navItems = [
  ['dashboard', 'Dashboard', 'DB'],
  ['content', 'Posts & Comments', 'PC'],
  ['reports', 'Reports', 'RP'],
  ['users', 'Users', 'US'],
  ['groups', 'Groups', 'GR'],
  ['messages', 'Chats', 'CH'],
  ['support', 'Support', 'SOS'],
  ['notifications', 'Notifications', 'NT'],
  ['badges', 'Badges', 'BD'],
  ['media', 'Media', 'MD'],
  ['safety', 'Safety Rules', 'SR'],
  ['audit', 'Audit Log', 'AU'],
];

export default function AdminLayout({ activePage, onNavigate, children, onLogout, adminUser }) {
  return (
    <div className="admin-shell">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-mark">K</div>
          <div>
            <strong>Kiddo Admin</strong>
            <span>Child-safe social ops</span>
          </div>
        </div>
        <nav>
          {navItems.map(([key, label, icon]) => (
            <button
              key={key}
              className={activePage === key ? 'active' : ''}
              onClick={() => onNavigate(key)}
            >
              <span>{icon}</span>
              {label}
            </button>
          ))}
        </nav>
      </aside>
      <main className="main">
        <header className="topbar">
          <div>
            <strong>Admin console</strong>
            <span>Review, moderate and protect children in real time.</span>
          </div>
          <div className="topbar-actions">
            <span className="topbar-user">
              {adminUser?.displayName || adminUser?.username || 'Admin'}
            </span>
            <button className="ghost-button" onClick={onLogout}>Logout</button>
          </div>
        </header>
        {children}
      </main>
    </div>
  );
}
