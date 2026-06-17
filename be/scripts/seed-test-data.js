/* eslint-disable no-console */

const bcrypt = require('bcryptjs');
const mongoose = require('mongoose');

const connectDB = require('../src/config/db');
const { normalizeFriendPair } = require('../src/utils/friendship');

const User = require('../src/models/User');
const Group = require('../src/models/Group');
const GroupMember = require('../src/models/GroupMember');
const Post = require('../src/models/Post');
const Comment = require('../src/models/Comment');
const Chat = require('../src/models/Chat');
const Message = require('../src/models/Message');
const Friendship = require('../src/models/Friendship');
const FriendRequest = require('../src/models/FriendRequest');
const Notification = require('../src/models/Notification');
const Report = require('../src/models/Report');
const Block = require('../src/models/Block');

const DEFAULT_PASSWORD = 'Kiddo123!';

const SEED_USERS = [
  {
    displayName: 'Kiddo Admin',
    username: 'admin_kiddo',
    age: 13,
    role: 'ADMIN',
    favoriteTopics: ['safety', 'community'],
  },
  {
    displayName: 'Luna Moderator',
    username: 'mod_luna',
    age: 12,
    role: 'MODERATOR',
    favoriteTopics: ['moderation', 'kindness'],
  },
  {
    displayName: 'Alex Star',
    username: 'kid_alex',
    age: 9,
    role: 'CHILD',
    favoriteTopics: ['space', 'science'],
  },
  {
    displayName: 'Bella Bloom',
    username: 'kid_bella',
    age: 10,
    role: 'CHILD',
    favoriteTopics: ['books', 'music'],
  },
  {
    displayName: 'Cody Code',
    username: 'kid_cody',
    age: 11,
    role: 'CHILD',
    favoriteTopics: ['coding', 'games'],
  },
  {
    displayName: 'Daisy Draw',
    username: 'kid_daisy',
    age: 8,
    role: 'CHILD',
    favoriteTopics: ['art', 'animals'],
  },
  {
    displayName: 'Ethan Earth',
    username: 'kid_ethan',
    age: 12,
    role: 'CHILD',
    favoriteTopics: ['sports', 'space'],
  },
  {
    displayName: 'Fiona Fun',
    username: 'kid_fiona',
    age: 13,
    role: 'CHILD',
    favoriteTopics: ['dance', 'stories'],
  },
];

const SEED_GROUPS = [
  {
    key: 'group_star',
    name: 'Star Gazers',
    topic: 'space',
    description: 'Share fun facts about planets and stars.',
    ageMin: 8,
    ageMax: 12,
    owner: 'kid_alex',
    members: ['kid_bella', 'kid_ethan'],
  },
  {
    key: 'group_pixel',
    name: 'Pixel Coders',
    topic: 'coding',
    description: 'Build mini games and learn coding together.',
    ageMin: 10,
    ageMax: 14,
    owner: 'kid_cody',
    members: ['kid_ethan', 'kid_fiona'],
  },
  {
    key: 'group_art',
    name: 'Art Sparks',
    topic: 'art',
    description: 'Drawing, painting and creative craft challenges.',
    ageMin: 7,
    ageMax: 11,
    owner: 'kid_daisy',
    members: ['kid_alex', 'kid_bella'],
  },
  {
    key: 'group_books',
    name: 'Book Buddies',
    topic: 'books',
    description: 'Read stories and share your favorite characters.',
    ageMin: 8,
    ageMax: 14,
    owner: 'kid_bella',
    members: ['kid_daisy', 'kid_fiona'],
  },
];

const SEED_FRIENDSHIPS = [
  ['kid_alex', 'kid_bella'],
  ['kid_alex', 'kid_daisy'],
  ['kid_alex', 'kid_ethan'],
  ['kid_bella', 'kid_fiona'],
  ['kid_cody', 'kid_ethan'],
  ['kid_ethan', 'kid_fiona'],
];

const SEED_FRIEND_REQUESTS = [
  { sender: 'kid_bella', receiver: 'kid_cody', status: 'PENDING' },
  { sender: 'kid_daisy', receiver: 'kid_fiona', status: 'PENDING' },
  { sender: 'kid_ethan', receiver: 'kid_bella', status: 'PENDING' },
];

const SEED_POSTS = [
  {
    key: 'post_alex_space',
    author: 'kid_alex',
    content: 'I built a paper rocket today. It flew across my room!',
    topics: ['space', 'science'],
    mood: 'excited',
    audience: 'PUBLIC',
    allowComments: true,
    allowReactions: true,
    ageMin: 7,
    ageMax: 14,
  },
  {
    key: 'post_bella_books',
    author: 'kid_bella',
    content: 'My favorite story this week is about a tiny explorer.',
    topics: ['books', 'stories'],
    mood: 'happy',
    audience: 'FRIENDS',
    allowComments: true,
    allowReactions: true,
    ageMin: 8,
    ageMax: 14,
  },
  {
    key: 'post_cody_game',
    author: 'kid_cody',
    content: 'I made a mini maze game with points and levels.',
    topics: ['coding', 'games'],
    mood: 'proud',
    audience: 'PUBLIC',
    allowComments: true,
    allowReactions: true,
    ageMin: 9,
    ageMax: 14,
  },
  {
    key: 'post_daisy_art',
    author: 'kid_daisy',
    content: 'I drew a panda with watercolor. The ears look cute!',
    topics: ['art', 'animals'],
    mood: 'calm',
    audience: 'FRIENDS',
    allowComments: true,
    allowReactions: true,
    ageMin: 7,
    ageMax: 12,
  },
  {
    key: 'post_ethan_sports',
    author: 'kid_ethan',
    content: 'Team practice was awesome. I learned a new pass today.',
    topics: ['sports', 'teamwork'],
    mood: 'energetic',
    audience: 'PUBLIC',
    allowComments: true,
    allowReactions: true,
    ageMin: 9,
    ageMax: 14,
  },
  {
    key: 'post_fiona_dance',
    author: 'kid_fiona',
    content: 'Our dance group finished a fun routine for school day.',
    topics: ['dance', 'music'],
    mood: 'joyful',
    audience: 'PUBLIC',
    allowComments: true,
    allowReactions: true,
    ageMin: 8,
    ageMax: 14,
  },
];

const SEED_COMMENTS = [
  {
    key: 'comment_bella_on_alex',
    postKey: 'post_alex_space',
    author: 'kid_bella',
    content: 'That sounds amazing. Did you paint the rocket too?',
  },
  {
    key: 'reply_cody_to_bella',
    postKey: 'post_alex_space',
    author: 'kid_cody',
    parentKey: 'comment_bella_on_alex',
    content: 'I want to build one too this weekend.',
  },
  {
    key: 'comment_ethan_on_cody',
    postKey: 'post_cody_game',
    author: 'kid_ethan',
    content: 'Can I test your game after class?',
  },
  {
    key: 'comment_alex_on_bella',
    postKey: 'post_bella_books',
    author: 'kid_alex',
    content: 'Nice pick. I like explorer stories too.',
  },
  {
    key: 'comment_daisy_on_fiona',
    postKey: 'post_fiona_dance',
    author: 'kid_daisy',
    content: 'So cool! Please share your favorite song next time.',
  },
];

const SEED_CHATS = [
  {
    key: 'chat_alex_bella',
    type: 'DIRECT',
    members: ['kid_alex', 'kid_bella'],
    createdBy: 'kid_alex',
    messages: [
      { sender: 'kid_alex', content: 'Hi Bella, did you finish reading today?' },
      { sender: 'kid_bella', content: 'Yes. I loved chapter three!' },
      { sender: 'kid_alex', content: 'Great. Let us discuss it after class.' },
    ],
  },
  {
    key: 'chat_cody_ethan',
    type: 'DIRECT',
    members: ['kid_cody', 'kid_ethan'],
    createdBy: 'kid_cody',
    messages: [
      { sender: 'kid_cody', content: 'Want to test my maze game now?' },
      { sender: 'kid_ethan', content: 'Sure. Send me the score challenge.' },
    ],
  },
  {
    key: 'chat_art_group',
    type: 'GROUP',
    members: ['kid_daisy', 'kid_alex', 'kid_bella'],
    createdBy: 'kid_daisy',
    messages: [
      { sender: 'kid_daisy', content: 'Art challenge: draw your dream pet.' },
      { sender: 'kid_alex', content: 'I will draw a robot cat.' },
      { sender: 'kid_bella', content: 'I am drawing a flying rabbit.' },
    ],
  },
];

function getArg(name) {
  const index = process.argv.indexOf(`--${name}`);
  if (index === -1) return undefined;
  const value = process.argv[index + 1];
  if (!value || value.startsWith('--')) return '';
  return value;
}

function hasFlag(name) {
  return process.argv.includes(`--${name}`);
}

function toSnapshot(user) {
  return {
    displayName: user.displayName,
    username: user.username,
    avatarUrl: user.avatarUrl || '',
  };
}

function getUser(usersByUsername, username) {
  const user = usersByUsername.get(username);
  if (!user) {
    throw new Error(`Seed user not found: ${username}`);
  }
  return user;
}

async function upsertUsers(passwordHash) {
  const usersByUsername = new Map();

  for (const item of SEED_USERS) {
    const update = {
      displayName: item.displayName,
      age: item.age,
      role: item.role,
      favoriteTopics: item.favoriteTopics,
      bio: 'Seed account for API testing.',
      avatarUrl: '',
      isActive: true,
      passwordHash,
      privacy: {
        allowFriendRequests: true,
        allowComments: true,
        safeSearchOnly: true,
      },
    };

    const user = await User.findOneAndUpdate(
      { username: item.username },
      {
        $set: {
          ...update,
          username: item.username,
        },
      },
      {
        upsert: true,
        returnDocument: 'after',
        runValidators: true,
        setDefaultsOnInsert: true,
      },
    );

    usersByUsername.set(item.username, user);
  }

  return usersByUsername;
}

async function clearSeedData(seedUserIds) {
  const userFilter = { $in: seedUserIds };

  const ownedGroupIds = await Group.find({ ownerId: userFilter }).distinct('_id');
  if (ownedGroupIds.length > 0) {
    await GroupMember.deleteMany({
      $or: [{ userId: userFilter }, { groupId: { $in: ownedGroupIds } }],
    });
  } else {
    await GroupMember.deleteMany({ userId: userFilter });
  }
  await Group.deleteMany({ ownerId: userFilter });

  const authoredPostIds = await Post.find({ authorId: userFilter }).distinct('_id');
  if (authoredPostIds.length > 0) {
    await Comment.deleteMany({ postId: { $in: authoredPostIds } });
  }
  await Comment.deleteMany({ authorId: userFilter });
  await Post.deleteMany({ authorId: userFilter });

  const chatIds = await Chat.find({ memberIds: userFilter }).distinct('_id');
  if (chatIds.length > 0) {
    await Message.deleteMany({ chatId: { $in: chatIds } });
  }
  await Message.deleteMany({ senderId: userFilter });
  await Chat.deleteMany({ memberIds: userFilter });

  await Friendship.deleteMany({
    $or: [{ userAId: userFilter }, { userBId: userFilter }],
  });

  await FriendRequest.deleteMany({
    $or: [{ senderId: userFilter }, { receiverId: userFilter }],
  });

  await Block.deleteMany({
    $or: [{ blockerId: userFilter }, { blockedId: userFilter }],
  });

  await Notification.deleteMany({ userId: userFilter });
  await Report.deleteMany({ reporterId: userFilter });
}

async function seedGroups(usersByUsername) {
  const groupsByKey = new Map();

  for (const item of SEED_GROUPS) {
    const owner = getUser(usersByUsername, item.owner);
    const memberIds = item.members.map((username) =>
      getUser(usersByUsername, username)._id,
    );

    const group = await Group.create({
      name: item.name,
      topic: item.topic,
      description: item.description,
      ageMin: item.ageMin,
      ageMax: item.ageMax,
      ownerId: owner._id,
      memberCount: 1 + memberIds.length,
      status: 'ACTIVE',
    });

    await GroupMember.create({
      groupId: group._id,
      userId: owner._id,
      role: 'OWNER',
      status: 'ACTIVE',
    });

    for (const memberId of memberIds) {
      await GroupMember.create({
        groupId: group._id,
        userId: memberId,
        role: 'MEMBER',
        status: 'ACTIVE',
      });
    }

    groupsByKey.set(item.key, group);
  }

  return groupsByKey;
}

async function seedFriendships(usersByUsername) {
  for (const [left, right] of SEED_FRIENDSHIPS) {
    const userA = getUser(usersByUsername, left);
    const userB = getUser(usersByUsername, right);
    const pair = normalizeFriendPair(userA._id, userB._id);

    await Friendship.findOneAndUpdate(
      pair,
      { $set: pair },
      { upsert: true, returnDocument: 'after', setDefaultsOnInsert: true },
    );
  }
}

async function seedFriendRequests(usersByUsername) {
  for (const item of SEED_FRIEND_REQUESTS) {
    const sender = getUser(usersByUsername, item.sender);
    const receiver = getUser(usersByUsername, item.receiver);

    await FriendRequest.create({
      senderId: sender._id,
      receiverId: receiver._id,
      status: item.status,
    });
  }
}

async function seedPosts(usersByUsername) {
  const postsByKey = new Map();

  for (const item of SEED_POSTS) {
    const author = getUser(usersByUsername, item.author);

    const post = await Post.create({
      authorId: author._id,
      authorSnapshot: toSnapshot(author),
      content: item.content,
      topics: item.topics,
      mood: item.mood,
      audience: item.audience,
      allowComments: item.allowComments,
      allowReactions: item.allowReactions,
      ageMin: item.ageMin,
      ageMax: item.ageMax,
      reactionCount: 0,
      commentCount: 0,
      status: 'PUBLISHED',
    });

    postsByKey.set(item.key, post);
  }

  return postsByKey;
}

async function seedComments(usersByUsername, postsByKey) {
  const commentsByKey = new Map();

  for (const item of SEED_COMMENTS) {
    const author = getUser(usersByUsername, item.author);
    const post = postsByKey.get(item.postKey);

    if (!post) {
      throw new Error(`Seed post not found: ${item.postKey}`);
    }

    const parentComment = item.parentKey ? commentsByKey.get(item.parentKey) : null;

    if (item.parentKey && !parentComment) {
      throw new Error(`Seed parent comment not found: ${item.parentKey}`);
    }

    const comment = await Comment.create({
      postId: post._id,
      authorId: author._id,
      authorSnapshot: toSnapshot(author),
      parentCommentId: parentComment ? parentComment._id : null,
      content: item.content,
      status: 'PUBLISHED',
      likeCount: 0,
    });

    commentsByKey.set(item.key, comment);
  }

  return commentsByKey;
}

async function syncCommentCounts(postsByKey) {
  for (const post of postsByKey.values()) {
    const commentCount = await Comment.countDocuments({
      postId: post._id,
      status: 'PUBLISHED',
    });

    await Post.updateOne(
      { _id: post._id },
      { $set: { commentCount } },
      { runValidators: true },
    );
  }
}

async function seedChats(usersByUsername) {
  const chatsByKey = new Map();

  for (const item of SEED_CHATS) {
    const createdBy = getUser(usersByUsername, item.createdBy);
    const memberIds = item.members.map((username) =>
      getUser(usersByUsername, username)._id.toString(),
    );

    if (item.type === 'DIRECT') {
      memberIds.sort();
    }

    const chat = await Chat.create({
      type: item.type,
      memberIds,
      createdBy: createdBy._id,
    });

    let lastMessageAt = null;
    for (const messageSeed of item.messages) {
      const sender = getUser(usersByUsername, messageSeed.sender);
      const message = await Message.create({
        chatId: chat._id,
        senderId: sender._id,
        content: messageSeed.content,
        status: 'SENT',
      });
      lastMessageAt = message.createdAt;
    }

    if (lastMessageAt) {
      await Chat.updateOne(
        { _id: chat._id },
        { $set: { updatedAt: lastMessageAt } },
      );
    }

    chatsByKey.set(item.key, chat);
  }

  return chatsByKey;
}

async function seedReports(usersByUsername, postsByKey, groupsByKey) {
  const reportsByKey = new Map();

  const reports = [
    {
      key: 'report_post_spam',
      reporter: 'kid_bella',
      targetType: 'POST',
      targetId: postsByKey.get('post_cody_game')._id.toString(),
      category: 'SPAM',
      details: 'Looks repeated too many times in my feed.',
      urgency: 2,
      status: 'PENDING',
    },
    {
      key: 'report_user_bullying',
      reporter: 'kid_daisy',
      targetType: 'USER',
      targetId: getUser(usersByUsername, 'kid_fiona')._id.toString(),
      category: 'BULLYING',
      details: 'I felt uncomfortable with one message in chat.',
      urgency: 4,
      status: 'REVIEWING',
    },
    {
      key: 'report_group_other',
      reporter: 'kid_alex',
      targetType: 'GROUP',
      targetId: groupsByKey.get('group_pixel')._id.toString(),
      category: 'OTHER',
      details: 'Please review group rules description wording.',
      urgency: 1,
      status: 'RESOLVED',
    },
  ];

  for (const item of reports) {
    const reporter = getUser(usersByUsername, item.reporter);
    const report = await Report.create({
      reporterId: reporter._id,
      targetType: item.targetType,
      targetId: item.targetId,
      category: item.category,
      details: item.details,
      urgency: item.urgency,
      status: item.status,
    });
    reportsByKey.set(item.key, report);
  }

  return reportsByKey;
}

async function seedNotifications(usersByUsername, reportsByKey) {
  const notifications = [
    {
      user: 'kid_bella',
      type: 'FRIEND_REQUEST_RECEIVED',
      payload: {
        fromUserId: getUser(usersByUsername, 'kid_ethan')._id.toString(),
      },
      read: false,
    },
    {
      user: 'kid_cody',
      type: 'FRIEND_REQUEST_RECEIVED',
      payload: {
        fromUserId: getUser(usersByUsername, 'kid_bella')._id.toString(),
      },
      read: false,
    },
    {
      user: 'kid_daisy',
      type: 'REPORT_STATUS_UPDATED',
      payload: {
        reportId: reportsByKey.get('report_user_bullying')._id.toString(),
        status: 'REVIEWING',
      },
      read: true,
    },
    {
      user: 'mod_luna',
      type: 'MODERATION_ALERT',
      payload: {
        reportId: reportsByKey.get('report_post_spam')._id.toString(),
      },
      read: false,
    },
  ];

  for (const item of notifications) {
    const user = getUser(usersByUsername, item.user);
    await Notification.create({
      userId: user._id,
      type: item.type,
      payload: item.payload,
      readAt: item.read ? new Date() : null,
    });
  }
}

async function seedBlocks(usersByUsername) {
  await Block.create({
    blockerId: getUser(usersByUsername, 'kid_fiona')._id,
    blockedId: getUser(usersByUsername, 'kid_daisy')._id,
  });
}

function printCredentials(password) {
  console.log('\nSeed users for login:');
  for (const user of SEED_USERS) {
    console.log(
      `- username=${user.username} | role=${user.role} | age=${user.age} | password=${password}`,
    );
  }
}

function printSummary(created) {
  console.log('\nCreated test dataset:');
  console.log(`- users: ${created.users}`);
  console.log(`- groups: ${created.groups}`);
  console.log(`- groupMembers: ${created.groupMembers}`);
  console.log(`- friendships: ${created.friendships}`);
  console.log(`- friendRequests: ${created.friendRequests}`);
  console.log(`- posts: ${created.posts}`);
  console.log(`- comments: ${created.comments}`);
  console.log(`- chats: ${created.chats}`);
  console.log(`- messages: ${created.messages}`);
  console.log(`- reports: ${created.reports}`);
  console.log(`- notifications: ${created.notifications}`);
  console.log(`- blocks: ${created.blocks}`);
}

async function main() {
  const password = getArg('password') || process.env.SEED_PASSWORD || DEFAULT_PASSWORD;
  const appendMode = hasFlag('append');

  if (password.length < 6) {
    throw new Error('Password must be at least 6 characters.');
  }

  await connectDB();

  const passwordHash = await bcrypt.hash(password, 10);
  const usersByUsername = await upsertUsers(passwordHash);
  const seedUserIds = Array.from(usersByUsername.values()).map((user) => user._id);

  if (!appendMode) {
    await clearSeedData(seedUserIds);
  }

  const groupsByKey = await seedGroups(usersByUsername);
  await seedFriendships(usersByUsername);
  await seedFriendRequests(usersByUsername);
  const postsByKey = await seedPosts(usersByUsername);
  const commentsByKey = await seedComments(usersByUsername, postsByKey);
  await syncCommentCounts(postsByKey);
  await seedChats(usersByUsername);
  const reportsByKey = await seedReports(usersByUsername, postsByKey, groupsByKey);
  await seedNotifications(usersByUsername, reportsByKey);
  await seedBlocks(usersByUsername);

  const groupIds = Array.from(groupsByKey.values()).map((item) => item._id);
  const chatIds = await Chat.find({ memberIds: { $in: seedUserIds } }).distinct('_id');

  printSummary({
    users: SEED_USERS.length,
    groups: await Group.countDocuments({ _id: { $in: groupIds } }),
    groupMembers: await GroupMember.countDocuments({ groupId: { $in: groupIds } }),
    friendships: await Friendship.countDocuments({
      $or: [{ userAId: { $in: seedUserIds } }, { userBId: { $in: seedUserIds } }],
    }),
    friendRequests: await FriendRequest.countDocuments({
      $or: [{ senderId: { $in: seedUserIds } }, { receiverId: { $in: seedUserIds } }],
    }),
    posts: await Post.countDocuments({ authorId: { $in: seedUserIds } }),
    comments: await Comment.countDocuments({ authorId: { $in: seedUserIds } }),
    chats: await Chat.countDocuments({ _id: { $in: chatIds } }),
    messages: await Message.countDocuments({ chatId: { $in: chatIds } }),
    reports: await Report.countDocuments({ reporterId: { $in: seedUserIds } }),
    notifications: await Notification.countDocuments({ userId: { $in: seedUserIds } }),
    blocks: await Block.countDocuments({
      $or: [{ blockerId: { $in: seedUserIds } }, { blockedId: { $in: seedUserIds } }],
    }),
  });

  printCredentials(password);
  console.log(
    '\nSeed completed successfully. Run with --append if you do not want old seed data to be replaced.',
  );
}

main()
  .catch((error) => {
    console.error('Seed failed:', error);
    process.exitCode = 1;
  })
  .finally(async () => {
    try {
      await mongoose.disconnect();
    } catch {
      // ignore disconnect errors
    }
  });
