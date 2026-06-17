const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || 'http://127.0.0.1:5000';

function authHeaders() {
  const token = localStorage.getItem('admin_token');
  return token ? { Authorization: `Bearer ${token}` } : {};
}

async function request(path, options = {}) {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...authHeaders(),
      ...(options.headers || {}),
    },
  });

  const text = await response.text();
  const payload = text ? JSON.parse(text) : {};

  if (!response.ok) {
    throw new Error(payload.message || 'Request failed');
  }

  return payload;
}

export const api = {
  login: (username, password) =>
    request('/api/auth/login', {
      method: 'POST',
      body: JSON.stringify({ username, password }),
    }),
  getDashboard: () => request('/api/admin/dashboard'),
  listReports: (status = '') =>
    request(`/api/admin/reports${status && status !== 'ALL' ? `?status=${status}` : ''}`),
  updateReport: (reportId, status) =>
    request(`/api/admin/reports/${reportId}`, {
      method: 'PATCH',
      body: JSON.stringify({ status }),
    }),
  listUsers: (query = '') => request(`/api/admin/users${query ? `?q=${query}` : ''}`),
  updateUserStatus: (userId, status) =>
    request(`/api/admin/users/${userId}/status`, {
      method: 'PATCH',
      body: JSON.stringify({ status }),
    }),
  listPosts: (status = '', pendingOnly = false) => {
    // `pendingOnly = true` is a server-side shortcut for the admin
    // "awaiting media review" queue. We only attach it when no
    // explicit status is provided so the filter dropdown still works
    // for the other tabs.
    const params = [];
    if (status && status !== 'ALL') {
      params.push(`status=${encodeURIComponent(status)}`);
    } else if (pendingOnly) {
      params.push('pending=1');
    }
    const suffix = params.length ? `?${params.join('&')}` : '';
    return request(`/api/admin/posts${suffix}`);
  },
  updatePostStatus: (postId, status) =>
    request(`/api/admin/posts/${postId}/status`, {
      method: 'PATCH',
      body: JSON.stringify({ status }),
    }),
  listComments: (postId = '') =>
    request(`/api/admin/comments${postId ? `?postId=${postId}` : ''}`),
  updateCommentStatus: (commentId, status) =>
    request(`/api/admin/comments/${commentId}/status`, {
      method: 'PATCH',
      body: JSON.stringify({ status }),
    }),
  listGroups: () => request('/api/admin/groups'),
  createGroup: (body) =>
    request('/api/admin/groups', {
      method: 'POST',
      body: JSON.stringify(body),
    }),
  updateGroupStatus: (groupId, status) =>
    request(`/api/admin/groups/${groupId}/status`, {
      method: 'PATCH',
      body: JSON.stringify({ status }),
    }),
  listMessages: () => request('/api/admin/messages'),
  updateMessageStatus: (messageId, status) =>
    request(`/api/admin/messages/${messageId}/status`, {
      method: 'PATCH',
      body: JSON.stringify({ status }),
    }),
  listSupportThreads: (status = '') =>
    request(`/api/admin/support${status && status !== 'ALL' ? `?status=${status}` : ''}`),
  listSupportMessages: (threadId) => request(`/api/admin/support/${threadId}/messages`),
  replySupport: (threadId, content) =>
    request(`/api/admin/support/${threadId}/messages`, {
      method: 'POST',
      body: JSON.stringify({ content }),
    }),
  updateSupportStatus: (threadId, status) =>
    request(`/api/admin/support/${threadId}/status`, {
      method: 'PATCH',
      body: JSON.stringify({ status }),
    }),
  broadcastNotification: (body) =>
    request('/api/admin/notifications/broadcast', {
      method: 'POST',
      body: JSON.stringify(body),
    }),
  listBadges: () => request('/api/admin/badges'),
  listMedia: () => request('/api/admin/media'),
  updateMediaStatus: (mediaId, status) =>
    request(`/api/admin/media/${encodeURIComponent(mediaId)}/status`, {
      method: 'PATCH',
      body: JSON.stringify({ status }),
    }),
  getSafety: () => request('/api/admin/safety'),
  updateSafety: (body) =>
    request('/api/admin/safety', {
      method: 'PATCH',
      body: JSON.stringify(body),
    }),
  listAudit: () => request('/api/admin/audit'),
};
