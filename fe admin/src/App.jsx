import { useMemo, useState } from 'react';
import AdminLayout from './components/AdminLayout';
import AuditPage from './pages/AuditPage';
import BadgesPage from './pages/BadgesPage';
import ContentPage from './pages/ContentPage';
import DashboardPage from './pages/DashboardPage';
import GroupsPage from './pages/GroupsPage';
import LoginPage from './pages/LoginPage';
import MediaPage from './pages/MediaPage';
import MessagesPage from './pages/MessagesPage';
import NotificationsPage from './pages/NotificationsPage';
import ReportsPage from './pages/ReportsPage';
import SafetyPage from './pages/SafetyPage';
import SupportPage from './pages/SupportPage';
import UsersPage from './pages/UsersPage';

export default function App() {
  const [activePage, setActivePage] = useState('dashboard');
  const [adminUser, setAdminUser] = useState(() => {
    const stored = localStorage.getItem('admin_user');
    if (!stored) return null;
    try {
      return JSON.parse(stored);
    } catch {
      return null;
    }
  });

  const page = useMemo(() => {
    switch (activePage) {
      case 'content':
        return <ContentPage />;
      case 'reports':
        return <ReportsPage />;
      case 'users':
        return <UsersPage />;
      case 'groups':
        return <GroupsPage />;
      case 'messages':
        return <MessagesPage />;
      case 'support':
        return <SupportPage />;
      case 'notifications':
        return <NotificationsPage />;
      case 'badges':
        return <BadgesPage />;
      case 'media':
        return <MediaPage />;
      case 'safety':
        return <SafetyPage />;
      case 'audit':
        return <AuditPage />;
      default:
        return <DashboardPage onNavigate={setActivePage} />;
    }
  }, [activePage]);

  if (!adminUser) {
    return (
      <LoginPage
        onLogin={(user) => {
          localStorage.setItem('admin_user', JSON.stringify(user));
          setAdminUser(user);
        }}
      />
    );
  }

  return (
    <AdminLayout
      activePage={activePage}
      onNavigate={setActivePage}
      adminUser={adminUser}
      onLogout={() => {
        localStorage.removeItem('admin_token');
        localStorage.removeItem('admin_user');
        setAdminUser(null);
      }}
    >
      {page}
    </AdminLayout>
  );
}
