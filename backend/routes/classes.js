// Class routes for teachers, mounted at /api/classes (JWT + teacher role).
//
//   GET    /                                 my classes with counts
//   POST   /                                 create { name, subject?, section?, description? }
//   GET    /dashboard                        numbers for the teacher home screen
//   GET    /:class_id                        one class
//   PUT    /:class_id                        update
//   DELETE /:class_id                        delete (roster, attendance, announcements; exams are kept)
//   POST   /:class_id/join-code              issue a new join code
//
//   GET    /:class_id/students               roster, pending requests first
//   POST   /:class_id/students               add { name, roll_number, email?, create_login? }
//   PATCH  /:class_id/students/:student_id   approve { status:'active' } or edit name / roll
//   DELETE /:class_id/students/:student_id   remove from class (or reject a request)
//   POST   /:class_id/students/:student_id/reset-password   new temporary password
//   GET    /:class_id/students/:student_id/report           one student's results + attendance
//
//   GET    /:class_id/exams                  exams of the class
//   GET    /:class_id/attendance             sessions with daily rate
//   GET    /:class_id/attendance/:date       roster with that day's status (YYYY-MM-DD)
//   PUT    /:class_id/attendance/:date       save { records: [{student_id, status}], note? }
//   GET    /:class_id/announcements          list
//   POST   /:class_id/announcements          post { title, body }, notifies students
//   DELETE /:class_id/announcements/:id
//   GET    /:class_id/analytics              charts + leaderboard + at-risk list
//   GET    /:class_id/reports/results.csv    student x exam matrix
//   GET    /:class_id/reports/attendance.csv student x date matrix
//
// Roster entries ("students" here) are class_students rows; they may or may
// not have a user account.

const crypto = require('crypto');
const express = require('express');
const bcrypt = require('bcrypt');
const pool = require('../config/db');
const { classParam } = require('../middleware/ownership');
const { classAnalytics, latestResults, attendanceCounts, attendanceRate } = require('../services/analytics');
const { classStudentUserIds, notify } = require('../services/notify');

const router = express.Router();
router.param('class_id', classParam);

const UNIQUE_VIOLATION = '23505';
const ATTENDANCE_STATUSES = ['present', 'absent', 'late', 'excused'];
// No 0/O/1/I so codes are easy to read aloud and type.
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function newJoinCode() {
  let code = '';
  for (let i = 0; i < 6; i++) code += CODE_ALPHABET[crypto.randomInt(CODE_ALPHABET.length)];
  return code;
}

function temporaryPassword() {
  return `${newJoinCode().toLowerCase()}${crypto.randomInt(10, 100)}`;
}

function cleanText(value, max) {
  const text = String(value ?? '').trim();
  return text ? text.slice(0, max) : null;
}

function isIsoDate(value) {
  return /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(value));
}

function csvCell(value) {
  const text = value === null || value === undefined ? '' : String(value);
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

function sendCsv(res, fileName, rows) {
  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="${fileName}"`);
  return res.send(rows.map((row) => row.map(csvCell).join(',')).join('\r\n'));
}

const CLASS_LIST_SQL = `
  SELECT c.*,
         (SELECT COUNT(*) FROM class_students s WHERE s.class_id = c.id AND s.status = 'active')::int AS student_count,
         (SELECT COUNT(*) FROM class_students s WHERE s.class_id = c.id AND s.status = 'pending')::int AS pending_count,
         (SELECT COUNT(*) FROM exams e WHERE e.class_id = c.id)::int AS exam_count,
         (SELECT MAX(session_date) FROM attendance_sessions a WHERE a.class_id = c.id) AS last_attendance
    FROM classes c`;

// ---------------------------------------------------------------- classes

router.get('/', async (req, res) => {
  const result = await pool.query(
    `${CLASS_LIST_SQL} WHERE c.teacher_id = $1 ORDER BY c.created_at DESC`,
    [req.user.id],
  );
  return res.json({ classes: result.rows });
});

router.post('/', async (req, res) => {
  const name = cleanText(req.body?.name, 120);
  if (!name) return res.status(400).json({ message: 'Class name is required' });

  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      const result = await pool.query(
        `INSERT INTO classes (id, teacher_id, name, subject, section, description, join_code)
         VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
        [crypto.randomUUID(), req.user.id, name, cleanText(req.body.subject, 120),
          cleanText(req.body.section, 60), cleanText(req.body.description, 2000), newJoinCode()],
      );
      return res.status(201).json({ class: { ...result.rows[0], student_count: 0, pending_count: 0, exam_count: 0 } });
    } catch (error) {
      if (error.code !== UNIQUE_VIOLATION) throw error; // join-code collision: retry
    }
  }
  return res.status(500).json({ message: 'Could not create class' });
});

// The teacher home screen: class-level numbers only.
router.get('/dashboard', async (req, res) => {
  const classes = (await pool.query(
    `${CLASS_LIST_SQL} WHERE c.teacher_id = $1 ORDER BY c.created_at DESC`,
    [req.user.id],
  )).rows;
  const ids = classes.map((c) => c.id);
  // The app sends its local date; the server clock is UTC.
  const today = isIsoDate(String(req.query.date || ''))
    ? req.query.date
    : new Date().toISOString().slice(0, 10);

  const [attendanceToday, recentExams, unpublished] = await Promise.all([
    pool.query(
      `SELECT s.class_id,
              COUNT(*) FILTER (WHERE ar.status IN ('present', 'late'))::int AS attended,
              COUNT(*) FILTER (WHERE ar.status <> 'excused')::int AS counted
         FROM attendance_sessions s
         JOIN attendance_records ar ON ar.session_id = s.id
        WHERE s.class_id = ANY($1::uuid[]) AND s.session_date = $2
        GROUP BY s.class_id`,
      [ids, today],
    ),
    pool.query(
      `SELECT e.id, e.title, e.subject, e.class_id, e.created_at, e.results_published_at,
              e.total_questions, e.roll_digits, e.registration_digits, c.name AS class_name,
              (SELECT COUNT(*) FROM exam_results r WHERE r.exam_id = e.id)::int AS graded
         FROM exams e LEFT JOIN classes c ON c.id = e.class_id
        WHERE e.user_id = $1
        ORDER BY e.created_at DESC LIMIT 5`,
      [req.user.id],
    ),
    pool.query(
      `SELECT COUNT(*)::int AS n FROM exams e
        WHERE e.user_id = $1 AND e.class_id IS NOT NULL AND e.results_published_at IS NULL
          AND EXISTS (SELECT 1 FROM exam_results r WHERE r.exam_id = e.id)`,
      [req.user.id],
    ),
  ]);

  const todayByClass = Object.fromEntries(attendanceToday.rows.map((r) => [r.class_id, r]));
  return res.json({
    summary: {
      classes: classes.length,
      students: classes.reduce((n, c) => n + c.student_count, 0),
      pending_requests: classes.reduce((n, c) => n + c.pending_count, 0),
      exams: classes.reduce((n, c) => n + c.exam_count, 0),
      attendance_taken_today: attendanceToday.rows.length,
      unpublished_exams: unpublished.rows[0].n,
    },
    classes: classes.map((c) => {
      const t = todayByClass[c.id];
      return {
        ...c,
        attendance_today: t && t.counted > 0 ? Math.round((t.attended / t.counted) * 100) : null,
      };
    }),
    recent_exams: recentExams.rows,
  });
});

router.get('/:class_id', async (req, res) => {
  const result = await pool.query(`${CLASS_LIST_SQL} WHERE c.id = $1`, [req.params.class_id]);
  return res.json({ class: result.rows[0] });
});

router.put('/:class_id', async (req, res) => {
  const name = cleanText(req.body?.name, 120);
  if (!name) return res.status(400).json({ message: 'Class name is required' });
  const result = await pool.query(
    `UPDATE classes SET name = $1, subject = $2, section = $3, description = $4
      WHERE id = $5 RETURNING *`,
    [name, cleanText(req.body.subject, 120), cleanText(req.body.section, 60),
      cleanText(req.body.description, 2000), req.params.class_id],
  );
  return res.json({ class: result.rows[0] });
});

router.delete('/:class_id', async (req, res) => {
  await pool.query('DELETE FROM classes WHERE id = $1', [req.params.class_id]);
  return res.json({ message: 'Class deleted' });
});

router.post('/:class_id/join-code', async (req, res) => {
  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      const result = await pool.query(
        'UPDATE classes SET join_code = $1 WHERE id = $2 RETURNING join_code',
        [newJoinCode(), req.params.class_id],
      );
      return res.json({ join_code: result.rows[0].join_code });
    } catch (error) {
      if (error.code !== UNIQUE_VIOLATION) throw error;
    }
  }
  return res.status(500).json({ message: 'Could not create a new code' });
});

// ---------------------------------------------------------------- roster

async function findStudent(classId, studentId) {
  try {
    const result = await pool.query(
      `SELECT cs.*, u.username, u.email AS account_email
         FROM class_students cs LEFT JOIN users u ON u.id = cs.user_id
        WHERE cs.id = $1 AND cs.class_id = $2`,
      [studentId, classId],
    );
    return result.rows[0];
  } catch (error) {
    if (error.code === '22P02') return undefined; // not a uuid
    throw error;
  }
}

// Roll numbers are compared without leading zeros, like result matching.
async function rollTaken(classId, rollNumber, exceptId = null) {
  const result = await pool.query(
    `SELECT 1 FROM class_students
      WHERE class_id = $1 AND ltrim(roll_number, '0') = ltrim($2, '0')
        AND ($3::uuid IS NULL OR id <> $3)`,
    [classId, rollNumber, exceptId],
  );
  return result.rows.length > 0;
}

router.get('/:class_id/students', async (req, res) => {
  const { class_id: classId } = req.params;
  const [roster, counts] = await Promise.all([
    pool.query(
      `SELECT cs.id, cs.name, cs.roll_number, cs.email, cs.status, cs.created_at,
              cs.user_id, u.username, u.email AS account_email,
              (u.avatar IS NOT NULL) AS has_avatar, u.avatar_updated_at
         FROM class_students cs LEFT JOIN users u ON u.id = cs.user_id
        WHERE cs.class_id = $1
        ORDER BY (cs.status = 'pending') DESC, cs.roll_number`,
      [classId],
    ),
    attendanceCounts([classId]),
  ]);
  return res.json({
    students: roster.rows.map((s) => ({
      ...s,
      has_account: s.user_id !== null,
      attendance_rate: attendanceRate(counts[s.id]),
    })),
  });
});

router.post('/:class_id/students', async (req, res) => {
  const { class_id: classId } = req.params;
  const name = cleanText(req.body?.name, 120);
  const rollNumber = cleanText(req.body?.roll_number, 32);
  const email = cleanText(req.body?.email, 255)?.toLowerCase() || null;
  if (!name || !rollNumber) return res.status(400).json({ message: 'Name and roll number are required' });
  if (!/^\d+$/.test(rollNumber)) return res.status(400).json({ message: 'Roll number must contain digits only' });
  if (await rollTaken(classId, rollNumber)) {
    return res.status(409).json({ message: `Roll number ${rollNumber} is already in this class` });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    let userId = null;
    let credentials = null;

    if (req.body.create_login) {
      const code = (await client.query('SELECT join_code FROM classes WHERE id = $1', [classId])).rows[0].join_code;
      const username = `${code}-${rollNumber}`.toLowerCase();
      const password = temporaryPassword();
      const user = await client.query(
        `INSERT INTO users (name, username, password_hash, role, must_change_password)
         VALUES ($1, $2, $3, 'student', true) RETURNING id`,
        [name, username, await bcrypt.hash(password, 12)],
      );
      userId = user.rows[0].id;
      credentials = { username, password };
    }

    const inserted = await client.query(
      `INSERT INTO class_students (id, class_id, user_id, name, roll_number, email, status)
       VALUES ($1, $2, $3, $4, $5, $6, 'active') RETURNING *`,
      [crypto.randomUUID(), classId, userId, name, rollNumber, email],
    );
    await client.query('COMMIT');
    // The temporary password is only ever returned here.
    return res.status(201).json({ student: { ...inserted.rows[0], has_account: userId !== null }, credentials });
  } catch (error) {
    await client.query('ROLLBACK');
    if (error.code === UNIQUE_VIOLATION) {
      return res.status(409).json({ message: 'A student with that roll number or login already exists' });
    }
    throw error;
  } finally {
    client.release();
  }
});

router.patch('/:class_id/students/:student_id', async (req, res) => {
  const { class_id: classId, student_id: studentId } = req.params;
  const student = await findStudent(classId, studentId);
  if (!student) return res.status(404).json({ message: 'student not found' });

  const name = cleanText(req.body?.name, 120) || student.name;
  const rollNumber = cleanText(req.body?.roll_number, 32) || student.roll_number;
  const status = req.body?.status === 'active' ? 'active' : student.status;
  if (!/^\d+$/.test(rollNumber)) return res.status(400).json({ message: 'Roll number must contain digits only' });
  if (rollNumber !== student.roll_number && await rollTaken(classId, rollNumber, studentId)) {
    return res.status(409).json({ message: `Roll number ${rollNumber} is already in this class` });
  }

  const result = await pool.query(
    'UPDATE class_students SET name = $1, roll_number = $2, status = $3 WHERE id = $4 RETURNING *',
    [name, rollNumber, status, studentId],
  );
  if (student.status === 'pending' && status === 'active' && student.user_id) {
    const cls = (await pool.query('SELECT name FROM classes WHERE id = $1', [classId])).rows[0];
    notify([student.user_id], {
      type: 'enrolment_approved',
      title: `You joined ${cls.name}`,
      body: 'Your teacher approved your request.',
      data: { class_id: classId },
    });
  }
  return res.json({ student: result.rows[0] });
});

router.delete('/:class_id/students/:student_id', async (req, res) => {
  const { class_id: classId, student_id: studentId } = req.params;
  const student = await findStudent(classId, studentId);
  if (!student) return res.status(404).json({ message: 'student not found' });
  await pool.query('DELETE FROM class_students WHERE id = $1', [studentId]);
  return res.json({ message: 'Student removed' });
});

// Only for accounts the teacher created (username logins). Students who signed
// up with their own email use "Forgot password" instead.
router.post('/:class_id/students/:student_id/reset-password', async (req, res) => {
  const student = await findStudent(req.params.class_id, req.params.student_id);
  if (!student) return res.status(404).json({ message: 'student not found' });
  if (!student.user_id || !student.username) {
    return res.status(400).json({ message: 'Only logins created by you can be reset here' });
  }
  const password = temporaryPassword();
  await pool.query(
    'UPDATE users SET password_hash = $1, must_change_password = true WHERE id = $2',
    [await bcrypt.hash(password, 12), student.user_id],
  );
  return res.json({ credentials: { username: student.username, password } });
});

router.get('/:class_id/students/:student_id/report', async (req, res) => {
  const { class_id: classId, student_id: studentId } = req.params;
  const student = await findStudent(classId, studentId);
  if (!student) return res.status(404).json({ message: 'student not found' });

  const [rows, counts, records] = await Promise.all([
    latestResults([classId]),
    attendanceCounts([classId]),
    pool.query(
      `SELECT s.session_date, ar.status
         FROM attendance_records ar JOIN attendance_sessions s ON s.id = ar.session_id
        WHERE ar.class_student_id = $1 ORDER BY s.session_date DESC`,
      [studentId],
    ),
  ]);
  const results = rows
    .filter((r) => r.student_id === studentId)
    .sort((a, b) => new Date(a.exam_date) - new Date(b.exam_date))
    .map((r) => ({
      result_id: r.id, exam_id: r.exam_id, exam_title: r.exam_title, date: r.exam_date,
      percentage: r.percentage, marks: r.marks, max_marks: r.max_marks, grade: r.grade,
      passed: r.passed, rank: r.rank, out_of: r.exam_takers, class_average: r.exam_average,
    }));
  return res.json({
    student: {
      id: student.id, name: student.name, roll_number: student.roll_number, status: student.status,
      has_account: student.user_id !== null, username: student.username, email: student.account_email || student.email,
    },
    results,
    attendance: { ...(counts[studentId] || {}), rate: attendanceRate(counts[studentId]), records: records.rows },
  });
});

// ---------------------------------------------------------------- exams

router.get('/:class_id/exams', async (req, res) => {
  const result = await pool.query(
    `SELECT e.*, (SELECT COUNT(*) FROM exam_results r WHERE r.exam_id = e.id)::int AS graded
       FROM exams e WHERE e.class_id = $1 ORDER BY e.created_at DESC`,
    [req.params.class_id],
  );
  return res.json({ exams: result.rows });
});

// ---------------------------------------------------------------- attendance

router.get('/:class_id/attendance', async (req, res) => {
  const result = await pool.query(
    `SELECT s.id, s.session_date, s.note,
            COUNT(*) FILTER (WHERE ar.status = 'present')::int AS present,
            COUNT(*) FILTER (WHERE ar.status = 'late')::int AS late,
            COUNT(*) FILTER (WHERE ar.status = 'absent')::int AS absent,
            COUNT(*) FILTER (WHERE ar.status = 'excused')::int AS excused
       FROM attendance_sessions s
       LEFT JOIN attendance_records ar ON ar.session_id = s.id
      WHERE s.class_id = $1
      GROUP BY s.id ORDER BY s.session_date DESC LIMIT 120`,
    [req.params.class_id],
  );
  return res.json({ sessions: result.rows });
});

router.get('/:class_id/attendance/:date', async (req, res) => {
  const { class_id: classId, date } = req.params;
  if (!isIsoDate(date)) return res.status(400).json({ message: 'Date must be YYYY-MM-DD' });
  const session = (await pool.query(
    'SELECT id, note FROM attendance_sessions WHERE class_id = $1 AND session_date = $2',
    [classId, date],
  )).rows[0];
  const roster = await pool.query(
    `SELECT cs.id AS student_id, cs.name, cs.roll_number, ar.status
       FROM class_students cs
       LEFT JOIN attendance_records ar ON ar.class_student_id = cs.id AND ar.session_id = $2
      WHERE cs.class_id = $1 AND cs.status = 'active'
      ORDER BY cs.roll_number`,
    [classId, session?.id || null],
  );
  return res.json({
    date,
    taken: Boolean(session),
    note: session?.note || '',
    records: roster.rows,
  });
});

router.put('/:class_id/attendance/:date', async (req, res) => {
  const { class_id: classId, date } = req.params;
  if (!isIsoDate(date)) return res.status(400).json({ message: 'Date must be YYYY-MM-DD' });
  const records = Array.isArray(req.body?.records) ? req.body.records : null;
  if (!records) return res.status(400).json({ message: 'records array is required' });
  if (records.some((r) => !ATTENDANCE_STATUSES.includes(r?.status))) {
    return res.status(400).json({ message: `status must be one of ${ATTENDANCE_STATUSES.join(', ')}` });
  }

  const roster = await pool.query(
    `SELECT id, user_id FROM class_students WHERE class_id = $1 AND status = 'active'`,
    [classId],
  );
  const rosterIds = new Map(roster.rows.map((r) => [r.id, r.user_id]));
  const valid = records.filter((r) => rosterIds.has(r.student_id));

  const client = await pool.connect();
  let previouslyAbsent = new Set();
  try {
    await client.query('BEGIN');
    const session = await client.query(
      `INSERT INTO attendance_sessions (id, class_id, session_date, note)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (class_id, session_date)
       DO UPDATE SET note = EXCLUDED.note, updated_at = now()
       RETURNING id`,
      [crypto.randomUUID(), classId, date, cleanText(req.body.note, 500)],
    );
    const sessionId = session.rows[0].id;
    previouslyAbsent = new Set((await client.query(
      `SELECT class_student_id FROM attendance_records WHERE session_id = $1 AND status = 'absent'`,
      [sessionId],
    )).rows.map((r) => r.class_student_id));

    for (const record of valid) {
      await client.query(
        `INSERT INTO attendance_records (session_id, class_student_id, status)
         VALUES ($1, $2, $3)
         ON CONFLICT (session_id, class_student_id) DO UPDATE SET status = EXCLUDED.status`,
        [sessionId, record.student_id, record.status],
      );
    }
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }

  // Tell newly-absent students (not again on every re-save).
  const absentees = valid
    .filter((r) => r.status === 'absent' && !previouslyAbsent.has(r.student_id))
    .map((r) => rosterIds.get(r.student_id));
  if (absentees.length) {
    const cls = (await pool.query('SELECT name FROM classes WHERE id = $1', [classId])).rows[0];
    notify(absentees, {
      type: 'attendance_absent',
      title: `Marked absent in ${cls.name}`,
      body: `You were marked absent on ${date}.`,
      data: { class_id: classId, date },
    });
  }
  return res.json({ message: 'Attendance saved', saved: valid.length });
});

// ---------------------------------------------------------------- announcements

router.get('/:class_id/announcements', async (req, res) => {
  const result = await pool.query(
    `SELECT a.*, u.name AS author_name FROM announcements a JOIN users u ON u.id = a.author_id
      WHERE a.class_id = $1 ORDER BY a.created_at DESC LIMIT 100`,
    [req.params.class_id],
  );
  return res.json({ announcements: result.rows });
});

router.post('/:class_id/announcements', async (req, res) => {
  const { class_id: classId } = req.params;
  const title = cleanText(req.body?.title, 200);
  const body = cleanText(req.body?.body, 5000) || '';
  if (!title) return res.status(400).json({ message: 'Title is required' });

  const result = await pool.query(
    `INSERT INTO announcements (id, class_id, author_id, title, body)
     VALUES ($1, $2, $3, $4, $5) RETURNING *`,
    [crypto.randomUUID(), classId, req.user.id, title, body],
  );
  const cls = (await pool.query('SELECT name FROM classes WHERE id = $1', [classId])).rows[0];
  notify(await classStudentUserIds(classId), {
    type: 'announcement',
    title: `${cls.name}: ${title}`,
    body: body.slice(0, 180),
    data: { class_id: classId, announcement_id: result.rows[0].id },
  });
  return res.status(201).json({ announcement: result.rows[0] });
});

router.delete('/:class_id/announcements/:announcement_id', async (req, res) => {
  try {
    await pool.query(
      'DELETE FROM announcements WHERE id = $1 AND class_id = $2',
      [req.params.announcement_id, req.params.class_id],
    );
  } catch (error) {
    if (error.code !== '22P02') throw error;
  }
  return res.json({ message: 'Announcement deleted' });
});

// ---------------------------------------------------------------- analytics & reports

router.get('/:class_id/analytics', async (req, res) => {
  return res.json(await classAnalytics(req.params.class_id));
});

router.get('/:class_id/reports/results.csv', async (req, res) => {
  const analytics = await classAnalytics(req.params.class_id);
  const rows = await latestResults([req.params.class_id]);
  const header = ['Roll', 'Name', ...analytics.exams.map((e) => `${e.title} (%)`), 'Average (%)', 'Attendance (%)'];
  const lines = analytics.students.map((s) => [
    s.roll_number,
    s.name,
    ...analytics.exams.map((e) => rows.find((r) => r.exam_id === e.id && r.student_id === s.id)?.percentage ?? ''),
    s.average ?? '',
    s.attendance_rate ?? '',
  ]);
  return sendCsv(res, 'class-results.csv', [header, ...lines]);
});

router.get('/:class_id/reports/attendance.csv', async (req, res) => {
  const { class_id: classId } = req.params;
  const [sessions, roster, records, counts] = await Promise.all([
    pool.query('SELECT id, session_date FROM attendance_sessions WHERE class_id = $1 ORDER BY session_date', [classId]),
    pool.query(`SELECT id, name, roll_number FROM class_students WHERE class_id = $1 AND status = 'active' ORDER BY roll_number`, [classId]),
    pool.query(
      `SELECT ar.* FROM attendance_records ar JOIN attendance_sessions s ON s.id = ar.session_id WHERE s.class_id = $1`,
      [classId],
    ),
    attendanceCounts([classId]),
  ]);
  const status = new Map(records.rows.map((r) => [`${r.session_id}:${r.class_student_id}`, r.status]));
  const dates = sessions.rows.map((s) => s.session_date);
  const lines = roster.rows.map((st) => [
    st.roll_number,
    st.name,
    ...sessions.rows.map((s) => status.get(`${s.id}:${st.id}`) || ''),
    attendanceRate(counts[st.id]) ?? '',
  ]);
  return sendCsv(res, 'class-attendance.csv', [['Roll', 'Name', ...dates, 'Attendance (%)'], ...lines]);
});

module.exports = router;
