// Notification routes, mounted at /api/notifications (JWT, any role).
//
//   GET    /                 latest 100 + unread count
//   POST   /read-all         mark everything read
//   POST   /:id/read         mark one read
//   POST   /devices          register a push token { token, platform }
//   DELETE /devices          forget a push token { token } (on logout)

const express = require('express');
const pool = require('../config/db');

const router = express.Router();

router.get('/', async (req, res) => {
  const [list, unread] = await Promise.all([
    pool.query(
      `SELECT id, type, title, body, data, read_at, created_at
         FROM notifications WHERE user_id = $1
        ORDER BY created_at DESC LIMIT 100`,
      [req.user.id],
    ),
    pool.query(
      'SELECT COUNT(*)::int AS n FROM notifications WHERE user_id = $1 AND read_at IS NULL',
      [req.user.id],
    ),
  ]);
  return res.json({ notifications: list.rows, unread: unread.rows[0].n });
});

router.post('/read-all', async (req, res) => {
  await pool.query(
    'UPDATE notifications SET read_at = now() WHERE user_id = $1 AND read_at IS NULL',
    [req.user.id],
  );
  return res.json({ message: 'ok' });
});

router.post('/:id/read', async (req, res) => {
  try {
    await pool.query(
      'UPDATE notifications SET read_at = COALESCE(read_at, now()) WHERE id = $1 AND user_id = $2',
      [req.params.id, req.user.id],
    );
  } catch (error) {
    if (error.code !== '22P02') throw error;
  }
  return res.json({ message: 'ok' });
});

router.post('/devices', async (req, res) => {
  const token = String(req.body?.token || '').trim();
  if (!token || token.length > 4096) return res.status(400).json({ message: 'token is required' });
  const platform = String(req.body?.platform || 'android').slice(0, 20);
  // A token moves to whoever signed in last on that device.
  await pool.query(
    `INSERT INTO device_tokens (token, user_id, platform) VALUES ($1, $2, $3)
     ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id,
       platform = EXCLUDED.platform, updated_at = now()`,
    [token, req.user.id, platform],
  );
  return res.json({ message: 'ok' });
});

router.delete('/devices', async (req, res) => {
  await pool.query(
    'DELETE FROM device_tokens WHERE token = $1 AND user_id = $2',
    [String(req.body?.token || ''), req.user.id],
  );
  return res.json({ message: 'ok' });
});

module.exports = router;
