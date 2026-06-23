const nodemailer = require('nodemailer');

const env = {
  gmailUser: process.env.GMAIL_USER || '',
  gmailAppPassword: process.env.GMAIL_APP_PASSWORD || '',
  emailFrom: process.env.EMAIL_FROM || 'Kiddo <noreply@kiddo.app>',
};

/** Lazily-created singleton transporter. Nodemailer maintains its own
 *  connection pool internally, so creating the transporter once and
 *  reusing it across requests is both safe and efficient. */
let _transporter = null;

function getTransporter() {
  if (_transporter === null) {
    _transporter = nodemailer.createTransport({
      host: 'smtp.gmail.com',
      port: 587,
      secure: false,
      auth: {
        user: env.gmailUser,
        pass: env.gmailAppPassword,
      },
      tls: {
        rejectUnauthorized: false,
      },
      pool: true,
      maxConnections: 5,
      rateLimit: 10,
    });
  }
  return _transporter;
}

function buildVerificationEmail(code) {
  return {
    subject: 'Kiddo - Ma xac minh email cua ban',
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 24px; background: #F7FBFF; border-radius: 16px;">
        <div style="text-align: center; margin-bottom: 24px;">
          <h1 style="color: #1A3D7C; font-size: 28px; margin: 0;">Kiddo</h1>
          <p style="color: #5A74A6; margin: 4px 0 0;">Ma xac minh email cua ban</p>
        </div>
        <div style="background: white; border-radius: 16px; padding: 32px 24px; text-align: center; box-shadow: 0 2px 12px rgba(0,0,0,0.06);">
          <p style="color: #2A4474; font-size: 16px; margin: 0 0 16px;">Ma xac minh cua ban la:</p>
          <div style="background: linear-gradient(135deg, #33B8FF, #FF9AD5); border-radius: 12px; padding: 20px; margin-bottom: 20px;">
            <span style="font-size: 36px; font-weight: 800; color: white; letter-spacing: 8px; font-family: monospace;">${code}</span>
          </div>
          <p style="color: #5A74A6; font-size: 14px; margin: 0;">Ma co hieu luc trong <strong>10 phut</strong>. Neu ban khong yeu cau dang ky, vui long bo qua email nay.</p>
        </div>
        <p style="text-align: center; color: #8AA4C8; font-size: 12px; margin-top: 20px;">Day la email tu he thong Kiddo. Vui long khong tra loi email nay.</p>
      </div>
    `,
    text: `Kiddo - Ma xac minh email: ${code}. Co hieu luc trong 10 phut.`,
  };
}

function buildPasswordResetEmail(code) {
  return {
    subject: 'Kiddo - Dat lai mat khau',
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 24px; background: #F7FBFF; border-radius: 16px;">
        <div style="text-align: center; margin-bottom: 24px;">
          <h1 style="color: #1A3D7C; font-size: 28px; margin: 0;">Kiddo</h1>
          <p style="color: #5A74A6; margin: 4px 0 0;">Dat lai mat khau</p>
        </div>
        <div style="background: white; border-radius: 16px; padding: 32px 24px; text-align: center; box-shadow: 0 2px 12px rgba(0,0,0,0.06);">
          <p style="color: #2A4474; font-size: 16px; margin: 0 0 16px;">Ma dat lai mat khau cua ban la:</p>
          <div style="background: linear-gradient(135deg, #FF9AD5, #FFC857); border-radius: 12px; padding: 20px; margin-bottom: 20px;">
            <span style="font-size: 36px; font-weight: 800; color: white; letter-spacing: 8px; font-family: monospace;">${code}</span>
          </div>
          <p style="color: #5A74A6; font-size: 14px; margin: 0;">Ma co hieu luc trong <strong>15 phut</strong>. Neu ban khong yeu cau dat lai mat khau, vui long bo qua email nay.</p>
        </div>
        <p style="text-align: center; color: #8AA4C8; font-size: 12px; margin-top: 20px;">Day la email tu he thong Kiddo. Vui long khong tra loi email nay.</p>
      </div>
    `,
    text: `Kiddo - Ma dat lai mat khau: ${code}. Co hieu luc trong 15 phut.`,
  };
}

async function sendEmail(to, mailOptions) {
  if (!env.gmailUser || !env.gmailAppPassword) {
    throw new Error('Email configuration is not set (GMAIL_USER or GMAIL_APP_PASSWORD missing).');
  }

  await getTransporter().sendMail({
    from: env.emailFrom,
    to,
    ...mailOptions,
  });
}

async function sendVerificationCode(email, code) {
  await sendEmail(email, buildVerificationEmail(code));
}

async function sendPasswordResetCode(email, code) {
  await sendEmail(email, buildPasswordResetEmail(code));
}

module.exports = {
  sendVerificationCode,
  sendPasswordResetCode,
};
