const express = require('express');
const pool = require('../config/db');

const router = express.Router();
const { examParam, resultParam } = require('../middleware/ownership');

// :id is a result id; :exam_id is an exam id. Both must belong to the caller.
router.param('id', resultParam);
router.param('exam_id', examParam);


// ========================================
// GET RESULT
// GET /api/results/:id
// ========================================

router.get('/:id', async (req, res) => {
  const { id } = req.params;

  try {
    const result = await pool.query(
      `
        SELECT
          id,
          exam_id,
          scan_id,
          roll_number,
          registration_number,
          correct,
          wrong,
          blank,
          ambiguous,
          marks,
          max_marks,
          percentage,
          grade,
          passed,
          needs_review,
          created_at
        FROM exam_results
        WHERE id = $1
      `,
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        message: 'Result not found',
      });
    }

    return res.status(200).json({
      result: result.rows[0],
    });

  } catch (error) {
    console.error(
      'Get result error:',
      error.message
    );

    return res.status(500).json({
      message: 'Could not fetch result',
    });
  }
});


// ========================================
// GET DETAILED RESULT
// GET /api/results/:id/details
// ========================================

router.get('/:id/details', async (req, res) => {
  const { id } = req.params;

  try {

    // --------------------------------------------------
    // 1. Get saved result
    // --------------------------------------------------

    const resultQuery = await pool.query(
      `
        SELECT
          id,
          exam_id,
          scan_id,
          roll_number,
          registration_number,
          correct,
          wrong,
          blank,
          ambiguous,
          marks,
          max_marks,
          percentage,
          grade,
          passed,
          needs_review,
          created_at
        FROM exam_results
        WHERE id = $1
      `,
      [id]
    );

    if (resultQuery.rows.length === 0) {
      return res.status(404).json({
        message: 'Result not found',
      });
    }

    const result = resultQuery.rows[0];


    // --------------------------------------------------
    // 2. Get exam information
    // --------------------------------------------------

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
      [result.exam_id]
    );

    if (examQuery.rows.length === 0) {
      return res.status(404).json({
        message: 'Exam not found',
      });
    }

    const exam = examQuery.rows[0];


    // --------------------------------------------------
    // 3. Get answer key + student's answers
    // --------------------------------------------------

    const questionsQuery = await pool.query(
      `
        SELECT
          ak.question_number,
          ak.correct_answer,
          oa.value AS given_answer,
          oa.status,
          oa.confidence,
          oa.scores
        FROM answer_keys ak

        LEFT JOIN omr_answers oa
          ON oa.question_number = ak.question_number
          AND oa.scan_id = $1

        WHERE ak.exam_id = $2

        ORDER BY ak.question_number ASC
      `,
      [
        result.scan_id,
        result.exam_id,
      ]
    );


    // --------------------------------------------------
    // 4. Get exam scoring rules
    // --------------------------------------------------

    const rulesQuery = await pool.query(
      `
        SELECT
          marks_correct,
          marks_wrong,
          marks_blank,
          pass_percentage,
          ambiguous_as,
          clamp_negative_total
        FROM exam_scoring_rules
        WHERE exam_id = $1
      `,
      [result.exam_id]
    );

    if (rulesQuery.rows.length === 0) {
      return res.status(404).json({
        message: 'Scoring rules not found',
      });
    }

    const rules = rulesQuery.rows[0];


    // --------------------------------------------------
    // 5. Build question-by-question result
    // --------------------------------------------------

    const questions =
      questionsQuery.rows.map((row) => {

        const correctAnswer =
          row.correct_answer
            ? String(row.correct_answer)
                .trim()
                .toUpperCase()
            : null;

        const givenAnswer =
          row.given_answer
            ? String(row.given_answer)
                .trim()
                .toUpperCase()
            : null;

        let status = 'not_keyed';
        let marks = 0;

        if (!correctAnswer) {

          status = 'not_keyed';

        } else if (
          row.status === 'multi' ||
          row.status === 'faint' ||
          row.status === 'unreadable'
        ) {

          status = 'ambiguous';

          if (
            rules.ambiguous_as === 'wrong'
          ) {
            marks =
              Number(rules.marks_wrong);
          } else if (
            rules.ambiguous_as === 'blank'
          ) {
            marks =
              Number(rules.marks_blank);
          }

        } else if (!givenAnswer) {

          status = 'blank';

          marks =
            Number(rules.marks_blank);

        } else if (
          givenAnswer === correctAnswer
        ) {

          status = 'correct';

          marks =
            Number(rules.marks_correct);

        } else {

          status = 'wrong';

          marks =
            Number(rules.marks_wrong);
        }

        return {
          question_number:
            Number(row.question_number),

          given_answer:
            givenAnswer,

          correct_answer:
            correctAnswer,

          status,

          marks,

          confidence:
            row.confidence !== null
              ? Number(row.confidence)
              : null,

          scores:
            row.scores || [],
        };
      });


    // --------------------------------------------------
    // 6. Return complete result
    // --------------------------------------------------

    return res.status(200).json({
      result: {
        id: result.id,

        exam: {
          id: exam.id,
          title: exam.title,
          subject: exam.subject,
          total_questions:
            Number(exam.total_questions),
        },

        scan_id:
          result.scan_id,

        student: {
          roll_number:
            result.roll_number,

          registration_number:
            result.registration_number,
        },

        summary: {
          correct:
            result.correct,

          wrong:
            result.wrong,

          blank:
            result.blank,

          ambiguous:
            result.ambiguous,

          marks:
            Number(result.marks),

          max_marks:
            Number(result.max_marks),

          percentage:
            Number(result.percentage),

          grade:
            result.grade,

          passed:
            result.passed,

          needs_review:
            result.needs_review,
        },

        scoring_rules: {
          marks_correct:
            Number(rules.marks_correct),

          marks_wrong:
            Number(rules.marks_wrong),

          marks_blank:
            Number(rules.marks_blank),

          pass_percentage:
            Number(rules.pass_percentage),

          ambiguous_as:
            rules.ambiguous_as,

          clamp_negative_total:
            rules.clamp_negative_total,
        },

        questions,

        created_at:
          result.created_at,
      },
    });

  } catch (error) {

    console.error(
      'Get detailed result error:',
      error.message
    );

    return res.status(500).json({
      message:
        'Could not fetch detailed result',
    });
  }
});
// ========================================
// GET ALL RESULTS FOR AN EXAM
// GET /api/results/exam/:exam_id
// ========================================

router.get('/exam/:exam_id', async (req, res) => {
  const { exam_id } = req.params;

  try {

    // --------------------------------------------------
    // 1. Check exam exists
    // --------------------------------------------------

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
      [exam_id]
    );

    if (examQuery.rows.length === 0) {
      return res.status(404).json({
        message: 'Exam not found',
      });
    }

    const exam = examQuery.rows[0];


    // --------------------------------------------------
    // 2. Get all results for this exam
    // --------------------------------------------------

    const resultsQuery = await pool.query(
      `
        SELECT
          id,
          scan_id,
          roll_number,
          registration_number,
          correct,
          wrong,
          blank,
          ambiguous,
          marks,
          max_marks,
          percentage,
          grade,
          passed,
          needs_review,
          created_at
        FROM exam_results
        WHERE exam_id = $1
        ORDER BY percentage DESC, created_at ASC
      `,
      [exam_id]
    );


    // --------------------------------------------------
    // 3. Return results
    // --------------------------------------------------

    return res.status(200).json({
      exam: {
        id: exam.id,
        title: exam.title,
        subject: exam.subject,
        total_questions:
          Number(exam.total_questions),
      },

      count:
        resultsQuery.rows.length,

      results:
        resultsQuery.rows.map((row) => ({
          result_id:
            row.id,

          scan_id:
            row.scan_id,

          roll_number:
            row.roll_number,

          registration_number:
            row.registration_number,

          correct:
            row.correct,

          wrong:
            row.wrong,

          blank:
            row.blank,

          ambiguous:
            row.ambiguous,

          marks:
            Number(row.marks),

          max_marks:
            Number(row.max_marks),

          percentage:
            Number(row.percentage),

          grade:
            row.grade,

          passed:
            row.passed,

          needs_review:
            row.needs_review,

          created_at:
            row.created_at,
        })),
    });

  } catch (error) {

    console.error(
      'Get exam results error:',
      error.message
    );

    return res.status(500).json({
      message:
        'Could not fetch exam results',
    });
  }
});


module.exports = router;