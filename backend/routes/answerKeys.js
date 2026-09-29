// Answer-key routes, mounted at /api/answer-key (JWT required).
//
//   POST /                 add one answer { exam_id, question_number, correct_answer }
//   POST /batch            replace the whole key { exam_id, answers: [...] }  (used by the app)
//   GET  /exam/:exam_id    the exam's answers, by question number
//
// Answers are stored upper-cased. The per-question marks / negative_marks
// columns are legacy: scoring uses the exam-wide rules in exam_scoring_rules.

const express = require('express');
const crypto = require('crypto');
const pool = require('../config/db');
const { examParam, requireExamInBody } = require('../middleware/ownership');

const router = express.Router();

router.param('exam_id', examParam);


// ========================================
// CREATE SINGLE ANSWER KEY
// POST /api/answer-key
// ========================================

const createAnswerKey = async (req, res) => {
  const {
    exam_id,
    question_number,
    correct_answer,
    marks,
    negative_marks,
  } = req.body;

  // -----------------------------
  // Validate required fields
  // -----------------------------

  if (!exam_id || !question_number || typeof correct_answer !== 'string' || !correct_answer.trim()) {
    return res.status(400).json({
      message: 'exam_id, question_number and correct_answer are required',
    });
  }

  // -----------------------------
  // Validate question number
  // -----------------------------

  if (
    !Number.isInteger(Number(question_number)) ||
    Number(question_number) <= 0
  ) {
    return res.status(400).json({
      message: 'question_number must be a positive integer',
    });
  }

  try {
    // -----------------------------
    // Check exam exists
    // -----------------------------

    const examResult = await pool.query(
      `
        SELECT id, total_questions
        FROM exams
        WHERE id = $1
      `,
      [exam_id],
    );

    if (examResult.rows.length === 0) {
      return res.status(404).json({
        message: 'Exam not found',
      });
    }

    // -----------------------------
    // Check question number
    // -----------------------------

    if (
      Number(question_number) >
      Number(examResult.rows[0].total_questions)
    ) {
      return res.status(400).json({
        message: 'question_number exceeds total questions in the exam',
      });
    }

    // -----------------------------
    // Create answer key
    // -----------------------------

    const id = crypto.randomUUID();

    const result = await pool.query(
      `
        INSERT INTO answer_keys (
          id,
          exam_id,
          question_number,
          correct_answer,
          marks,
          negative_marks
        )
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING *
      `,
      [
        id,
        exam_id,
        Number(question_number),
        correct_answer.trim().toUpperCase(),
        marks !== undefined ? Number(marks) : 1,
        negative_marks !== undefined ? Number(negative_marks) : 0,
      ],
    );

    return res.status(201).json({
      message: 'Answer key created successfully',
      answer_key: result.rows[0],
    });

  } catch (error) {
    if (error.code === '23505') {
      return res.status(409).json({
        message: 'This question already has an answer; use /batch to change it',
      });
    }
    console.error('Create answer key error:', error);

    return res.status(500).json({
      message: 'Could not create answer key',
    });
  }
};

router.post('/', requireExamInBody, createAnswerKey);


// ========================================
// CREATE / UPDATE FULL ANSWER KEY
// POST /api/answer-key/batch
// ========================================

router.post('/batch', requireExamInBody, async (req, res) => {
  const { exam_id, answers } = req.body;

  // -----------------------------
  // Validate request
  // -----------------------------

  if (
    !exam_id ||
    !Array.isArray(answers)
  ) {
    return res.status(400).json({
      message: 'exam_id and an answers array are required',
    });
  }

  const client = await pool.connect();

  try {
    // -----------------------------
    // Check exam exists
    // -----------------------------

    const examResult = await client.query(
      `
        SELECT id, total_questions
        FROM exams
        WHERE id = $1
      `,
      [exam_id],
    );

    if (examResult.rows.length === 0) {
      return res.status(404).json({
        message: 'Exam not found',
      });
    }

    const totalQuestions = Number(
      examResult.rows[0].total_questions,
    );

    // -----------------------------
    // Validate all answers
    // -----------------------------

    for (const answer of answers) {
      const questionNumber = Number(answer.question_number);
      const correctAnswer = answer.correct_answer;

      if (
        !Number.isInteger(questionNumber) ||
        questionNumber <= 0 ||
        questionNumber > totalQuestions
      ) {
        return res.status(400).json({
          message: `Invalid question number: ${answer.question_number}`,
        });
      }

      if (
        typeof correctAnswer !== 'string' ||
        correctAnswer.trim() === ''
      ) {
        return res.status(400).json({
          message: `Missing answer for question ${questionNumber}`,
        });
      }
    }

    // -----------------------------
    // Start transaction
    // -----------------------------

    await client.query('BEGIN');

    // The submitted list is the complete answer key. Removing existing rows
    // first means a question can be intentionally returned to a blank state.
    await client.query(
      'DELETE FROM answer_keys WHERE exam_id = $1',
      [exam_id],
    );

    // -----------------------------
    // Insert / update answers
    // -----------------------------

    for (const answer of answers) {
      await client.query(
        `
          INSERT INTO answer_keys (
            id,
            exam_id,
            question_number,
            correct_answer,
            marks,
            negative_marks
          )
          VALUES (
            $1,
            $2,
            $3,
            $4,
            1,
            0
          )
          ON CONFLICT (exam_id, question_number)
          DO UPDATE SET
            correct_answer = EXCLUDED.correct_answer
        `,
        [
          crypto.randomUUID(),
          exam_id,
          Number(answer.question_number),
          answer.correct_answer.trim().toUpperCase(),
        ],
      );
    }

    // -----------------------------
    // Commit transaction
    // -----------------------------

    await client.query('COMMIT');

    return res.status(200).json({
      message: 'Answer key saved successfully',
      exam_id,
      count: answers.length,
    });

  } catch (error) {
    // -----------------------------
    // Rollback if anything fails
    // -----------------------------

    await client.query('ROLLBACK');

    console.error('Batch answer key error:', error);

    return res.status(500).json({
      message: 'Could not save answer key',
    });

  } finally {
    client.release();
  }
});


// ========================================
// GET ALL ANSWER KEYS FOR AN EXAM
// GET /api/answer-key/exam/:exam_id
// ========================================

router.get('/exam/:exam_id', async (req, res) => {
  const { exam_id } = req.params;

  try {
    const result = await pool.query(
      `
        SELECT *
        FROM answer_keys
        WHERE exam_id = $1
        ORDER BY question_number ASC
      `,
      [exam_id],
    );

    return res.status(200).json({
      exam_id,
      count: result.rows.length,
      answer_keys: result.rows,
    });

  } catch (error) {
    console.error('Get answer keys error:', error);

    return res.status(500).json({
      message: 'Could not fetch answer keys',
    });
  }
});


module.exports = router;
