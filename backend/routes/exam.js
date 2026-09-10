const express = require('express');
const crypto = require('crypto');
const pool = require('../config/db');

const router = express.Router();


// ========================================
// CREATE EXAM
// POST /api/exam
// ========================================

router.post('/', async (req, res) => {
  const {
    title,
    subject,
    total_questions,
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

  const examId = crypto.randomUUID();

  try {
    const result = await pool.query(
      `
        INSERT INTO exams (
          id,
          title,
          subject,
          total_questions
        )
        VALUES ($1, $2, $3, $4)
        RETURNING *
      `,
      [
        examId,
        title,
        subject || null,
        Number(total_questions),
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
          id,
          title,
          subject,
          total_questions,
          created_at
        FROM exams
        ORDER BY created_at DESC
      `
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

  try {
    const result = await pool.query(
      `
        UPDATE exams
        SET
          title = $1,
          subject = $2,
          total_questions = $3
        WHERE id = $4
        RETURNING *
      `,
      [
        title,
        subject || null,
        Number(total_questions),
        id,
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