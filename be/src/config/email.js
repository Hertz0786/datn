const dotenv = require('dotenv');

dotenv.config();

const env = {
  gmailUser: process.env.GMAIL_USER || '',
  gmailAppPassword: process.env.GMAIL_APP_PASSWORD || '',
  emailFrom: process.env.EMAIL_FROM || 'Kiddo <noreply@kiddo.app>',
  emailEnabled: Boolean(process.env.GMAIL_USER && process.env.GMAIL_APP_PASSWORD),
};

module.exports = env;
