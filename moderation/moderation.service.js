const axios = require('axios');
const nsfwjs = require('nsfwjs');
const FlaggedContent = require('./FlaggedContent');
const Notification = require('../models/notification.model');
const User = require('../models/user.model');
const { getReceiverSocketId, io } = require('../lib/socket');
const sensitiveWords = require('./sensitiveWords');


// Load the NSFWJS model.
let nsfwModel;
(async () => {
  nsfwModel = await nsfwjs.load();
  console.log('NSFWJS model loaded.');
})();

const { createCanvas, loadImage } = require('canvas');

const checkImageForInappropriateContent = async (imageUrl) => {
  try {
    if (!nsfwModel) {
      console.warn('NSFW model is not ready yet.');
      return false;
    }

    const response = await axios.get(imageUrl, { responseType: 'arraybuffer' });
    const imageBuffer = Buffer.from(response.data, 'binary');

    const img = await loadImage(imageBuffer);
    const canvas = createCanvas(img.width, img.height);
    const ctx = canvas.getContext('2d');
    ctx.drawImage(img, 0, 0, img.width, img.height);

    const predictions = await nsfwModel.classify(canvas);
    console.log('Predictions:', predictions);

    const porn = predictions.find(p => p.className === 'Porn')?.probability || 0;
    const sexy = predictions.find(p => p.className === 'Sexy')?.probability || 0;
    const hentai = predictions.find(p => p.className === 'Hentai')?.probability || 0;
    const drawing = predictions.find(p => p.className === 'Drawing')?.probability || 0;

    const isFlagged = (porn > 0.4 || sexy > 0.4 || hentai > 0.4 || drawing > 0.7);

    return isFlagged;
  } catch (error) {
    console.error('Error moderating image with NSFWJS:', error.message);
    return false;
  }
};



const notifyAdmins = async (message, fromUserId) => {
  try {
    const admins = await User.find({ role: 'admin' });

    const notifications = admins.map(admin => ({
      from: fromUserId,
      to: admin._id,
      type: 'moderation',
      reason: message,
    }));

    await Notification.insertMany(notifications);

    admins.forEach(admin => {
      if (admin.socketId) {
        io.to(admin.socketId).emit('newNotification', {
          message,
          fromUserId,
        });
      }
    });
  } catch (err) {
    console.error('Error sending moderation notification to admins:', err);
  }
};

const moderatePostContent = async (post) => {
  const reasons = [];

  const allBadWords = [
    ...sensitiveWords.vulgar,
    ...sensitiveWords.privacy,
    ...sensitiveWords.racist,
    ...sensitiveWords.sexist,
    ...sensitiveWords.suicide,
  ];

  if (post.text) {
    const text = post.text.toLowerCase();
    const detectedWords = allBadWords.filter(word => text.includes(word.toLowerCase()));
    if (detectedWords.length > 0) {
      reasons.push(`Inappropriate text: ${detectedWords.join(', ')}`);
    }
  }

if (post.image) {
  const response = await axios.get(post.image, { responseType: 'arraybuffer' });
  const imageBuffer = Buffer.from(response.data, 'binary');
  const img = await loadImage(imageBuffer);
  const canvas = createCanvas(img.width, img.height);
  const ctx = canvas.getContext('2d');
  ctx.drawImage(img, 0, 0, img.width, img.height);

  const predictions = await nsfwModel.classify(canvas);
  console.log('Predictions:', predictions);

  const reasonsMap = {
    'Porn': 0.4,
    'Sexy': 0.4,
    'Hentai': 0.4,
    'Drawing': 0.7
  };

  for (const pred of predictions) {
    const threshold = reasonsMap[pred.className];
    if (threshold && pred.probability > threshold) {
      reasons.push(`Image flagged for ${pred.className} (${(pred.probability * 100).toFixed(1)}%)`);
    }
  }
}

  if (reasons.length > 0) {
    await FlaggedContent.create({
      post: post._id,
      reason: reasons.join(', '),
    });

    await notifyAdmins(
      `Post ${post._id} flagged. Reason(s): ${reasons.join(', ')}`,
      post.user
    );
  }
};

const moderateCommentContent = async (comment, postId) => {
  const reasons = [];

  const allBadWords = [
    ...sensitiveWords.vulgar,
    ...sensitiveWords.privacy,
    ...sensitiveWords.racist,
    ...sensitiveWords.sexist,
    ...sensitiveWords.suicide,
  ];

  const text = comment.text.toLowerCase();
  const detectedWords = allBadWords.filter(word => text.includes(word.toLowerCase()));
  if (detectedWords.length > 0) {
    reasons.push(`Comment contains inappropriate text: ${detectedWords.join(', ')}`);
  }

  if (reasons.length > 0) {
    await FlaggedContent.create({
      comment: comment,
      post: postId,
      reason: reasons.join(', '),
    });

    await notifyAdmins(
      `Comment flagged on post ${postId}. Reason(s): ${reasons.join(', ')}`,
      comment.user
    );
    return true;
  }

  return false;
};


module.exports = {
  moderatePostContent,
  checkImageForInappropriateContent,
  notifyAdmins,
  moderateCommentContent,
};
