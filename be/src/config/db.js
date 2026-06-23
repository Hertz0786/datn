const mongoose = require('mongoose');
const env = require('./env');

const PASSWORD_PLACEHOLDER_REGEX = /<db_password>|<password>|YOUR_PASSWORD/g;

async function connectDB() {
  if (!env.mongoUri) {
    throw new Error('Missing MONGODB_URI in environment variables.');
  }

  const hasPlaceholder = PASSWORD_PLACEHOLDER_REGEX.test(env.mongoUri);
  PASSWORD_PLACEHOLDER_REGEX.lastIndex = 0; // reset after test so replace() starts from 0
  const mongoUri = hasPlaceholder
    ? env.mongoUri.replace(
        PASSWORD_PLACEHOLDER_REGEX,
        encodeURIComponent(String(env.mongoPassword || '')),
      )
    : env.mongoUri;

  if (hasPlaceholder && !env.mongoPassword) {
    throw new Error(
      'MONGODB_URI contains a password placeholder. Set MONGODB_PASSWORD in .env.',
    );
  }

  mongoose.set('strictQuery', true);
  await mongoose.connect(mongoUri);
  console.log('Connected to MongoDB');
}

module.exports = connectDB;

