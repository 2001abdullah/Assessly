// Account routes, mounted at /api/auth (public, rate-limited in server.js).
//
//   POST   /register         create a password account { name, email, password, role? }
//   POST   /login            { email (or username), password, role? } -> { token, user }
//   POST   /google           { id_token, role? }                      -> { token, user }
//   POST   /forgot-password  email a 6-digit reset code (always 202)
//   POST   /reset-password   email + code + new password
//   GET    /me               profile of the token's user        (JWT required)
//   DELETE /me               delete the account and all its data (JWT required)
//
// Roles: 'teacher' (default) or 'student'. The app sends the role of the
// portal the user chose; signing in to the wrong portal gets a 403 that says
// which one to use. A student account created by a teacher has a username
// (e.g. "ab12cd-15") instead of an email.
//
// Emails are stored lower-cased and compared case-insensitively.

const crypto = require('crypto');
const express = require('express');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const { OAuth2Client } = require('google-auth-library');
const pool = require('../config/db');
const authMiddleware = require('../middleware/authMiddleware');
const { sendPasswordResetCode } = require('../services/email');
const { loadProfile } = require('./profile');

const router = express.Router();
const googleClient = new OAuth2Client();

const BCRYPT_ROUNDS = 12;
const MIN_PASSWORD_LENGTH = 8;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const UNIQUE_VIOLATION = '23505';

// Same answer whether or not the account exists, so the endpoint cannot be
// used to discover which emails are registered.
const genericResetMessage = {
  message: 'If that account exists, a reset code has been sent.',
};
const invalidCredentials = { message: 'Invalid email or password' };

const ROLES = ['teacher', 'student'];

function normalizeEmail(value) {
  return String(value || '').trim().toLowerCase();
}

// Undefined when the client did not say (older app versions: teacher).
function requestedRole(body) {
  const role = String(body?.role || '').toLowerCase();
  return ROLES.includes(role) ? role : undefined;
}

function wrongPortal(res, actualRole) {
  return res.status(403).json({
    message: actualRole === 'student'
      ? 'This is a student account. Go back and choose "I\'m a student".'
      : 'This is a teacher account. Go back and choose "I\'m a teacher".',
    role: actualRole,
  });
}

function hashResetCode(code) {
  return crypto.createHash('sha256').update(code).digest('hex');
}

// Signs a JWT for the user. The payload is what authMiddleware exposes as
// req.user on later requests.
function createSession(user) {
  const role = user.role || 'teacher';
  const token = jwt.sign(
    { id: user.id, email: user.email, name: user.name, role },
    process.env.JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN || '7d' },
  );
  return {
    message: 'login successful',
    token,
    user: {
      id: user.id,
      name: user.name,
      email: user.email,
      username: user.username || null,
      role,
      must_change_password: Boolean(user.must_change_password),
    },
  };
}

router.post('/register', async (req, res) => {
  const name = String(req.body?.name || '').trim();
  const email = normalizeEmail(req.body?.email);
  const password = String(req.body?.password || '');

  if (!name || !email || !password) {
    return res.status(400).json({ message: 'name, email and password are required' });
  }
  if (password.length < MIN_PASSWORD_LENGTH) {
    return res.status(400).json({ message: 'password must be at least 8 characters' });
  }
  if (!EMAIL_PATTERN.test(email)) {
    return res.status(400).json({ message: 'Please enter a valid email address' });
  }

  try {
    const passwordHash = await bcrypt.hash(password, BCRYPT_ROUNDS);
    const insertResult = await pool.query(
      `INSERT INTO users (name, email, password_hash, role)
       VALUES ($1, $2, $3, $4)
       RETURNING id, name, email, role, created_at`,
      [name.slice(0, 100), email, passwordHash, requestedRole(req.body) || 'teacher'],
    );
    return res.status(201).json({
      message: 'user registered successfully',
      user: insertResult.rows[0],
    });
  } catch (error) {
    // The UNIQUE(email) constraint is the source of truth, which also covers
    // two sign-ups racing with the same address.
    if (error.code === UNIQUE_VIOLATION) {
      return res.status(409).json({ message: 'email already registered' });
    }
    console.error('registration error:', error.message);
    return res.status(500).json({ message: 'something went wrong while registering the user' });
  }
});

router.post('/login', async (req, res) => {
  // "email" may also be a username issued by a teacher (no "@").
  const login = normalizeEmail(req.body?.email || req.body?.username);
  const password = String(req.body?.password || '');
  if (!login || !password) {
    return res.status(400).json({ message: 'email and password are required' });
  }

  try {
    const result = await pool.query(
      `SELECT id, name, email, username, role, must_change_password, password_hash
         FROM users WHERE ${login.includes('@') ? 'lower(email)' : 'lower(username)'} = $1`,
      [login],
    );
    const user = result.rows[0];
    // Unknown email and wrong password get the same 401 so the endpoint does
    // not reveal which accounts exist.
    if (!user) return res.status(401).json(invalidCredentials);
    if (!user.password_hash) {
      return res.status(400).json({ message: 'Use Google to sign in to this account' });
    }
    if (!(await bcrypt.compare(password, user.password_hash))) {
      return res.status(401).json(invalidCredentials);
    }
    // Checked only after the password, so it reveals nothing to a stranger.
    const role = requestedRole(req.body);
    if (role && role !== user.role) return wrongPortal(res, user.role);
    return res.status(200).json(createSession(user));
  } catch (error) {
    console.error('login error', error.message);
    return res.status(500).json({ message: 'something went wrong while logging in' });
  }
});

// Verifies a Google ID token and signs the user in, creating the account on
// first use. An existing password account with the same verified email is
// linked; an account already linked to a different Google identity is refused.
router.post('/google', async (req, res) => {
  const idToken = req.body?.id_token;
  const audience = process.env.GOOGLE_CLIENT_ID;
  if (!idToken) return res.status(400).json({ message: 'Google ID token is required' });
  if (!audience) return res.status(503).json({ message: 'Google sign-in is not configured' });

  try {
    const ticket = await googleClient.verifyIdToken({ idToken, audience });
    const payload = ticket.getPayload();
    if (!payload?.sub || !payload.email || payload.email_verified !== true) {
      return res.status(401).json({ message: 'Google account could not be verified' });
    }

    const name = String(payload.name || payload.email.split('@')[0]).slice(0, 100);
    const email = normalizeEmail(payload.email);
    // The requested role only applies when this creates the account.
    const role = requestedRole(req.body);
    const userResult = await pool.query(
      `INSERT INTO users (name, email, google_subject, role)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (email) DO UPDATE
         SET google_subject = COALESCE(users.google_subject, EXCLUDED.google_subject),
             name = CASE WHEN users.name = '' THEN EXCLUDED.name ELSE users.name END
       WHERE users.google_subject IS NULL
          OR users.google_subject = EXCLUDED.google_subject
       RETURNING id, name, email, username, role, must_change_password`,
      [name, email, payload.sub, role || 'teacher'],
    );
    const user = userResult.rows[0];
    if (!user) {
      return res.status(409).json({ message: 'Google account does not match the linked account' });
    }
    if (role && role !== user.role) return wrongPortal(res, user.role);
    return res.status(200).json(createSession(user));
  } catch (error) {
    console.error('Google login error', error.message);
    return res.status(401).json({ message: 'Google sign-in failed' });
  }
});

// Only a SHA-256 hash of the code is stored; codes are single-use and expire
// after 15 minutes. Requesting a new code invalidates the previous one.
router.post('/forgot-password', async (req, res) => {
  const email = normalizeEmail(req.body?.email);
  if (!email) return res.status(400).json({ message: 'email is required' });

  try {
    const userResult = await pool.query(
      'SELECT id, email FROM users WHERE lower(email) = $1',
      [email],
    );
    if (!userResult.rows.length) return res.status(202).json(genericResetMessage);

    const user = userResult.rows[0];
    const code = crypto.randomInt(100000, 1000000).toString();
    await pool.query('DELETE FROM password_reset_tokens WHERE user_id = $1', [user.id]);
    await pool.query(
      `INSERT INTO password_reset_tokens (id, user_id, token_hash, expires_at)
       VALUES ($1, $2, $3, now() + interval '15 minutes')`,
      [crypto.randomUUID(), user.id, hashResetCode(code)],
    );
    await sendPasswordResetCode({ email: user.email, code });
    return res.status(202).json(genericResetMessage);
  } catch (error) {
    console.error('password reset request error:', error.message);
    return res.status(202).json(genericResetMessage);
  }
});

router.post('/reset-password', async (req, res) => {
  const email = normalizeEmail(req.body?.email);
  const code = String(req.body?.code || '').trim();
  const password = String(req.body?.password || '');
  if (!email || !/^\d{6}$/.test(code) || password.length < MIN_PASSWORD_LENGTH) {
    return res.status(400).json({ message: 'Valid email, 6-digit code, and 8-character password are required' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // FOR UPDATE stops two concurrent requests from using the same code.
    const tokenResult = await client.query(
      `SELECT prt.id, prt.user_id
         FROM password_reset_tokens prt
         JOIN users u ON u.id = prt.user_id
        WHERE lower(u.email) = $1 AND prt.token_hash = $2
          AND prt.used_at IS NULL AND prt.expires_at > now()
        FOR UPDATE`,
      [email, hashResetCode(code)],
    );
    if (!tokenResult.rows.length) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: 'Reset code is invalid or expired' });
    }
    const { id: tokenId, user_id: userId } = tokenResult.rows[0];
    const passwordHash = await bcrypt.hash(password, BCRYPT_ROUNDS);
    await client.query('UPDATE users SET password_hash = $1 WHERE id = $2', [passwordHash, userId]);
    await client.query('UPDATE password_reset_tokens SET used_at = now() WHERE id = $1', [tokenId]);
    await client.query('COMMIT');
    return res.status(200).json({ message: 'Password reset successfully' });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('password reset error:', error.message);
    return res.status(500).json({ message: 'Could not reset password' });
  } finally {
    client.release();
  }
});

router.get('/me', authMiddleware, async (req, res) => {
  try {
    const user = await loadProfile(req.user.id);
    if (!user) {
      return res.status(404).json({ message: 'user not found' });
    }
    return res.json({ message: 'authenticated user', user });
  } catch (error) {
    console.error('profile error', error.message);
    return res.status(500).json({ message: 'could not load profile' });
  }
});

// Permanently removes the signed-in user and everything they own. Deleting
// the exams cascades to answer keys, scoring rules, scans, answers and
// results; reset tokens cascade from the user row.
router.delete('/me', authMiddleware, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('DELETE FROM exams WHERE user_id = $1', [req.user.id]);
    // A student's pending join requests go; approved roster entries stay with
    // the teacher's class (unlinked from the deleted account).
    await client.query(
      `DELETE FROM class_students WHERE user_id = $1 AND status = 'pending'`,
      [req.user.id],
    );
    const deleted = await client.query(
      'DELETE FROM users WHERE id = $1 RETURNING id',
      [req.user.id],
    );
    await client.query('COMMIT');

    if (deleted.rows.length === 0) {
      return res.status(404).json({ message: 'user not found' });
    }
    return res.status(200).json({ message: 'account deleted' });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('account deletion error', error.message);
    return res.status(500).json({ message: 'could not delete account' });
  } finally {
    client.release();
  }
});

module.exports = router;
