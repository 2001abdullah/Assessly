// Profile routes, mounted at /api/profile (JWT, any role).
//
//   GET    /                 my profile
//   PUT    /                 update { name, phone, institution, bio }
//   PUT    /password         { current_password?, new_password }
//   PUT    /avatar           multipart 'avatar' (JPEG/PNG, <= 1 MB; the app resizes to 512 px)
//   DELETE /avatar
//   GET    /avatar/:user_id  the picture, for myself or someone who shares a class with me
//
// Pictures are stored in the database (users.avatar) because the hosting
// plan has no persistent disk.

const express = require('express');
const bcrypt = require('bcrypt');
const multer = require('multer');
const pool = require('../config/db');

const router = express.Router();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 1024 * 1024 } });

const PROFILE_SQL = `
  SELECT u.id, u.name, u.email, u.username, u.role, u.phone, u.institution, u.bio,
         u.created_at, u.must_change_password, u.google_subject IS NOT NULL AS google_linked,
         u.password_hash IS NOT NULL AS has_password,
         u.avatar IS NOT NULL AS has_avatar, u.avatar_updated_at
    FROM users u WHERE u.id = $1`;

async function loadProfile(userId) {
  return (await pool.query(PROFILE_SQL, [userId])).rows[0] || null;
}

function cleanText(value, max) {
  const text = String(value ?? '').trim();
  return text ? text.slice(0, max) : null;
}

// JPEG (FF D8 FF) or PNG (89 50 4E 47) by content, not by the client's claim.
function imageType(buffer) {
  if (buffer.length > 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) return 'image/jpeg';
  if (buffer.length > 4 && buffer.subarray(0, 4).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47]))) return 'image/png';
  return null;
}

router.get('/', async (req, res) => {
  const profile = await loadProfile(req.user.id);
  if (!profile) return res.status(404).json({ message: 'user not found' });
  return res.json({ user: profile });
});

router.put('/', async (req, res) => {
  const name = cleanText(req.body?.name, 100);
  if (!name) return res.status(400).json({ message: 'Name is required' });
  await pool.query(
    'UPDATE users SET name = $1, phone = $2, institution = $3, bio = $4 WHERE id = $5',
    [name, cleanText(req.body.phone, 40), cleanText(req.body.institution, 160),
      cleanText(req.body.bio, 500), req.user.id],
  );
  // Keep the roster name in step for students.
  await pool.query('UPDATE class_students SET name = $1 WHERE user_id = $2', [name, req.user.id]);
  return res.json({ user: await loadProfile(req.user.id) });
});

// The current password is required unless the account has none yet (Google
// sign-up) or is on a teacher-issued temporary password.
router.put('/password', async (req, res) => {
  const current = String(req.body?.current_password || '');
  const next = String(req.body?.new_password || '');
  if (next.length < 8) return res.status(400).json({ message: 'New password must be at least 8 characters' });

  const user = (await pool.query(
    'SELECT password_hash, must_change_password FROM users WHERE id = $1',
    [req.user.id],
  )).rows[0];
  if (!user) return res.status(404).json({ message: 'user not found' });
  if (user.password_hash && !(await bcrypt.compare(current, user.password_hash))) {
    return res.status(400).json({ message: 'Current password is incorrect' });
  }
  await pool.query(
    'UPDATE users SET password_hash = $1, must_change_password = false WHERE id = $2',
    [await bcrypt.hash(next, 12), req.user.id],
  );
  return res.json({ message: 'Password updated' });
});

router.put('/avatar', upload.single('avatar'), async (req, res) => {
  const buffer = req.file?.buffer;
  if (!buffer) return res.status(400).json({ message: 'avatar image is required' });
  if (!imageType(buffer)) return res.status(400).json({ message: 'Use a JPEG or PNG image' });
  await pool.query(
    'UPDATE users SET avatar = $1, avatar_updated_at = now() WHERE id = $2',
    [buffer, req.user.id],
  );
  return res.json({ user: await loadProfile(req.user.id) });
});

router.delete('/avatar', async (req, res) => {
  await pool.query('UPDATE users SET avatar = NULL, avatar_updated_at = now() WHERE id = $1', [req.user.id]);
  return res.json({ user: await loadProfile(req.user.id) });
});

// Visible to the owner, to a student's teachers, and to a teacher's students.
router.get('/avatar/:user_id', async (req, res) => {
  const target = Number(req.params.user_id);
  if (!Number.isInteger(target)) return res.status(404).end();
  if (target !== req.user.id) {
    const related = await pool.query(
      `SELECT 1 FROM class_students cs JOIN classes c ON c.id = cs.class_id
        WHERE (cs.user_id = $1 AND c.teacher_id = $2)
           OR (cs.user_id = $2 AND c.teacher_id = $1)
        LIMIT 1`,
      [target, req.user.id],
    );
    if (!related.rows.length) return res.status(404).end();
  }
  const row = (await pool.query('SELECT avatar FROM users WHERE id = $1', [target])).rows[0];
  if (!row?.avatar) return res.status(404).end();
  res.setHeader('Content-Type', imageType(row.avatar) || 'application/octet-stream');
  res.setHeader('Cache-Control', 'private, max-age=86400');
  return res.send(row.avatar);
});

module.exports = router;
module.exports.loadProfile = loadProfile;
