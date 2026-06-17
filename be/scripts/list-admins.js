const mongoose = require('mongoose');
const env = require('../src/config/env');
const User = require('../src/models/User');

(async () => {
  const uri = env.mongoUri.replace(/<db_password>|<password>|YOUR_PASSWORD/g, encodeURIComponent(String(env.mongoPassword || '')));
  await mongoose.connect(uri);
  const users = await User.find({ role: { $in: ['ADMIN', 'MODERATOR'] } }).select('username role displayName createdAt');
  console.log(JSON.stringify(users, null, 2));
  await mongoose.disconnect();
})().catch((e) => { console.error(e); process.exit(1); });
