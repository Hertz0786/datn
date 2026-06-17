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
const PostReaction = require('../src/models/PostReaction');
const PostBookmark = require('../src/models/PostBookmark');
const MediaAsset = require('../src/models/MediaAsset');
const Photo = require('../src/models/Photo');

const DEFAULT_PASSWORD = 'Kiddo123!';
const RICH_PREFIX = 'rich_seed';

const USERS = [
  ['kid_mia', 'Mia Melody', 8, ['music', 'stories'], 'I like making tiny songs and sharing kind notes.'],
  ['kid_noah', 'Noah Nova', 9, ['space', 'science'], 'I collect star facts and build paper rockets.'],
  ['kid_ivy', 'Ivy Ink', 10, ['art', 'books'], 'Sketchbook explorer with too many colored pencils.'],
  ['kid_leo', 'Leo Logic', 11, ['coding', 'puzzles'], 'I build small games and love clever puzzles.'],
  ['kid_zoe', 'Zoe Zoom', 7, ['sports', 'friends'], 'Fast runner, team player, snack enthusiast.'],
  ['kid_kian', 'Kian Kite', 12, ['nature', 'travel'], 'Cloud watcher and weekend walking expert.'],
  ['kid_mina', 'Mina Moon', 9, ['space', 'drawing'], 'Moon doodles, bedtime stories, and soft colors.'],
  ['kid_rio', 'Rio Runner', 13, ['sports', 'health'], 'Practice, teamwork, and friendly challenges.'],
  ['kid_hana', 'Hana Heart', 8, ['kindness', 'craft'], 'Making cards and cheering friends on.'],
  ['kid_ben', 'Ben Brave', 10, ['games', 'robotics'], 'Robot builder with a notebook full of ideas.'],
  ['kid_sara', 'Sara Story', 11, ['books', 'writing'], 'I write tiny adventures after school.'],
  ['kid_tony', 'Tony Tinker', 12, ['science', 'makers'], 'I fix toys, test ideas, and label everything.'],
  ['kid_lily', 'Lily Light', 7, ['dance', 'music'], 'Dance steps, bright stickers, and happy songs.'],
  ['kid_finn', 'Finn Forest', 9, ['nature', 'animals'], 'I know many leaf shapes and bird sounds.'],
  ['kid_nami', 'Nami Note', 10, ['music', 'school'], 'Piano practice and neat study notes.'],
  ['kid_kai', 'Kai Cloud', 12, ['weather', 'science'], 'I track clouds and ask big questions.'],
  ['kid_ruby', 'Ruby Rain', 8, ['art', 'nature'], 'Watercolor clouds and tiny flower drawings.'],
  ['kid_oscar', 'Oscar Orbit', 13, ['space', 'math'], 'Planet models and number games.'],
  ['kid_emma', 'Emma Echo', 9, ['stories', 'drama'], 'I like acting out funny story scenes.'],
  ['kid_max', 'Max Marble', 11, ['games', 'sports'], 'Board games, football, and fair play.'],
  ['kid_nina', 'Nina Nature', 10, ['animals', 'garden'], 'Garden helper and butterfly spotter.'],
  ['kid_tom', 'Tom Tempo', 12, ['music', 'coding'], 'I make beats and try coding patterns.'],
  ['kid_amy', 'Amy Art', 8, ['painting', 'craft'], 'Glue, paper, paint, and big imagination.'],
  ['kid_ken', 'Ken Quest', 13, ['adventure', 'books'], 'Maps, mysteries, and friendly quests.'],
  ['kid_lina', 'Lina Leaf', 9, ['nature', 'photos'], 'I take photos of leaves and skies.'],
  ['kid_sam', 'Sam Spark', 11, ['science', 'robotics'], 'Safe experiments and tiny robots.'],
  ['kid_gia', 'Gia Game', 10, ['games', 'coding'], 'Pixel art, mini games, and level design.'],
  ['kid_vinh', 'Vinh Vega', 12, ['space', 'math'], 'I like constellations and logic games.'],
  ['kid_trang', 'Trang Trail', 13, ['travel', 'photography'], 'Weekend walks and photo albums.'],
  ['kid_hieu', 'Hieu Hero', 11, ['teamwork', 'stories'], 'I like helping friends finish challenges.'],
];

const GROUPS = [
  ['space_club', 'Space Explorers', 'space', 'Talk about stars, planets and rockets.', 8, 14],
  ['art_room', 'Color Studio', 'art', 'Share drawings, crafts and friendly feedback.', 7, 12],
  ['code_lab', 'Code Lab Kids', 'coding', 'Build small games and learn code together.', 10, 14],
  ['book_corner', 'Book Corner', 'books', 'Stories, reviews and favorite characters.', 8, 14],
  ['nature_walk', 'Nature Walkers', 'nature', 'Leaves, birds, weather and outdoor photos.', 7, 14],
  ['music_stage', 'Music Stage', 'music', 'Songs, instruments and rhythm games.', 7, 14],
  ['sports_team', 'Friendly Sports', 'sports', 'Practice notes and teamwork moments.', 9, 14],
  ['robot_club', 'Robot Club', 'robotics', 'Safe builds, circuits and robot ideas.', 10, 14],
  ['story_camp', 'Story Camp', 'stories', 'Short stories and creative prompts.', 8, 13],
  ['photo_circle', 'Photo Circle', 'photography', 'Safe photo sharing and composition tips.', 10, 14],
];

const THEMES = [
  ['space', 'I made a paper rocket and named it Spark One.', 'space,rocket', 'excited', 'Space Rocket', '2563eb'],
  ['art', 'Today I tried drawing with only three colors.', 'art,drawing', 'creative', 'Three Color Art', 'ec4899'],
  ['books', 'I finished a mystery story and liked the ending.', 'books,stories', 'curious', 'Book Review', '7c3aed'],
  ['coding', 'My maze game finally has a finish line.', 'coding,games', 'proud', 'Maze Game', '059669'],
  ['sports', 'Our team practiced passing and cheering kindly.', 'sports,teamwork', 'energetic', 'Team Practice', 'f97316'],
  ['nature', 'I found three different leaf shapes on a walk.', 'nature,photos', 'calm', 'Leaf Walk', '16a34a'],
  ['music', 'I learned a new rhythm and clapped it twice.', 'music,dance', 'happy', 'New Rhythm', '0891b2'],
  ['science', 'We tested which paper bridge could hold more coins.', 'science,school', 'focused', 'Science Bridge', '0f766e'],
  ['robotics', 'My cardboard robot got a shiny button panel.', 'robotics,makers', 'proud', 'Robot Build', '64748b'],
  ['craft', 'I made a thank-you card with paper stars.', 'craft,kindness', 'kind', 'Paper Stars', 'db2777'],
  ['weather', 'The clouds looked like soft mountains after school.', 'weather,nature', 'peaceful', 'Cloud Watch', '0284c7'],
  ['photography', 'I took a safe photo of our class garden.', 'photography,garden', 'bright', 'Garden Photo', '65a30d'],
];

const COMMENTS = [
  'This looks really fun!',
  'Nice idea. I want to try this too.',
  'Your post made me smile.',
  'Great job sharing this.',
  'That sounds like a cool project.',
  'I like the colors in this.',
  'Can you share more next time?',
  'That is a very creative idea.',
  'I learned something from this.',
  'Keep going, this is awesome.',
];

const REACTIONS = ['heart', 'star', 'laugh', 'wow', 'clap'];

function getArg(name) {
  const index = process.argv.indexOf(`--${name}`);
  if (index === -1) return undefined;
  const value = process.argv[index + 1];
  if (!value || value.startsWith('--')) return '';
  return value;
}

function avatarUrl(seed) {
  return `https://api.dicebear.com/9.x/adventurer/png?seed=${encodeURIComponent(seed)}`;
}

function imageUrl(seed, text, color = '33b8ff', width = 900, height = 620) {
  return `https://placehold.co/${width}x${height}/${color}/ffffff.png?text=${encodeURIComponent(text)}&font=montserrat`;
}

function toSnapshot(user) {
  return {
    displayName: user.displayName,
    username: user.username,
    avatarUrl: user.avatarUrl || '',
  };
}

function pick(array, index) {
  return array[index % array.length];
}

async function clearRichData(seedUserIds) {
  if (seedUserIds.length === 0) return;

  const userFilter = { $in: seedUserIds };
  const ownedGroupIds = await Group.find({ ownerId: userFilter }).distinct('_id');
  const authoredPostIds = await Post.find({ authorId: userFilter }).distinct('_id');
  const chatIds = await Chat.find({ memberIds: userFilter }).distinct('_id');
  const targetIds = [
    ...seedUserIds.map((id) => id.toString()),
    ...ownedGroupIds.map((id) => id.toString()),
    ...authoredPostIds.map((id) => id.toString()),
  ];

  if (authoredPostIds.length > 0) {
    await Comment.deleteMany({ postId: { $in: authoredPostIds } });
    await PostReaction.deleteMany({ postId: { $in: authoredPostIds } });
    await PostBookmark.deleteMany({ postId: { $in: authoredPostIds } });
  }

  await Comment.deleteMany({ authorId: userFilter });
  await Post.deleteMany({ authorId: userFilter });
  await PostReaction.deleteMany({ userId: userFilter });
  await PostBookmark.deleteMany({ userId: userFilter });

  if (chatIds.length > 0) {
    await Message.deleteMany({ chatId: { $in: chatIds } });
  }
  await Message.deleteMany({ senderId: userFilter });
  await Chat.deleteMany({ memberIds: userFilter });

  await GroupMember.deleteMany({
    $or: [{ userId: userFilter }, { groupId: { $in: ownedGroupIds } }],
  });
  await Group.deleteMany({ ownerId: userFilter });

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
  await Report.deleteMany({
    $or: [{ reporterId: userFilter }, { targetId: { $in: targetIds } }],
  });
  await MediaAsset.deleteMany({ ownerId: userFilter });
  await Photo.deleteMany({ ownerId: userFilter });
}

async function seedUsers(passwordHash) {
  const users = [];

  for (let index = 0; index < USERS.length; index += 1) {
    const [username, displayName, age, favoriteTopics, bio] = USERS[index];
    const coverText = `${displayName} cover`;
    const user = await User.findOneAndUpdate(
      { username },
      {
        $set: {
          username,
          displayName,
          age,
          role: 'CHILD',
          moderationStatus: 'ACTIVE',
          avatarUrl: avatarUrl(username),
          coverUrl: imageUrl(`${username}-cover`, coverText, pick(['33b8ff', '7c3aed', '059669', 'f97316', 'ec4899'], index), 1200, 420),
          bio,
          favoriteTopics,
          isActive: true,
          passwordHash,
          privacy: {
            allowFriendRequests: true,
            allowComments: true,
            safeSearchOnly: true,
          },
        },
      },
      {
        upsert: true,
        returnDocument: 'after',
        runValidators: true,
        setDefaultsOnInsert: true,
      },
    );

    users.push(user);
  }

  return users;
}

async function seedProfileMedia(users) {
  const docs = [];
  const photos = [];

  for (const user of users) {
    docs.push({
      ownerId: user._id,
      sourceType: 'PROFILE',
      sourceId: user._id,
      publicId: `${RICH_PREFIX}/avatar/${user.username}`,
      secureUrl: user.avatarUrl,
      resourceType: 'image',
      format: 'png',
      originalFilename: `${user.username}-avatar.png`,
      mimeType: 'image/png',
      status: 'APPROVED',
      moderation: {
        provider: 'seed',
        decision: 'APPROVED',
        mediaType: 'image',
        topLabel: 'safe',
        topScore: 1,
        unsafeScore: 0,
        checkedAt: new Date(),
      },
    });

    docs.push({
      ownerId: user._id,
      sourceType: 'PROFILE',
      sourceId: user._id,
      publicId: `${RICH_PREFIX}/cover/${user.username}`,
      secureUrl: user.coverUrl,
      resourceType: 'image',
      format: 'png',
      originalFilename: `${user.username}-cover.png`,
      mimeType: 'image/png',
      status: 'APPROVED',
      moderation: {
        provider: 'seed',
        decision: 'APPROVED',
        mediaType: 'image',
        topLabel: 'safe',
        topScore: 1,
        unsafeScore: 0,
        checkedAt: new Date(),
      },
    });
  }

  const assets = await MediaAsset.insertMany(docs);
  for (let index = 0; index < assets.length; index += 2) {
    const avatarAsset = assets[index];
    const coverAsset = assets[index + 1];
    photos.push({
      ownerId: avatarAsset.ownerId,
      mediaAssetId: avatarAsset._id,
      caption: 'Profile avatar',
      album: 'profile',
      visibility: 'PUBLIC',
      status: 'PUBLISHED',
    });
    photos.push({
      ownerId: coverAsset.ownerId,
      mediaAssetId: coverAsset._id,
      caption: 'Profile cover',
      album: 'cover',
      visibility: 'PUBLIC',
      status: 'PUBLISHED',
    });
  }
  await Photo.insertMany(photos);
}

async function seedGroups(users) {
  const groups = [];

  for (let index = 0; index < GROUPS.length; index += 1) {
    const [key, name, topic, description, ageMin, ageMax] = GROUPS[index];
    const owner = users[index % users.length];
    const memberUsers = [
      owner,
      users[(index + 3) % users.length],
      users[(index + 7) % users.length],
      users[(index + 11) % users.length],
      users[(index + 15) % users.length],
    ];

    const group = await Group.create({
      name,
      topic,
      description,
      ageMin,
      ageMax,
      ownerId: owner._id,
      memberCount: memberUsers.length,
      status: 'ACTIVE',
    });

    await GroupMember.insertMany(
      memberUsers.map((user, memberIndex) => ({
        groupId: group._id,
        userId: user._id,
        role: memberIndex === 0 ? 'OWNER' : 'MEMBER',
        status: 'ACTIVE',
      })),
    );

    groups.push({ key, group, members: memberUsers });
  }

  return groups;
}

async function seedFriendships(users) {
  const pairs = new Set();
  const docs = [];

  for (let index = 0; index < users.length; index += 1) {
    for (let offset = 1; offset <= 5; offset += 1) {
      const left = users[index];
      const right = users[(index + offset) % users.length];
      const pair = normalizeFriendPair(left._id, right._id);
      const key = `${pair.userAId}:${pair.userBId}`;
      if (!pairs.has(key)) {
        pairs.add(key);
        docs.push(pair);
      }
    }
  }

  await Friendship.insertMany(docs);

  const requestPairs = new Set();
  const requests = [];
  let cursor = 0;
  while (requests.length < 20 && cursor < users.length * 4) {
    const sender = users[(cursor * 2) % users.length];
    const receiver = users[(cursor * 2 + 9) % users.length];
    const key = `${sender._id.toString()}:${receiver._id.toString()}`;
    cursor += 1;
    if (sender._id.equals(receiver._id) || requestPairs.has(key)) {
      continue;
    }
    requestPairs.add(key);
    requests.push({
      senderId: sender._id,
      receiverId: receiver._id,
      status: pick(['PENDING', 'PENDING', 'REJECTED', 'CANCELLED'], requests.length),
    });
  }
  await FriendRequest.insertMany(requests);
}

async function seedPosts(users, groups) {
  const posts = [];
  const mediaAssets = [];

  for (let userIndex = 0; userIndex < users.length; userIndex += 1) {
    const author = users[userIndex];
    for (let postIndex = 0; postIndex < 3; postIndex += 1) {
      const theme = pick(THEMES, userIndex * 3 + postIndex);
      const [topic, content, rawTopics, mood, imageText, color] = theme;
      const groupInfo = postIndex === 2 ? groups[userIndex % groups.length] : null;
      const mediaUrl = imageUrl(
        `${author.username}-${postIndex}`,
        `${imageText} by ${author.displayName.split(' ')[0]}`,
        color,
      );
      const post = await Post.create({
        authorId: author._id,
        authorSnapshot: toSnapshot(author),
        content,
        topics: rawTopics.split(','),
        mood,
        mediaUrls: [mediaUrl],
        audience: groupInfo ? 'GROUP' : pick(['PUBLIC', 'FRIENDS', 'PUBLIC'], postIndex),
        groupId: groupInfo ? groupInfo.group._id : null,
        allowComments: true,
        allowReactions: true,
        ageMin: Math.max(7, author.age - 1),
        ageMax: 14,
        reactionCount: 0,
        commentCount: 0,
        status: 'PUBLISHED',
      });

      posts.push(post);
      mediaAssets.push({
        ownerId: author._id,
        sourceType: 'POST',
        sourceId: post._id,
        publicId: `${RICH_PREFIX}/post/${post._id.toString()}`,
        secureUrl: mediaUrl,
        resourceType: 'image',
        format: 'png',
        originalFilename: `${topic}-${post._id.toString()}.png`,
        mimeType: 'image/png',
        status: 'APPROVED',
        moderation: {
          provider: 'seed',
          decision: 'APPROVED',
          mediaType: 'image',
          topLabel: 'safe',
          topScore: 1,
          unsafeScore: 0,
          checkedAt: new Date(),
        },
      });
    }
  }

  await MediaAsset.insertMany(mediaAssets);
  return posts;
}

async function seedCommentsReactionsAndBookmarks(users, posts) {
  const commentDocs = [];
  const reactionDocs = [];
  const bookmarkDocs = [];

  for (let index = 0; index < posts.length; index += 1) {
    const post = posts[index];
    const commenters = [
      users[(index + 1) % users.length],
      users[(index + 6) % users.length],
    ];

    for (let commentIndex = 0; commentIndex < commenters.length; commentIndex += 1) {
      const author = commenters[commentIndex];
      commentDocs.push({
        postId: post._id,
        authorId: author._id,
        authorSnapshot: toSnapshot(author),
        content: pick(COMMENTS, index + commentIndex),
        status: 'PUBLISHED',
        likeCount: (index + commentIndex) % 4,
      });
    }

    for (let offset = 1; offset <= 6; offset += 1) {
      const user = users[(index + offset) % users.length];
      reactionDocs.push({
        postId: post._id,
        userId: user._id,
        reaction: pick(REACTIONS, index + offset),
      });
    }

    for (let offset = 7; offset <= 9; offset += 1) {
      bookmarkDocs.push({
        postId: post._id,
        userId: users[(index + offset) % users.length]._id,
      });
    }
  }

  await Comment.insertMany(commentDocs);
  await PostReaction.insertMany(reactionDocs);
  await PostBookmark.insertMany(bookmarkDocs);

  for (const post of posts) {
    const [commentCount, reactionCount] = await Promise.all([
      Comment.countDocuments({ postId: post._id, status: 'PUBLISHED' }),
      PostReaction.countDocuments({ postId: post._id }),
    ]);
    await Post.updateOne({ _id: post._id }, { $set: { commentCount, reactionCount } });
  }
}

async function seedChats(users) {
  const chatDocs = [];

  for (let index = 0; index < 15; index += 1) {
    const left = users[index];
    const right = users[(index + 1) % users.length];
    chatDocs.push({
      type: 'DIRECT',
      members: [left, right],
      createdBy: left,
      messages: [
        [left, 'Hi! Did you see the new posts today?'],
        [right, 'Yes, the art and space posts were my favorites.'],
        [left, 'Let us try a friendly challenge tomorrow.'],
      ],
    });
  }

  for (let index = 0; index < 5; index += 1) {
    const members = [
      users[index],
      users[(index + 4) % users.length],
      users[(index + 8) % users.length],
      users[(index + 12) % users.length],
    ];
    chatDocs.push({
      type: 'GROUP',
      members,
      createdBy: members[0],
      messages: [
        [members[0], 'Group idea: share one kind thing today.'],
        [members[1], 'I helped clean the classroom board.'],
        [members[2], 'I shared my pencils during art time.'],
        [members[3], 'I cheered for my friend during practice.'],
      ],
    });
  }

  for (const item of chatDocs) {
    const memberIds = item.members.map((user) => user._id.toString());
    if (item.type === 'DIRECT') {
      memberIds.sort();
    }

    const chat = await Chat.create({
      type: item.type,
      memberIds,
      createdBy: item.createdBy._id,
    });

    await Message.insertMany(
      item.messages.map(([sender, content]) => ({
        chatId: chat._id,
        senderId: sender._id,
        content,
        mediaUrls: [],
        status: 'SENT',
      })),
    );
  }
}

async function seedReportsAndNotifications(users, posts, groups) {
  const reports = [];
  for (let index = 0; index < 18; index += 1) {
    const targetPost = posts[(index * 3) % posts.length];
    reports.push({
      reporterId: users[(index + 2) % users.length]._id,
      targetType: pick(['POST', 'COMMENT', 'GROUP', 'MESSAGE', 'USER'], index),
      targetId: index % 4 === 0
        ? groups[index % groups.length].group._id.toString()
        : targetPost._id.toString(),
      category: pick(['SPAM', 'UNSAFE_CONTENT', 'BULLYING', 'PRIVATE_INFO', 'OTHER'], index),
      details: pick([
        'Please review this item for safety.',
        'This looks confusing and may need admin review.',
        'I want an adult to check this content.',
        'The content may not match the community rules.',
      ], index),
      urgency: (index % 5) + 1,
      status: pick(['PENDING', 'PENDING', 'REVIEWING', 'RESOLVED', 'DISMISSED'], index),
    });
  }
  const createdReports = await Report.insertMany(reports);

  const notifications = [];
  for (let index = 0; index < 60; index += 1) {
    const user = users[index % users.length];
    notifications.push({
      userId: user._id,
      type: pick([
        'FRIEND_REQUEST_RECEIVED',
        'POST_REACTION',
        'COMMENT_CREATED',
        'GROUP_UPDATE',
        'REPORT_STATUS_UPDATED',
        'SYSTEM_BROADCAST',
      ], index),
      payload: {
        seed: RICH_PREFIX,
        fromUserId: users[(index + 5) % users.length]._id.toString(),
        postId: posts[index % posts.length]._id.toString(),
        reportId: createdReports[index % createdReports.length]._id.toString(),
      },
      readAt: index % 3 === 0 ? new Date() : null,
    });
  }
  await Notification.insertMany(notifications);

  await Block.create({
    blockerId: users[0]._id,
    blockedId: users[users.length - 1]._id,
  });
}

async function main() {
  const password = getArg('password') || process.env.SEED_PASSWORD || DEFAULT_PASSWORD;
  if (password.length < 6) {
    throw new Error('Password must be at least 6 characters.');
  }

  await connectDB();
  const passwordHash = await bcrypt.hash(password, 10);

  const users = await seedUsers(passwordHash);
  const userIds = users.map((user) => user._id);
  await clearRichData(userIds);

  const freshUsers = await seedUsers(passwordHash);
  await seedProfileMedia(freshUsers);
  const groups = await seedGroups(freshUsers);
  await seedFriendships(freshUsers);
  const posts = await seedPosts(freshUsers, groups);
  await seedCommentsReactionsAndBookmarks(freshUsers, posts);
  await seedChats(freshUsers);
  await seedReportsAndNotifications(freshUsers, posts, groups);

  const groupIds = groups.map((item) => item.group._id);
  const chatIds = await Chat.find({ memberIds: { $in: userIds } }).distinct('_id');

  console.log('\nRich seed data created:');
  console.log(`- users with avatars/covers: ${freshUsers.length}`);
  console.log(`- profile media assets: ${await MediaAsset.countDocuments({ ownerId: { $in: userIds }, sourceType: 'PROFILE' })}`);
  console.log(`- groups: ${await Group.countDocuments({ _id: { $in: groupIds } })}`);
  console.log(`- posts with images: ${await Post.countDocuments({ authorId: { $in: userIds }, mediaUrls: { $ne: [] } })}`);
  console.log(`- comments: ${await Comment.countDocuments({ authorId: { $in: userIds } })}`);
  console.log(`- reactions: ${await PostReaction.countDocuments({ userId: { $in: userIds } })}`);
  console.log(`- bookmarks: ${await PostBookmark.countDocuments({ userId: { $in: userIds } })}`);
  console.log(`- chats: ${await Chat.countDocuments({ _id: { $in: chatIds } })}`);
  console.log(`- messages: ${await Message.countDocuments({ chatId: { $in: chatIds } })}`);
  console.log(`- reports: ${await Report.countDocuments({ reporterId: { $in: userIds } })}`);
  console.log(`- notifications: ${await Notification.countDocuments({ userId: { $in: userIds } })}`);

  console.log('\nLogin samples:');
  console.log(`- username=${freshUsers[0].username} password=${password}`);
  console.log(`- username=${freshUsers[1].username} password=${password}`);
  console.log(`- username=${freshUsers[2].username} password=${password}`);
}

main()
  .catch((error) => {
    console.error('Rich seed failed:', error);
    process.exitCode = 1;
  })
  .finally(async () => {
    try {
      await mongoose.disconnect();
    } catch {
      // ignore disconnect errors
    }
  });
