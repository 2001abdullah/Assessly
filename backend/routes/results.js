// Result routes, mounted at /api/results (JWT + teacher role). Read-only:
// results are created by POST /api/scoring/score (or /api/omr/batch).
//
//   GET /:id                       one saved result (summary counts)
//   GET /:id/details               + exam, rules and a per-question breakdown
//   GET /exam/:exam_id             every result for an exam, best first, with
//                                  the matching student's name when the exam
//                                  belongs to a class
//   GET /exam/:exam_id/export.csv  the same as a CSV download
//
// resultDetails() is also used by the student routes.

const express = require('express');
const pool = require('../config/db');
const { AMBIGUOUS_STATUSES } = require('../services/scoring');
const { examParam, resultParam } = require('../middleware/ownership');

const router = express.Router();

// :id is a result id; :exam_id is an exam id. Both must belong to the caller.
router.param('id', resultParam);
router.param('exam_id', examParam);

const RESULT_COLUMNS = `
  id, exam_id, scan_id, roll_number, registration_number, correct, wrong,
  blank, ambiguous, marks, max_marks, percentage, grade, passed, needs_review,
  created_at`;

// Marks for one question under the exam's rules. For display only: saved
// totals are the ones computed when the sheet was scored, and ambiguous marks
// treated as 'review' score 0 here.
function questionOutcome(row, rules) {
  const correctAnswer = row.correct_answer ? String(row.correct_answer).trim().toUpperCase() : null;
  const givenAnswer = row.given_answer ? String(row.given_answer).trim().toUpperCase() : null;

  let status;
  let marks = 0;
  if (!correctAnswer) {
    status = 'not_keyed';
  } else if (AMBIGUOUS_STATUSES.has(row.status)) {
    status = 'ambiguous';
    if (rules.ambiguous_as === 'wrong') marks = Number(rules.marks_wrong);
    else if (rules.ambiguous_as === 'blank') marks = Number(rules.marks_blank);
  } else if (!givenAnswer) {
    status = 'blank';
    marks = Number(rules.marks_blank);
  } else if (givenAnswer === correctAnswer) {
    status = 'correct';
    marks = Number(rules.marks_correct);
  } else {
    status = 'wrong';
    marks = Number(rules.marks_wrong);
  }

  return {
    question_number: Number(row.question_number),
    given_answer: givenAnswer,
    correct_answer: correctAnswer,
    status,
    marks,
    confidence: row.confidence !== null ? Number(row.confidence) : null,
    scores: row.scores || [],
  };
}

/** A saved result with exam, rules and every question, or null. */
async function resultDetails(resultId) {
  const result = (await pool.query(
    `SELECT ${RESULT_COLUMNS} FROM exam_results WHERE id = $1`,
    [resultId],
  )).rows[0];
  if (!result) return null;

  const [examQuery, questionsQuery, rulesQuery] = await Promise.all([
    pool.query('SELECT id, title, subject, total_questions FROM exams WHERE id = $1', [result.exam_id]),
    pool.query(
      `SELECT ak.question_number, ak.correct_answer,
              oa.value AS given_answer, oa.status, oa.confidence, oa.scores
         FROM answer_keys ak
         LEFT JOIN omr_answers oa
           ON oa.question_number = ak.question_number AND oa.scan_id = $1
        WHERE ak.exam_id = $2
        ORDER BY ak.question_number ASC`,
      [result.scan_id, result.exam_id],
    ),
    pool.query(
      `SELECT marks_correct, marks_wrong, marks_blank, pass_percentage,
              ambiguous_as, clamp_negative_total
         FROM exam_scoring_rules WHERE exam_id = $1`,
      [result.exam_id],
    ),
  ]);
  const exam = examQuery.rows[0];
  const rules = rulesQuery.rows[0];
  if (!exam || !rules) return null;

  return {
    id: result.id,
    exam: {
      id: exam.id,
      title: exam.title,
      subject: exam.subject,
      total_questions: Number(exam.total_questions),
    },
    scan_id: result.scan_id,
    student: {
      roll_number: result.roll_number,
      registration_number: result.registration_number,
    },
    summary: {
      correct: result.correct,
      wrong: result.wrong,
      blank: result.blank,
      ambiguous: result.ambiguous,
      marks: Number(result.marks),
      max_marks: Number(result.max_marks),
      percentage: Number(result.percentage),
      grade: result.grade,
      passed: result.passed,
      needs_review: result.needs_review,
    },
    scoring_rules: {
      marks_correct: Number(rules.marks_correct),
      marks_wrong: Number(rules.marks_wrong),
      marks_blank: Number(rules.marks_blank),
      pass_percentage: Number(rules.pass_percentage),
      ambiguous_as: rules.ambiguous_as,
      clamp_negative_total: rules.clamp_negative_total,
    },
    questions: questionsQuery.rows.map((row) => questionOutcome(row, rules)),
    created_at: result.created_at,
  };
}

router.get('/:id', async (req, res) => {
  const result = await pool.query(`SELECT ${RESULT_COLUMNS} FROM exam_results WHERE id = $1`, [req.params.id]);
  if (result.rows.length === 0) return res.status(404).json({ message: 'Result not found' });
  return res.status(200).json({ result: result.rows[0] });
});

router.get('/:id/details', async (req, res) => {
  const details = await resultDetails(req.params.id);
  if (!details) return res.status(404).json({ message: 'Result not found' });
  return res.status(200).json({ result: details });
});

router.get('/exam/:exam_id', async (req, res) => {
  const { exam_id: examId } = req.params;
  const exam = (await pool.query(
    'SELECT id, title, subject, total_questions, class_id, results_published_at FROM exams WHERE id = $1',
    [examId],
  )).rows[0];
  if (!exam) return res.status(404).json({ message: 'Exam not found' });

  // The student is the class roster entry with the same roll number.
  const resultsQuery = await pool.query(
    `SELECT r.id, r.scan_id, r.roll_number, r.registration_number, r.correct,
            r.wrong, r.blank, r.ambiguous, r.marks, r.max_marks, r.percentage,
            r.grade, r.passed, r.needs_review, r.created_at, cs.name AS student_name
       FROM exam_results r
       LEFT JOIN class_students cs
         ON cs.class_id = $2 AND cs.status = 'active'
        AND ltrim(cs.roll_number, '0') = ltrim(r.roll_number, '0')
      WHERE r.exam_id = $1
      ORDER BY r.percentage DESC, r.created_at ASC`,
    [examId, exam.class_id],
  );

  return res.status(200).json({
    exam: {
      id: exam.id,
      title: exam.title,
      subject: exam.subject,
      total_questions: Number(exam.total_questions),
      class_id: exam.class_id,
      results_published_at: exam.results_published_at,
    },
    count: resultsQuery.rows.length,
    results: resultsQuery.rows.map((row) => ({
      result_id: row.id,
      scan_id: row.scan_id,
      roll_number: row.roll_number,
      registration_number: row.registration_number,
      student_name: row.student_name,
      correct: row.correct,
      wrong: row.wrong,
      blank: row.blank,
      ambiguous: row.ambiguous,
      marks: Number(row.marks),
      max_marks: Number(row.max_marks),
      percentage: Number(row.percentage),
      grade: row.grade,
      passed: row.passed,
      needs_review: row.needs_review,
      created_at: row.created_at,
    })),
  });
});

router.get('/exam/:exam_id/export.csv', async (req, res) => {
  const { exam_id: examId } = req.params;
  const exam = (await pool.query('SELECT class_id FROM exams WHERE id = $1', [examId])).rows[0];
  const result = await pool.query(
    `SELECT r.roll_number, cs.name AS student_name, r.registration_number, r.correct,
            r.wrong, r.blank, r.ambiguous, r.marks, r.max_marks, r.percentage,
            r.grade, r.passed, r.needs_review, r.created_at
       FROM exam_results r
       LEFT JOIN class_students cs
         ON cs.class_id = $2 AND cs.status = 'active'
        AND ltrim(cs.roll_number, '0') = ltrim(r.roll_number, '0')
      WHERE r.exam_id = $1
      ORDER BY r.created_at ASC`,
    [examId, exam?.class_id || null],
  );

  const escape = (value) => {
    const text = value === null || value === undefined ? '' : String(value);
    return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
  };
  const headers = [
    'roll_number', 'student_name', 'registration_number', 'correct', 'wrong', 'blank',
    'ambiguous', 'marks', 'max_marks', 'percentage', 'grade', 'passed',
    'needs_review', 'created_at',
  ];
  const rows = result.rows.map((row) => headers.map((header) => escape(row[header])).join(','));

  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="exam-${examId}-results.csv"`);
  return res.send([headers.join(','), ...rows].join('\r\n'));
});

module.exports = router;
module.exports.resultDetails = resultDetails;
