function toPublicUser(user) {
  return {
    id: user._id.toString(),
    displayName: user.displayName,
    username: user.username,
    age: user.age,
    role: user.role,
    avatarUrl: user.avatarUrl,
    coverUrl: user.coverUrl || '',
    bio: user.bio,
    favoriteTopics: user.favoriteTopics,
    privacy: user.privacy,
    createdAt: user.createdAt,
    updatedAt: user.updatedAt,
    lastActiveAt: user.lastActiveAt || null,
  };
}

module.exports = {
  toPublicUser,
};
