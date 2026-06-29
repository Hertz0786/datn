const nodemailer = require('nodemailer');

const user = 'nhanhieu0401@gmail.com';
const pass = 'hrmmsrbvegajjnxa';

async function test() {
  console.log('Using user:', user);
  console.log('Using pass length:', pass.length, '(first 4 chars):', pass.slice(0, 4));

  const transporter = nodemailer.createTransport({
    host: 'smtp.gmail.com',
    port: 587,
    secure: false,
    auth: { user, pass },
    tls: { rejectUnauthorized: false },
  });

  try {
    await transporter.sendMail({
      from: '"Kiddo" <' + user + '>',
      to: user,
      subject: 'Test email from Kiddo',
      text: 'This is a test.',
    });
    console.log('SUCCESS: Email sent!');
  } catch (err) {
    console.error('FAILED:', err.message);
    if (err.code) console.error('Code:', err.code);
    if (err.response) console.error('Response:', err.response);
  }
}

test();
