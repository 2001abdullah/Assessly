// Class and student analytics, shared by the teacher and student routes.
//
// How results are tied to students: a scanned sheet only carries a roll
// number. A result belongs to the class roster entry whose roll number
// matches, ignoring leading zeros ("0042" == "42"), in the exam's class. When
// a sheet was scanned more than once, only the latest result counts.

const pool = require('../config/db');

// Latest result per (exam, roll) for exams in the given classes, with the
// matching roster entry (if any) and the student's rank within that exam.
const LATEST_RESULTS_SQL = `
  WITH latest AS (
    SELECT DISTINCT ON (r.exam_id, ltrim(r.roll_number, '0'))
           r.*, e.class_id, e.title AS exam_title, e.subject AS exam_subject,
           e.created_at AS exam_date, e.results_published_at
      FROM exam_results r
      JOIN exams e ON e.id = r.exam_id
     WHERE e.class_id = ANY($1::uuid[])
       AND r.roll_number IS NOT NULL AND r.roll_number !~ '[?]'
     ORDER BY r.exam_id, ltrim(r.roll_number, '0'), r.created_at DESC
  )
  SELECT l.*,
         cs.id AS student_id, cs.name AS student_name, cs.user_id AS student_user_id,
         RANK() OVER (PARTITION BY l.exam_id ORDER BY l.marks DESC) AS rank,
         COUNT(*) OVER (PARTITION BY l.exam_id) AS exam_takers,
         AVG(l.percentage) OVER (PARTITION BY l.exam_id) AS exam_average,
         MAX(l.percentage) OVER (PARTITION BY l.exam_id) AS exam_highest
    FROM latest l
    LEFT JOIN class_students cs
      ON cs.class_id = l.class_id AND cs.status = 'active'
     AND ltrim(cs.roll_number, '0') = ltrim(l.roll_number, '0')
`;

const round1 = (value) => Math.round(Number(value) * 10) / 10;
const mean = (values) => (values.length
  ? values.reduce((a, b) => a + b, 0) / values.length
  : null);

async function latestResults(classIds) {
  if (!classIds.length) return [];
  const result = await pool.query(LATEST_RESULTS_SQL, [classIds]);
  return result.rows.map((row) => ({
    ...row,
    marks: Number(row.marks),
    max_marks: Number(row.max_marks),
    percentage: Number(row.percentage),
    rank: Number(row.rank),
    exam_takers: Number(row.exam_takers),
    exam_average: round1(row.exam_average),
    exam_highest: round1(row.exam_highest),
  }));
}

/** Attendance per roster entry: { [class_student_id]: {present, late, absent, excused, total} } */
async function attendanceCounts(classIds) {
  if (!classIds.length) return {};
  const result = await pool.query(
    `SELECT ar.class_student_id, ar.status, COUNT(*)::int AS n
       FROM attendance_records ar
       JOIN attendance_sessions s ON s.id = ar.session_id
      WHERE s.class_id = ANY($1::uuid[])
      GROUP BY ar.class_student_id, ar.status`,
    [classIds],
  );
  const counts = {};
  for (const row of result.rows) {
    const c = counts[row.class_student_id]
      || (counts[row.class_student_id] = { present: 0, late: 0, absent: 0, excused: 0, total: 0 });
    c[row.status] += row.n;
    c.total += row.n;
  }
  return counts;
}

/** Present or late counts as attended; excused days are left out. */
function attendanceRate(c) {
  if (!c) return null;
  const counted = c.total - c.excused;
  return counted > 0 ? round1(((c.present + c.late) / counted) * 100) : null;
}

const GRADE_ORDER = ['A+', 'A', 'A-', 'B', 'C', 'D', 'F'];

function gradeDistribution(rows) {
  const counts = Object.fromEntries(GRADE_ORDER.map((g) => [g, 0]));
  for (const row of rows) if (row.grade in counts) counts[row.grade] += 1;
  return GRADE_ORDER.map((grade) => ({ grade, count: counts[grade] }));
}

/** Everything the teacher's class analytics screen shows. */
async function classAnalytics(classId) {
  const [rows, counts, roster, sessions, exams] = await Promise.all([
    latestResults([classId]),
    attendanceCounts([classId]),
    pool.query(
      `SELECT id, name, roll_number, user_id FROM class_students
        WHERE class_id = $1 AND status = 'active' ORDER BY roll_number`,
      [classId],
    ),
    pool.query(
      `SELECT s.session_date,
              COUNT(*) FILTER (WHERE ar.status IN ('present', 'late'))::int AS attended,
              COUNT(*) FILTER (WHERE ar.status <> 'excused')::int AS counted
         FROM attendance_sessions s
         LEFT JOIN attendance_records ar ON ar.session_id = s.id
        WHERE s.class_id = $1
        GROUP BY s.id ORDER BY s.session_date`,
      [classId],
    ),
    pool.query(
      `SELECT id, title, subject, total_questions, created_at, results_published_at
         FROM exams WHERE class_id = $1 ORDER BY created_at`,
      [classId],
    ),
  ]);

  const examSummaries = exams.rows.map((exam) => {
    const examRows = rows.filter((r) => r.exam_id === exam.id);
    const passed = examRows.filter((r) => r.passed).length;
    return {
      id: exam.id,
      title: exam.title,
      subject: exam.subject,
      date: exam.created_at,
      published: exam.results_published_at !== null,
      students: examRows.length,
      average: examRows.length ? round1(mean(examRows.map((r) => r.percentage))) : null,
      highest: examRows.length ? round1(Math.max(...examRows.map((r) => r.percentage))) : null,
      pass_rate: examRows.length ? round1((passed / examRows.length) * 100) : null,
    };
  });

  const students = roster.rows.map((s) => {
    const mine = rows
      .filter((r) => r.student_id === s.id)
      .sort((a, b) => new Date(a.exam_date) - new Date(b.exam_date));
    const avg = mean(mine.map((r) => r.percentage));
    return {
      id: s.id,
      name: s.name,
      roll_number: s.roll_number,
      has_account: s.user_id !== null,
      exams_taken: mine.length,
      average: avg === null ? null : round1(avg),
      latest: mine.length ? mine[mine.length - 1].percentage : null,
      trend: mine.map((r) => r.percentage),
      attendance_rate: attendanceRate(counts[s.id]),
    };
  });

  const ranked = students
    .filter((s) => s.average !== null)
    .sort((a, b) => b.average - a.average);
  const allAverages = ranked.map((s) => s.average);
  const attendanceRates = students.map((s) => s.attendance_rate).filter((r) => r !== null);
  const unmatched = rows.filter((r) => !r.student_id).length;

  return {
    summary: {
      students: roster.rows.length,
      exams: exams.rows.length,
      average: allAverages.length ? round1(mean(allAverages)) : null,
      attendance_rate: attendanceRates.length ? round1(mean(attendanceRates)) : null,
      sessions: sessions.rows.length,
      // Results whose roll number matches nobody on the roster.
      unmatched_results: unmatched,
    },
    exams: examSummaries,
    attendance: sessions.rows.map((s) => ({
      date: s.session_date,
      rate: s.counted > 0 ? round1((s.attended / s.counted) * 100) : null,
    })),
    grade_distribution: gradeDistribution(rows.filter((r) => r.student_id)),
    leaderboard: ranked.map((s, i) => ({ rank: i + 1, ...s })),
    // Students who need attention: average under 40% or attendance under 75%.
    at_risk: students.filter((s) => (s.average !== null && s.average < 40)
      || (s.attendance_rate !== null && s.attendance_rate < 75)),
    students,
  };
}

/** The signed-in student's active enrolments. */
async function enrolmentsForUser(userId) {
  const result = await pool.query(
    `SELECT cs.id AS student_id, cs.roll_number, cs.name AS student_name, cs.status,
            c.id AS class_id, c.name AS class_name, c.subject, c.section,
            t.name AS teacher_name
       FROM class_students cs
       JOIN classes c ON c.id = cs.class_id
       JOIN users t ON t.id = c.teacher_id
      WHERE cs.user_id = $1
      ORDER BY c.created_at`,
    [userId],
  );
  return result.rows;
}

/** A student's published results across their active classes, newest first. */
async function studentResults(userId) {
  const enrolments = (await enrolmentsForUser(userId)).filter((e) => e.status === 'active');
  const rows = await latestResults(enrolments.map((e) => e.class_id));
  const mineIds = new Set(enrolments.map((e) => e.student_id));
  const classNames = Object.fromEntries(enrolments.map((e) => [e.class_id, e.class_name]));
  return rows
    .filter((r) => mineIds.has(r.student_id) && r.results_published_at !== null)
    .sort((a, b) => new Date(b.exam_date) - new Date(a.exam_date))
    .map((r) => ({
      result_id: r.id,
      exam_id: r.exam_id,
      exam_title: r.exam_title,
      subject: r.exam_subject,
      class_id: r.class_id,
      class_name: classNames[r.class_id],
      date: r.exam_date,
      published_at: r.results_published_at,
      correct: r.correct,
      wrong: r.wrong,
      blank: r.blank,
      marks: r.marks,
      max_marks: r.max_marks,
      percentage: r.percentage,
      grade: r.grade,
      passed: r.passed,
      rank: r.rank,
      out_of: r.exam_takers,
      class_average: r.exam_average,
      class_highest: r.exam_highest,
    }));
}

/** The student dashboard: performance, trend, attendance, class rank. */
async function studentOverview(userId) {
  const enrolments = await enrolmentsForUser(userId);
  const active = enrolments.filter((e) => e.status === 'active');
  const classIds = active.map((e) => e.class_id);
  const [results, counts] = await Promise.all([
    studentResults(userId),
    attendanceCounts(classIds),
  ]);

  const chronological = [...results].reverse();
  const avg = mean(results.map((r) => r.percentage));

  // Attendance across all classes.
  const total = { present: 0, late: 0, absent: 0, excused: 0, total: 0 };
  for (const e of active) {
    const c = counts[e.student_id];
    if (!c) continue;
    for (const key of Object.keys(total)) total[key] += c[key];
  }

  // Rank in each class by average over published exams.
  const classRanks = [];
  for (const e of active) {
    const rows = (await latestResults([e.class_id])).filter((r) => r.results_published_at && r.student_id);
    const byStudent = {};
    for (const r of rows) (byStudent[r.student_id] ||= []).push(r.percentage);
    const averages = Object.entries(byStudent)
      .map(([id, values]) => ({ id, avg: mean(values) }))
      .sort((a, b) => b.avg - a.avg);
    const position = averages.findIndex((a) => a.id === e.student_id);
    classRanks.push({
      class_id: e.class_id,
      class_name: e.class_name,
      rank: position >= 0 ? position + 1 : null,
      out_of: averages.length,
      average: position >= 0 ? round1(averages[position].avg) : null,
      attendance_rate: attendanceRate(counts[e.student_id]),
    });
  }

  return {
    classes: enrolments,
    summary: {
      exams_taken: results.length,
      average: avg === null ? null : round1(avg),
      best: results.length ? Math.max(...results.map((r) => r.percentage)) : null,
      passed: results.filter((r) => r.passed).length,
      attendance_rate: attendanceRate(total),
      attendance: total,
    },
    trend: chronological.map((r) => ({
      exam_title: r.exam_title,
      date: r.date,
      percentage: r.percentage,
      class_average: r.class_average,
    })),
    grade_distribution: gradeDistribution(results),
    class_ranks: classRanks,
    recent_results: results.slice(0, 5),
  };
}

module.exports = {
  attendanceCounts,
  attendanceRate,
  classAnalytics,
  enrolmentsForUser,
  latestResults,
  studentOverview,
  studentResults,
};
