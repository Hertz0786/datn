/* eslint-disable no-console */

const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const mongoose = require('mongoose');

const connectDB = require('../src/config/db');
const User = require('../src/models/User');

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

function generatePassword() {
  // base64url is URL-safe and easy to copy/paste.
  return crypto.randomBytes(12).toString('base64url');
}

async function main() {
  const usernameRaw = getArg('username') || process.env.ADMIN_USERNAME;
  const displayName =
    getArg('displayName') || process.env.ADMIN_DISPLAY_NAME || 'Admin';
  const ageRaw = getArg('age') || process.env.ADMIN_AGE || '12';
  const passwordArg = getArg('password');
  const passwordEnv = process.env.ADMIN_PASSWORD;
  const role = (getArg('role') || process.env.ADMIN_ROLE || 'ADMIN').toUpperCase();

  if (!usernameRaw) {
    console.error(
      'Missing --username (or set ADMIN_USERNAME).\n' +
        'Example: npm run bootstrap:admin -- --username admin',
    );
    process.exitCode = 1;
    return;
  }

  if (!['ADMIN', 'MODERATOR'].includes(role)) {
    console.error('Invalid role. Use ADMIN or MODERATOR.');
    process.exitCode = 1;
    return;
  }

  const username = String(usernameRaw).toLowerCase().trim();
  const age = Number(ageRaw);

  if (!Number.isFinite(age) || age < 7 || age > 14) {
    console.error('Invalid age. Must be between 7 and 14 (per User schema).');
    process.exitCode = 1;
    return;
  }

  const shouldGeneratePassword = !passwordArg && !passwordEnv;
  const password = passwordArg || passwordEnv || generatePassword();

  await connectDB();

  const existing = await User.findOne({ username });

  if (!existing) {
    const passwordHash = await bcrypt.hash(password, 10);
    const user = await User.create({
      displayName: String(displayName).trim(),
      username,
      age,
      passwordHash,
      role,
      isActive: true,
    });

    console.log(`Created ${role} user: ${user.username} (id=${user._id})`);

    if (shouldGeneratePassword) {
      console.log('Generated password (copy it now):');
      console.log(password);
    } else {
      console.log('Password set from args/env (not printed).');
    }

    return;
  }

  const update = { role, isActive: true };
  if (displayName) update.displayName = String(displayName).trim();
  if (hasFlag('set-age')) update.age = age;

  const shouldUpdatePassword = Boolean(passwordArg || passwordEnv);
  if (shouldUpdatePassword) {
    update.passwordHash = await bcrypt.hash(password, 10);
  }

  const user = await User.findByIdAndUpdate(existing._id, { $set: update }, { new: true });

  console.log(`Updated user: ${user.username} (id=${user._id}) -> role=${user.role}`);

  if (shouldGeneratePassword) {
    console.log('No password provided; keeping existing password.');
  } else if (shouldUpdatePassword) {
    console.log('Password updated from args/env (not printed).');
  }
}

main()
  .catch((error) => {
    console.error('Bootstrap admin failed:', error);
    process.exitCode = 1;
  })
  .finally(async () => {
    try {
      await mongoose.disconnect();
    } catch {
      // ignore
    }
  });
