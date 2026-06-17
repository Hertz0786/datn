const jwt = require('jsonwebtoken');
const env = require('../config/env');

function createAuthToken(user) {
  return jwt.sign(
    {
      sub: user._id.toString(),
      role: user.role,
      age: user.age,
      username: user.username,
    },
    env.jwtSecret,
    { expiresIn: '7d' },
  );
}

module.exports = {
  createAuthToken,
};

