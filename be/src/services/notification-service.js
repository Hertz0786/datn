const Notification = require('../models/Notification');
const { emitToUser } = require('../realtime/socket');

/**
 * Whitelist of every notification type the app knows about.
 * Adding a new event? Append a new entry here so the frontend
 * can pattern-match on it safely. The `category` field groups
 * events in the UI (e.g. "social", "moderation", "support").
 */
const NOTIFICATION_TYPES = {
  // Friend system
  FRIEND_REQUEST_RECEIVED: 'FRIEND_REQUEST_RECEIVED',
  FRIEND_REQUEST_ACCEPTED: 'FRIEND_REQUEST_ACCEPTED',
  FRIEND_REQUEST_REJECTED: 'FRIEND_REQUEST_REJECTED',
  FRIEND_REMOVED: 'FRIEND_REMOVED',

  // Block system
  USER_BLOCKED: 'USER_BLOCKED',
  USER_UNBLOCKED: 'USER_UNBLOCKED',

  // Group system
  GROUP_CREATED: 'GROUP_CREATED',
  GROUP_JOIN_REQUEST: 'GROUP_JOIN_REQUEST',
  GROUP_JOIN_REQUEST_ACCEPTED: 'GROUP_JOIN_REQUEST_ACCEPTED',
  GROUP_JOIN_REQUEST_REJECTED: 'GROUP_JOIN_REQUEST_REJECTED',
  GROUP_MEMBER_JOINED: 'GROUP_MEMBER_JOINED',
  GROUP_MEMBER_LEFT: 'GROUP_MEMBER_LEFT',
  GROUP_MEMBER_REMOVED: 'GROUP_MEMBER_REMOVED',
  GROUP_POST_CREATED: 'GROUP_POST_CREATED',

  // Post / reaction system
  POST_LIKED: 'POST_LIKED',
  POST_PENDING_MEDIA_REVIEW: 'POST_PENDING_MEDIA_REVIEW',
  POST_MODERATION_DECIDED: 'POST_MODERATION_DECIDED',
  POST_SHARED: 'POST_SHARED',

  // Comment system
  COMMENT_CREATED: 'COMMENT_CREATED',
  COMMENT_REPLIED: 'COMMENT_REPLIED',
  COMMENT_LIKED: 'COMMENT_LIKED',
  COMMENT_DELETED: 'COMMENT_DELETED',

  // Chat / messaging
  CHAT_MESSAGE: 'CHAT_MESSAGE',
  CHAT_MEMBER_ADDED: 'CHAT_MEMBER_ADDED',
  CHAT_MEMBER_REMOVED: 'CHAT_MEMBER_REMOVED',
  CHAT_MESSAGE_READ: 'CHAT_MESSAGE_READ',

  // Support
  SUPPORT_MESSAGE_RECEIVED: 'SUPPORT_MESSAGE_RECEIVED',
  SUPPORT_STATUS_UPDATED: 'SUPPORT_STATUS_UPDATED',

  // Reports
  REPORT_SUBMITTED: 'REPORT_SUBMITTED',
  REPORT_STATUS_UPDATED: 'REPORT_STATUS_UPDATED',

  // Admin moderation
  ADMIN_BROADCAST: 'ADMIN_BROADCAST',
  ADMIN_MODERATION_ALERT: 'ADMIN_MODERATION_ALERT',

  // System / profile
  PROFILE_UPDATED: 'PROFILE_UPDATED',
  ACCOUNT_WARNING: 'ACCOUNT_WARNING',
};

const NOTIFICATION_CATEGORY = {
  [NOTIFICATION_TYPES.FRIEND_REQUEST_RECEIVED]: 'social',
  [NOTIFICATION_TYPES.FRIEND_REQUEST_ACCEPTED]: 'social',
  [NOTIFICATION_TYPES.FRIEND_REQUEST_REJECTED]: 'social',
  [NOTIFICATION_TYPES.FRIEND_REMOVED]: 'social',
  [NOTIFICATION_TYPES.USER_BLOCKED]: 'safety',
  [NOTIFICATION_TYPES.USER_UNBLOCKED]: 'safety',
  [NOTIFICATION_TYPES.GROUP_CREATED]: 'group',
  [NOTIFICATION_TYPES.GROUP_JOIN_REQUEST]: 'group',
  [NOTIFICATION_TYPES.GROUP_JOIN_REQUEST_ACCEPTED]: 'group',
  [NOTIFICATION_TYPES.GROUP_JOIN_REQUEST_REJECTED]: 'group',
  [NOTIFICATION_TYPES.GROUP_MEMBER_JOINED]: 'group',
  [NOTIFICATION_TYPES.GROUP_MEMBER_LEFT]: 'group',
  [NOTIFICATION_TYPES.GROUP_MEMBER_REMOVED]: 'group',
  [NOTIFICATION_TYPES.GROUP_POST_CREATED]: 'group',
  [NOTIFICATION_TYPES.POST_LIKED]: 'social',
  [NOTIFICATION_TYPES.POST_PENDING_MEDIA_REVIEW]: 'moderation',
  [NOTIFICATION_TYPES.POST_MODERATION_DECIDED]: 'moderation',
  [NOTIFICATION_TYPES.POST_SHARED]: 'social',
  [NOTIFICATION_TYPES.COMMENT_CREATED]: 'social',
  [NOTIFICATION_TYPES.COMMENT_REPLIED]: 'social',
  [NOTIFICATION_TYPES.COMMENT_LIKED]: 'social',
  [NOTIFICATION_TYPES.COMMENT_DELETED]: 'social',
  [NOTIFICATION_TYPES.CHAT_MESSAGE]: 'message',
  [NOTIFICATION_TYPES.CHAT_MEMBER_ADDED]: 'message',
  [NOTIFICATION_TYPES.CHAT_MEMBER_REMOVED]: 'message',
  [NOTIFICATION_TYPES.CHAT_MESSAGE_READ]: 'message',
  [NOTIFICATION_TYPES.SUPPORT_MESSAGE_RECEIVED]: 'support',
  [NOTIFICATION_TYPES.SUPPORT_STATUS_UPDATED]: 'support',
  [NOTIFICATION_TYPES.REPORT_SUBMITTED]: 'safety',
  [NOTIFICATION_TYPES.REPORT_STATUS_UPDATED]: 'safety',
  [NOTIFICATION_TYPES.ADMIN_BROADCAST]: 'admin',
  [NOTIFICATION_TYPES.ADMIN_MODERATION_ALERT]: 'admin',
  [NOTIFICATION_TYPES.PROFILE_UPDATED]: 'account',
  [NOTIFICATION_TYPES.ACCOUNT_WARNING]: 'safety',
};

/**
 * Default title/body for each notification type. Frontends can
 * still override per-event by passing a `title`/`body` in the
 * payload, but these are the fallbacks so the UI never renders
 * a blank notification.
 */
const DEFAULT_COPY = {
  [NOTIFICATION_TYPES.FRIEND_REQUEST_RECEIVED]: {
    title: 'Lời mời kết bạn mới',
    body: '${actor} muốn kết bạn với bạn.',
  },
  [NOTIFICATION_TYPES.FRIEND_REQUEST_ACCEPTED]: {
    title: 'Đã chấp nhận kết bạn',
    body: '${actor} đã chấp nhận lời mời kết bạn của bạn.',
  },
  [NOTIFICATION_TYPES.FRIEND_REQUEST_REJECTED]: {
    title: 'Lời mời kết bạn bị từ chối',
    body: '${actor} đã từ chối lời mời kết bạn của bạn.',
  },
  [NOTIFICATION_TYPES.FRIEND_REMOVED]: {
    title: 'Đã xóa khỏi danh sách bạn bè',
    body: '${actor} đã xóa bạn khỏi danh sách bạn bè.',
  },
  [NOTIFICATION_TYPES.USER_BLOCKED]: {
    title: 'Bạn đã bị chặn',
    body: '${actor} đã chặn bạn. Bạn sẽ không thể tương tác với họ.',
  },
  [NOTIFICATION_TYPES.USER_UNBLOCKED]: {
    title: 'Đã bỏ chặn',
    body: '${actor} đã bỏ chặn bạn.',
  },
  [NOTIFICATION_TYPES.GROUP_CREATED]: {
    title: 'Nhóm mới được tạo',
    body: 'Nhóm "${groupName}" vừa được tạo.',
  },
  [NOTIFICATION_TYPES.GROUP_JOIN_REQUEST]: {
    title: 'Yêu cầu tham gia nhóm',
    body: '${actor} muốn tham gia nhóm "${groupName}".',
  },
  [NOTIFICATION_TYPES.GROUP_JOIN_REQUEST_ACCEPTED]: {
    title: 'Đã được vào nhóm',
    body: 'Bạn đã được chấp nhận vào nhóm "${groupName}".',
  },
  [NOTIFICATION_TYPES.GROUP_JOIN_REQUEST_REJECTED]: {
    title: 'Bị từ chối vào nhóm',
    body: 'Yêu cầu vào nhóm "${groupName}" đã bị từ chối.',
  },
  [NOTIFICATION_TYPES.GROUP_MEMBER_JOINED]: {
    title: 'Thành viên mới',
    body: '${actor} vừa tham gia nhóm "${groupName}".',
  },
  [NOTIFICATION_TYPES.GROUP_MEMBER_LEFT]: {
    title: 'Thành viên rời nhóm',
    body: '${actor} vừa rời khỏi nhóm "${groupName}".',
  },
  [NOTIFICATION_TYPES.GROUP_MEMBER_REMOVED]: {
    title: 'Bạn đã bị xóa khỏi nhóm',
    body: 'Bạn đã bị xóa khỏi nhóm "${groupName}".',
  },
  [NOTIFICATION_TYPES.GROUP_POST_CREATED]: {
    title: 'Bài viết mới trong nhóm',
    body: '${actor} vừa đăng bài trong nhóm "${groupName}".',
  },
  [NOTIFICATION_TYPES.POST_LIKED]: {
    title: 'Có người thích bài viết của bạn',
    body: '${actor} vừa thích bài viết của bạn.',
  },
  [NOTIFICATION_TYPES.POST_PENDING_MEDIA_REVIEW]: {
    title: 'Bài đăng đang chờ duyệt',
    body: 'Chúng tôi nghi ngờ bài đăng của bạn có hình ảnh chứa nội dung nhạy cảm. Vui lòng đợi admin duyệt.',
  },
  [NOTIFICATION_TYPES.POST_MODERATION_DECIDED]: {
    title: 'Bài đăng đã được admin xử lý',
    body: 'Bài đăng của bạn đã được admin xử lý.',
  },
  [NOTIFICATION_TYPES.COMMENT_CREATED]: {
    title: 'Có bình luận mới',
    body: '${actor} đã bình luận về bài viết của bạn.',
  },
  [NOTIFICATION_TYPES.COMMENT_REPLIED]: {
    title: 'Có người trả lời bình luận',
    body: '${actor} đã trả lời bình luận của bạn.',
  },
  [NOTIFICATION_TYPES.COMMENT_LIKED]: {
    title: 'Có người thích bình luận của bạn',
    body: '${actor} đã thích bình luận của bạn.',
  },
  [NOTIFICATION_TYPES.COMMENT_DELETED]: {
    title: 'Bình luận đã bị xóa',
    body: 'Một bình luận của bạn đã bị xóa.',
  },
  [NOTIFICATION_TYPES.CHAT_MESSAGE]: {
    title: 'Tin nhắn mới',
    body: '${actor} vừa gửi cho bạn một tin nhắn.',
  },
  [NOTIFICATION_TYPES.CHAT_MEMBER_ADDED]: {
    title: 'Bạn vừa được thêm vào nhóm chat',
    body: 'Bạn đã được thêm vào cuộc trò chuyện "${chatName}".',
  },
  [NOTIFICATION_TYPES.CHAT_MEMBER_REMOVED]: {
    title: 'Bạn vừa bị xóa khỏi nhóm chat',
    body: 'Bạn đã bị xóa khỏi cuộc trò chuyện "${chatName}".',
  },
  [NOTIFICATION_TYPES.CHAT_MESSAGE_READ]: {
    title: 'Tin nhắn đã được đọc',
    body: '${actor} đã đọc tin nhắn của bạn.',
  },
  [NOTIFICATION_TYPES.SUPPORT_MESSAGE_RECEIVED]: {
    title: 'Phản hồi từ đội ngũ hỗ trợ',
    body: 'Bạn vừa nhận được phản hồi từ admin.',
  },
  [NOTIFICATION_TYPES.SUPPORT_STATUS_UPDATED]: {
    title: 'Trạng thái yêu cầu hỗ trợ đã cập nhật',
    body: 'Yêu cầu hỗ trợ của bạn đã được cập nhật trạng thái.',
  },
  [NOTIFICATION_TYPES.REPORT_SUBMITTED]: {
    title: 'Báo cáo đã được gửi',
    body: 'Cảm ơn bạn. Báo cáo của bạn đã được gửi cho đội ngũ kiểm duyệt.',
  },
  [NOTIFICATION_TYPES.REPORT_STATUS_UPDATED]: {
    title: 'Báo cáo đã được xử lý',
    body: 'Báo cáo của bạn đã được đội ngũ kiểm duyệt xử lý.',
  },
  [NOTIFICATION_TYPES.ADMIN_BROADCAST]: {
    title: 'Thông báo từ đội ngũ Kiddo',
    body: 'Bạn có một thông báo mới từ đội ngũ vận hành.',
  },
  [NOTIFICATION_TYPES.ADMIN_MODERATION_ALERT]: {
    title: 'Có nội dung cần admin duyệt',
    body: 'Một bài viết hoặc bình luận cần được bạn xem xét.',
  },
  [NOTIFICATION_TYPES.PROFILE_UPDATED]: {
    title: 'Hồ sơ đã được cập nhật',
    body: 'Hồ sơ của bạn vừa được cập nhật.',
  },
  [NOTIFICATION_TYPES.ACCOUNT_WARNING]: {
    title: 'Cảnh báo tài khoản',
    body: 'Tài khoản của bạn vừa nhận một cảnh báo từ đội ngũ kiểm duyệt.',
  },
};

/**
 * Replace ${token} placeholders in a template string with values
 * from the supplied context. Missing tokens stay literal so a
 * template never breaks at runtime.
 *
 * Uses a function replacement so the ${...} pattern is treated as a
 * literal string — it is NOT evaluated as a JS template-literal
 * expression.  This prevents ${id} or ${n} in user content from
 * accidentally triggering expression evaluation.
 */
function renderTemplate(template, context) {
  if (typeof template !== 'string') {
    return template;
  }
  return template.replace(/\$\{(\w+)\}/g, (match) => {
    const key = match.slice(2, -1); // strip ${ and }
    if (Object.prototype.hasOwnProperty.call(context, key)) {
      return String(context[key]);
    }
    return match;
  });
}

/**
 * Send a single notification. Persists the row and emits the
 * realtime `notification:created` event so connected clients
 * update their badge / play a sound / etc.
 *
 * Returns the created notification, or null if the recipient is
 * the same as the actor (self-notifications are suppressed so we
 * do not ping the device that just triggered the event).
 */
async function sendNotification({
  userId,
  actorId = null,
  type,
  title = null,
  body = null,
  payload = {},
  emitRealtime = true,
  skipSelf = true,
  persist = true,
}) {
  if (!userId || !type) {
    return null;
  }
  if (skipSelf && actorId && userId.toString() === actorId.toString()) {
    return null;
  }
  if (!Object.values(NOTIFICATION_TYPES).includes(type)) {
    // Fail loudly so a typo in a route does not silently spam
    // the notifications collection.
    throw new Error(`Unknown notification type: ${type}`);
  }

  const enrichedPayload = {
    ...payload,
    category: NOTIFICATION_CATEGORY[type] || 'system',
  };

  if (persist && type !== NOTIFICATION_TYPES.CHAT_MESSAGE) {
    const fallback = DEFAULT_COPY[type] || { title: 'Thông báo', body: '' };
    const context = {
      actor: (payload.actorName || payload.actorUsername || 'Ai đó'),
      ...payload,
    };
    enrichedPayload.title = title || renderTemplate(fallback.title, context);
    enrichedPayload.body = body || renderTemplate(fallback.body, context);

    const notification = await Notification.create({
      userId,
      type,
      payload: enrichedPayload,
    });

    if (emitRealtime) {
      emitToUser(userId.toString(), 'notification:created', {
        notification: serializeNotification(notification),
      });
    }

    return notification;
  }

  if (emitRealtime) {
    emitToUser(userId.toString(), 'notification:created', {
      notification: {
        id: `realtime-${Date.now()}-${Math.random().toString(36).slice(2)}`,
        type,
        payload: enrichedPayload,
        readAt: null,
        createdAt: new Date(),
      },
    });
  }

  return null;
}

/**
 * Send the same notification to many users in one go. Returns the
 * list of created notifications (skipping self-recipients).
 */
async function broadcastNotification({
  userIds,
  actorId = null,
  type,
  title = null,
  body = null,
  payload = {},
  emitRealtime = true,
  skipSelf = true,
}) {
  if (!Array.isArray(userIds) || userIds.length === 0) {
    return [];
  }
  const shouldPersist = type !== NOTIFICATION_TYPES.CHAT_MESSAGE;
  const results = await Promise.all(
    userIds
      .filter((id) => !(skipSelf && actorId && id.toString() === actorId.toString()))
      .map((id) =>
        sendNotification({
          userId: id,
          actorId,
          type,
          title,
          body,
          payload,
          emitRealtime,
          skipSelf: false, // we already filtered
          persist: shouldPersist,
        }),
      ),
  );
  return results.filter(Boolean);
}

function serializeNotification(doc) {
  if (!doc) {
    return null;
  }
  return {
    id: doc._id.toString(),
    type: doc.type,
    payload: doc.payload || {},
    readAt: doc.readAt,
    createdAt: doc.createdAt,
  };
}

module.exports = {
  NOTIFICATION_TYPES,
  NOTIFICATION_CATEGORY,
  DEFAULT_COPY,
  sendNotification,
  broadcastNotification,
  renderTemplate,
  serializeNotification,
};
