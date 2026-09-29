// Student routes, mounted at /api/student (JWT + student role).
//
//   GET    /overview              dashboard: averages, trend, grades, rank, attendance
//   GET    /classes               my classes (active and pending)
//   POST   /classes/join          { code, roll_number, name? } -> join request
//   DELETE /classes/:class_id     leave a class
//   GET    /results               my published results, newest first
//   GET    /results/:result_id    one result with the per-question breakdown
//   GET    /attendance            my attendance per class with the day-by-day list
//   GET    /announcements         announcements from my active classes
//
// A student only ever sees their own marks. Class context is limited to
// averages, the highest score and their rank; never other students' names.

const crypto = require('crypto');
const express = require('express');
const pool = require('../config/db');
const {
  attendanceCounts, attendanceRate, enrolmentsForUser, studentOverview, studentResults,
} = require('../services/analytics');
const { notify } = require('../services/notify');
const { resultDetails } = require('./results');

const router = express.Router();

router.get('/overview', async (req, res) => {
  return res.json(await studentOverview(req.user.id));
});

router.get('/classes', async (req, res) => {
  return res.json({ classes: await enrolmentsForUser(req.user.id) });
});

router.post('/classes/join', async (req, res) => {
  const code = String(req.body?.code || '').trim().toUpperCase();
  const rollNumber = String(req.body?.roll_number || '').trim();
  if (!code || !rollNumber) return res.status(400).json({ message: 'Class code and roll number are required' });
  if (!/^\d{1,32}$/.test(rollNumber)) return res.status(400).json({ message: 'Roll number must contain digits only' });

  const cls = (await pool.query(
    'SELECT id, name, teacher_id FROM classes WHERE join_code = $1',
    [code],
  )).rows[0];
  if (!cls) return res.status(404).json({ message: 'No class has that code' });

  const already = (await pool.query(
    'SELECT status FROM class_students WHERE class_id = $1 AND user_id = $2',
    [cls.id, req.user.id],
  )).rows[0];
  if (already) {
    return res.status(409).json({
      message: already.status === 'pending' ? 'Your request is waiting for approval' : 'You are already in this class',
    });
  }

  const me = (await pool.query('SELECT name, email FROM users WHERE id = $1', [req.user.id])).rows[0];
  const name = String(req.body?.name || me.name).trim().slice(0, 120) || me.name;
  const existing = (await pool.query(
    `SELECT id, user_id FROM class_students
      WHERE class_id = $1 AND ltrim(roll_number, '0') = ltrim($2, '0')`,
    [cls.id, rollNumber],
  )).rows[0];

  if (existing?.user_id) {
    return res.status(409).json({ message: 'That roll number is already taken in this class. Check it with your teacher.' });
  }
  if (existing) {
    // The teacher already added this roll without an account: claim it. It
    // stays pending until the teacher confirms it is really this student.
    await pool.query(
      `UPDATE class_students SET user_id = $1, status = 'pending' WHERE id = $2`,
      [req.user.id, existing.id],
    );
  } else {
    await pool.query(
      `INSERT INTO class_students (id, class_id, user_id, name, roll_number, email, status)
       VALUES ($1, $2, $3, $4, $5, $6, 'pending')`,
      [crypto.randomUUID(), cls.id, req.user.id, name, rollNumber, me.email],
    );
  }

  notify([cls.teacher_id], {
    type: 'join_request',
    title: `Join request for ${cls.name}`,
    body: `${name} (roll ${rollNumber}) wants to join.`,
    data: { class_id: cls.id },
  });
  return res.status(201).json({ message: 'Request sent. Your teacher needs to approve it.', class: { id: cls.id, name: cls.name } });
});

router.delete('/classes/:class_id', async (req, res) => {
  try {
    await pool.query(
      'DELETE FROM class_students WHERE class_id = $1 AND user_id = $2',
      [req.params.class_id, req.user.id],
    );
  } catch (error) {
    if (error.code !== '22P02') throw error;
  }
  return res.json({ message: 'You left the class' });
});

router.get('/results', async (req, res) => {
  return res.json({ results: await studentResults(req.user.id) });
});

// Only a result that is the student's own AND published is visible.
router.get('/results/:result_id', async (req, res) => {
  const mine = (await studentResults(req.user.id)).find((r) => r.result_id === req.params.result_id);
  if (!mine) return res.status(404).json({ message: 'Result not found' });
  const details = await resultDetails(req.params.result_id);
  if (!details) return res.status(404).json({ message: 'Result not found' });
  return res.json({
    result: {
      ...details,
      rank: mine.rank,
      out_of: mine.out_of,
      class_average: mine.class_average,
      class_highest: mine.class_highest,
    },
  });
});

router.get('/attendance', async (req, res) => {
  const enrolments = (await enrolmentsForUser(req.user.id)).filter((e) => e.status === 'active');
  const counts = await attendanceCounts(enrolments.map((e) => e.class_id));
  const records = enrolments.length
    ? (await pool.query(
      `SELECT ar.class_student_id, s.session_date, ar.status
         FROM attendance_records ar JOIN attendance_sessions s ON s.id = ar.session_id
        WHERE ar.class_student_id = ANY($1::uuid[])
        ORDER BY s.session_date DESC`,
      [enrolments.map((e) => e.student_id)],
    )).rows
    : [];
  return res.json({
    classes: enrolments.map((e) => {
      const c = counts[e.student_id] || { present: 0, late: 0, absent: 0, excused: 0, total: 0 };
      return {
        class_id: e.class_id,
        class_name: e.class_name,
        ...c,
        rate: attendanceRate(c),
        records: records
          .filter((r) => r.class_student_id === e.student_id)
          .map((r) => ({ date: r.session_date, status: r.status })),
      };
    }),
  });
});

router.get('/announcements', async (req, res) => {
  const result = await pool.query(
    `SELECT a.id, a.title, a.body, a.created_at, c.id AS class_id, c.name AS class_name,
            u.name AS author_name
       FROM announcements a
       JOIN classes c ON c.id = a.class_id
       JOIN users u ON u.id = a.author_id
       JOIN class_students cs ON cs.class_id = c.id AND cs.user_id = $1 AND cs.status = 'active'
      ORDER BY a.created_at DESC LIMIT 100`,
    [req.user.id],
  );
  return res.json({ announcements: result.rows });
});

module.exports = router;
