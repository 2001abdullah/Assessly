// Exam routes, mounted at /api/exam (JWT required).
//
//   POST   /             create an exam owned by the caller
//   GET    /             the caller's exams, newest first
//   GET    /:id          one exam
//   PUT    /:id          update title / subject / question and digit counts
//   DELETE /:id          delete (cascades to answer keys, rules, scans, results)
//   GET    /:id/summary  pass/fail counts and mark statistics
//   POST   /:id/publish    make results visible to the class's students (notifies them)
//   POST   /:id/unpublish  hide them again
//
// An exam may belong to one of the teacher's classes (class_id); its results
// are then matched to students by roll number, and stay private until
// published.
//
// roll_digits / registration_digits control how many ID bubble columns the
// generated answer sheet has, so changing them after printing sheets makes
// old sheets unreadable.

const express = require('express');
const crypto = require('crypto');
const pool = require('../config/db');
const { examParam, userOwnsClass } = require('../middleware/ownership');
const { classStudentUserIds, notify } = require('../services/notify');

const router = express.Router();

// Every route with :id first checks the signed-in user owns that exam.
router.param('id', examParam);

// class_id from the body: null/'' for no class; otherwise must be the caller's.
async function resolveClassId(req, res) {
  const raw = req.body?.class_id;
  if (raw === undefined || raw === null || raw === '') return { ok: true, classId: null };
  if (!(await userOwnsClass(raw, req.user.id))) {
    res.status(404).json({ message: 'class not found' });
    return { ok: false };
  }
  return { ok: true, classId: raw };
}

router.post('/:id/publish', async (req, res) => {
  const exam = (await pool.query(
    `UPDATE exams SET results_published_at = COALESCE(results_published_at, now())
      WHERE id = $1 RETURNING id, title, class_id, results_published_at`,
    [req.params.id],
  )).rows[0];
  if (exam.class_id) {
    notify(await classStudentUserIds(exam.class_id), {
      type: 'results_published',
      title: `Results are out: ${exam.title}`,
      body: 'Open Assessly to see your marks.',
      data: { exam_id: exam.id, class_id: exam.class_id },
    });
  }
  return res.json({ message: 'Results published', exam });
});

router.post('/:id/unpublish', async (req, res) => {
  const exam = (await pool.query(
    'UPDATE exams SET results_published_at = NULL WHERE id = $1 RETURNING id, results_published_at',
    [req.params.id],
  )).rows[0];
  return res.json({ message: 'Results hidden from students', exam });
});


// ========================================
// CREATE EXAM
// POST /api/exam
// ========================================

router.post('/', async (req, res) => {
  const {
    title,
    subject,
    total_questions,
    roll_digits = 7,
    registration_digits = 10,
  } = req.body;

  if (!title || !total_questions) {
    return res.status(400).json({
      message: 'title and total_questions are required',
    });
  }

  if (
    !Number.isInteger(Number(total_questions)) ||
    Number(total_questions) <= 0
  ) {
    return res.status(400).json({
      message: 'total_questions must be a positive integer',
    });
  }

  const rollDigits = Number(roll_digits);
  const registrationDigits = Number(registration_digits);
  if (
    !Number.isInteger(rollDigits) || rollDigits < 1 || rollDigits > 14 ||
    !Number.isInteger(registrationDigits) || registrationDigits < 0 ||
    registrationDigits > 16 || rollDigits + registrationDigits > 26
  ) {
    return res.status(400).json({
      message: 'Roll digits must be 1-14, registration digits 0-16, with at most 26 digits combined',
    });
  }

  const { ok, classId } = await resolveClassId(req, res);
  if (!ok) return undefined;

  const examId = crypto.randomUUID();

  try {
    const result = await pool.query(
      `
        INSERT INTO exams (
          id,
          title,
          subject,
          total_questions,
          user_id,
          roll_digits,
          registration_digits,
          class_id
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING *
      `,
      [
        examId,
        title,
        subject || null,
        Number(total_questions),
        req.user.id,
        rollDigits,
        registrationDigits,
        classId,
      ],
    );

    return res.status(201).json({
      message: 'Exam created successfully',
      exam: result.rows[0],
    });

  } catch (error) {
    console.error('Create exam error:', error);

    return res.status(500).json({
      message: 'Could not create exam',
    });
  }
});
// ========================================
// GET ALL EXAMS
// GET /api/exam
// ========================================

router.get('/', async (req, res) => {
  try {
    const result = await pool.query(
      `
        SELECT
          e.id,
          e.title,
          e.subject,
          e.total_questions,
          e.roll_digits,
          e.registration_digits,
          e.created_at,
          e.class_id,
          e.results_published_at,
          c.name AS class_name
        FROM exams e
        LEFT JOIN classes c ON c.id = e.class_id
        WHERE e.user_id = $1
        ORDER BY e.created_at DESC
      `,
      [req.user.id],
    );

    return res.status(200).json({
      exams: result.rows,
    });

  } catch (error) {
    console.error('Get all exams error:', error);

    return res.status(500).json({
      message: 'Could not fetch exams',
    });
  }
});

// ========================================
// GET EXAM
// GET /api/exam/:id
// ========================================

router.get('/:id', async (req, res) => {
  const { id } = req.params;

  try {
    const result = await pool.query(
      `
        SELECT *
        FROM exams
        WHERE id = $1
      `,
      [id],
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        message: 'Exam not found',
      });
    }

    return res.status(200).json({
      exam: result.rows[0],
    });

  } catch (error) {
    console.error('Get exam error:', error);

    return res.status(500).json({
      message: 'Could not fetch exam',
    });
  }
});


// ========================================
// UPDATE EXAM
// PUT /api/exam/:id
// ========================================

router.put('/:id', async (req, res) => {
  const { id } = req.params;

  const {
    title,
    subject,
    total_questions,
    roll_digits = 7,
    registration_digits = 10,
  } = req.body;

  if (!title || !total_questions) {
    return res.status(400).json({
      message: 'title and total_questions are required',
    });
  }

  if (
    !Number.isInteger(Number(total_questions)) ||
    Number(total_questions) <= 0
  ) {
    return res.status(400).json({
      message: 'total_questions must be a positive integer',
    });
  }


  const rollDigits = Number(roll_digits);
  const registrationDigits = Number(registration_digits);
  if (
    !Number.isInteger(rollDigits) || rollDigits < 1 || rollDigits > 14 ||
    !Number.isInteger(registrationDigits) || registrationDigits < 0 ||
    registrationDigits > 16 || rollDigits + registrationDigits > 26
  ) {
    return res.status(400).json({ message: 'Invalid roll or registration digit count' });
  }

  // class_id is only changed when the request includes it.
  const changeClass = Object.prototype.hasOwnProperty.call(req.body, 'class_id');
  const { ok, classId } = changeClass ? await resolveClassId(req, res) : { ok: true, classId: null };
  if (!ok) return undefined;

  try {
    const result = await pool.query(
      `
        UPDATE exams
        SET
          title = $1,
          subject = $2,
          total_questions = $3
          , roll_digits = $4
          , registration_digits = $5
          , class_id = CASE WHEN $7 THEN $8::uuid ELSE class_id END
        WHERE id = $6
        RETURNING *
      `,
      [
        title,
        subject || null,
        Number(total_questions),
        rollDigits,
        registrationDigits,
        id,
        changeClass,
        classId,
      ],
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        message: 'Exam not found',
      });
    }

    return res.status(200).json({
      message: 'Exam updated successfully',
      exam: result.rows[0],
    });

  } catch (error) {
    console.error('Update exam error:', error);

    return res.status(500).json({
      message: 'Could not update exam',
    });
  }
});


// ========================================
// DELETE EXAM
// DELETE /api/exam/:id
// ========================================

router.delete('/:id', async (req, res) => {
  const { id } = req.params;

  try {
    const result = await pool.query(
      `
        DELETE FROM exams
        WHERE id = $1
        RETURNING id
      `,
      [id],
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        message: 'Exam not found',
      });
    }

    return res.status(200).json({
      message: 'Exam deleted successfully',
    });

  } catch (error) {
    console.error('Delete exam error:', error);

    return res.status(500).json({
      message: 'Could not delete exam',
    });
  }
});
router.get('/:id/summary', async (req, res) => {
  const { id } = req.params;

  try {

    const examQuery = await pool.query(
      `
        SELECT
          id,
          title,
          subject,
          total_questions
        FROM exams
        WHERE id = $1
      `,
      [id]
    );

    if (examQuery.rows.length === 0) {
      return res.status(404).json({
        message: 'Exam not found',
      });
    }

    const exam = examQuery.rows[0];

    const statsQuery = await pool.query(
      `
        SELECT
          COUNT(*) AS students,
          COUNT(*) FILTER (WHERE passed = true) AS passed,
          COUNT(*) FILTER (WHERE passed = false) AS failed,
          COALESCE(MAX(marks), 0) AS highest_marks,
          COALESCE(MIN(marks), 0) AS lowest_marks,
          COALESCE(AVG(marks), 0) AS average_marks,
          COALESCE(AVG(percentage), 0) AS average_percentage
        FROM exam_results
        WHERE exam_id = $1
      `,
      [id]
    );

    const stats = statsQuery.rows[0];

    const students = Number(stats.students);

    return res.status(200).json({
      exam: {
        id: exam.id,
        title: exam.title,
        subject: exam.subject,
        total_questions: Number(exam.total_questions),
      },

      summary: {
        students,
        passed: Number(stats.passed),
        failed: Number(stats.failed),

        highest_marks: Number(stats.highest_marks),
        lowest_marks: Number(stats.lowest_marks),

        average_marks: Number(stats.average_marks),
        average_percentage: Number(stats.average_percentage),

        pass_rate:
          students > 0
            ? Number(
                (
                  (Number(stats.passed) / students) * 100
                ).toFixed(2)
              )
            : 0,
      },
    });

  } catch (error) {

    console.error(
      'Get exam summary error:',
      error.message
    );

    return res.status(500).json({
      message: 'Could not fetch exam summary',
    });
  }
});

module.exports = router;
