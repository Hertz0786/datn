const PostReaction = require('../models/PostReaction');
const PostBookmark = require('../models/PostBookmark');
const User = require('../models/User');

async function withPostMeta(posts, userId) {
  const postList = Array.isArray(posts) ? posts : [posts];
  if (postList.length === 0) {
    return Array.isArray(posts) ? [] : null;
  }

  const postIds = postList.map((post) => post._id);
  const authorIds = [
    ...new Set(postList.map((post) => post.authorId.toString())),
  ];

  const [reactions, bookmarks, authors] = await Promise.all([
    PostReaction.find({ postId: { $in: postIds } }),
    PostBookmark.find({ postId: { $in: postIds }, userId }).select('postId'),
    User.find({ _id: { $in: authorIds }, isActive: true }).select(
      '_id displayName username avatarUrl role lastActiveAt',
    ),
  ]);

  const myReactionByPost = new Map();
  const breakdownByPost = new Map();

  for (const reaction of reactions) {
    const pid = reaction.postId.toString();
    if (reaction.userId.toString() === userId.toString()) {
      myReactionByPost.set(pid, reaction.reaction);
    }
    const counts = breakdownByPost.get(pid) || {};
    counts[reaction.reaction] = (counts[reaction.reaction] || 0) + 1;
    breakdownByPost.set(pid, counts);
  }

  const bookmarkedPostIds = new Set(
    bookmarks.map((bookmark) => bookmark.postId.toString()),
  );
  const authorById = new Map(
    authors.map((author) => [author._id.toString(), author]),
  );

  const items = postList.map((post) => {
    const postObject = typeof post.toObject === 'function' ? post.toObject() : post;
    const author = authorById.get(post.authorId.toString());
    const pid = post._id.toString();
    const savedSnapshot = postObject.authorSnapshot || {};
    const authorSnapshot = {
      _id: author ? author._id.toString() : post.authorId.toString(),
      displayName: author?.displayName || savedSnapshot.displayName || '',
      username: author?.username || savedSnapshot.username || '',
      avatarUrl: author?.avatarUrl || savedSnapshot.avatarUrl || '',
      role: author?.role || savedSnapshot.role || '',
      lastActiveAt: author?.lastActiveAt || savedSnapshot.lastActiveAt || null,
    };

    return {
      ...postObject,
      id: pid,
      likedByMe: myReactionByPost.has(pid),
      myReaction: myReactionByPost.get(pid) || null,
      reactions: breakdownByPost.get(pid) || {},
      bookmarkedByMe: bookmarkedPostIds.has(pid),
      authorSnapshot,
    };
  });

  return Array.isArray(posts) ? items : items[0];
}

module.exports = {
  withPostMeta,
};
