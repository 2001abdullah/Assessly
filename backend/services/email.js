// Outgoing email (password-reset codes) over SMTP.
// Needs SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD and EMAIL_FROM; port
// 465 uses implicit TLS, other ports STARTTLS. Throws if not configured.

const nodemailer = require('nodemailer');

function createTransport() {
  const { SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD } = process.env;
  if (!SMTP_HOST || !SMTP_PORT || !SMTP_USER || !SMTP_PASSWORD) {
    throw new Error('SMTP is not configured');
  }

  return nodemailer.createTransport({
    host: SMTP_HOST,
    port: Number(SMTP_PORT),
    secure: Number(SMTP_PORT) === 465,
    auth: { user: SMTP_USER, pass: SMTP_PASSWORD },
  });
}

async function sendPasswordResetCode({ email, code }) {
  const from = process.env.EMAIL_FROM;
  if (!from) throw new Error('EMAIL_FROM is not configured');

  await createTransport().sendMail({
    from,
    to: email,
    subject: 'Reset your Assessly password',
    text: `Your Assessly password reset code is ${code}. It expires in 15 minutes. If you did not request this, ignore this email.`,
  });
}

module.exports = { sendPasswordResetCode };
