// Notifications: an in-app inbox row per user, plus a phone push when
// Firebase is configured.
//
// Push uses the Firebase Cloud Messaging HTTP v1 API. Set
// FIREBASE_SERVICE_ACCOUNT to the service-account JSON (the whole file
// contents) from Firebase console -> Project settings -> Service accounts.
// Without it, only the in-app notifications are created.
//
// Sending never throws: a failed push must not fail the teacher's action.

const crypto = require('crypto');
const { GoogleAuth } = require('google-auth-library');
const pool = require('../config/db');

let firebase; // { projectId, auth } once configured, false when not

function firebaseConfig() {
  if (firebase !== undefined) return firebase;
  try {
    const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
    if (!raw) {
      firebase = false;
      return firebase;
    }
    const credentials = JSON.parse(raw);
    firebase = {
      projectId: credentials.project_id,
      auth: new GoogleAuth({
        credentials,
        scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
      }),
    };
  } catch (error) {
    console.error('FIREBASE_SERVICE_ACCOUNT is not valid JSON:', error.message);
    firebase = false;
  }
  return firebase;
}

async function sendPush(userIds, { title, body, data }) {
  const config = firebaseConfig();
  if (!config || userIds.length === 0) return;

  const tokens = await pool.query(
    'SELECT token FROM device_tokens WHERE user_id = ANY($1::int[])',
    [userIds],
  );
  if (tokens.rows.length === 0) return;

  const accessToken = await config.auth.getAccessToken();
  const url = `https://fcm.googleapis.com/v1/projects/${config.projectId}/messages:send`;
  // FCM data values must be strings.
  const stringData = Object.fromEntries(
    Object.entries(data || {}).map(([key, value]) => [key, String(value)]),
  );

  await Promise.all(tokens.rows.map(async ({ token }) => {
    const response = await fetch(url, {
      method: 'POST',
      headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message: { token, notification: { title, body }, data: stringData },
      }),
    });
    // 404/400 UNREGISTERED: the app was uninstalled or the token rotated.
    if (response.status === 404 || response.status === 400) {
      await pool.query('DELETE FROM device_tokens WHERE token = $1', [token]);
    }
  }));
}

/**
 * Notifies users. `userIds` may contain nulls/duplicates (e.g. roster rows
 * without accounts); they are ignored.
 */
async function notify(userIds, { type, title, body = '', data = {} }) {
  const ids = [...new Set(userIds.filter((id) => id !== null && id !== undefined))];
  if (ids.length === 0) return;
  try {
    const values = [];
    const params = [];
    ids.forEach((userId, i) => {
      const o = i * 6;
      values.push(`($${o + 1}, $${o + 2}, $${o + 3}, $${o + 4}, $${o + 5}, $${o + 6}::jsonb)`);
      params.push(crypto.randomUUID(), userId, type, title, body, JSON.stringify(data));
    });
    await pool.query(
      `INSERT INTO notifications (id, user_id, type, title, body, data) VALUES ${values.join(', ')}`,
      params,
    );
  } catch (error) {
    console.error('notification insert failed:', error.message);
  }
  sendPush(ids, { title, body, data: { type, ...data } })
    .catch((error) => console.error('push failed:', error.message));
}

/** Active roster members of a class who have an account. */
async function classStudentUserIds(classId) {
  const result = await pool.query(
    `SELECT user_id FROM class_students
      WHERE class_id = $1 AND status = 'active' AND user_id IS NOT NULL`,
    [classId],
  );
  return result.rows.map((row) => row.user_id);
}

module.exports = { classStudentUserIds, notify };
