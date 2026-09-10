const express = require('express');
const pool = require('../config/db');

const router = express.Router();


// ========================================
// CREATE / UPDATE SCORING RULES
// PUT /api/scoring-rules/:exam_id
// ========================================

router.put('/:exam_id', async (req, res) => {
  const { exam_id } = req.params;

  const {
    marks_correct = 1,
    marks_wrong = -0.5,
    marks_blank = 0,
    pass_percentage = 40,
    ambiguous_as = 'review',
    clamp_negative_total = true,
  } = req.body;

  // --------------------------------------------------
  // Validate numeric values
  // --------------------------------------------------

  const correct = Number(marks_correct);
  const wrong = Number(marks_wrong);
  const blank = Number(marks_blank);
  const pass = Number(pass_percentage);

  if (
    !Number.isFinite(correct) ||
    !Number.isFinite(wrong) ||
    !Number.isFinite(blank) ||
    !Number.isFinite(pass)
  ) {
    return res.status(400).json({
      message: 'Scoring values must be valid numbers',
    });
  }

  if (correct < 0) {
    return res.status(400).json({
      message: 'marks_correct must be greater than or equal to 0',
    });
  }

  if (wrong > 0) {
    return res.status(400).json({
      message: 'marks_wrong must be less than or equal to 0',
    });
  }

  if (blank !== 0) {
    return res.status(400).json({
      message: 'marks_blank must be 0',
    });
  }

  if (pass < 0 || pass > 100) {
    return res.status(400).json({
      message: 'pass_percentage must be between 0 and 100',
    });
  }

  if (
    !['review', 'wrong', 'blank'].includes(
      ambiguous_as
    )
  ) {
    return res.status(400).json({
      message:
        "ambiguous_as must be 'review', 'wrong' or 'blank'",
    });
  }

  // --------------------------------------------------
  // Check exam exists
  // --------------------------------------------------

  try {

    const examResult = await pool.query(
      `
        SELECT id
        FROM exams
        WHERE id = $1
      `,
      [exam_id]
    );

    if (examResult.rows.length === 0) {
      return res.status(404).json({
        message: 'Exam not found',
      });
    }


    // --------------------------------------------------
    // Insert or update rules
    // --------------------------------------------------

    const result = await pool.query(
      `
        INSERT INTO exam_scoring_rules (
          exam_id,
          marks_correct,
          marks_wrong,
          marks_blank,
          pass_percentage,
          ambiguous_as,
          clamp_negative_total,
          updated_at
        )
        VALUES (
          $1,
          $2,
          $3,
          $4,
          $5,
          $6,
          $7,
          NOW()
        )

        ON CONFLICT (exam_id)
        DO UPDATE SET
          marks_correct = EXCLUDED.marks_correct,
          marks_wrong = EXCLUDED.marks_wrong,
          marks_blank = EXCLUDED.marks_blank,
          pass_percentage = EXCLUDED.pass_percentage,
          ambiguous_as = EXCLUDED.ambiguous_as,
          clamp_negative_total =
            EXCLUDED.clamp_negative_total,
          updated_at = NOW()

        RETURNING *
      `,
      [
        exam_id,
        correct,
        wrong,
        blank,
        pass,
        ambiguous_as,
        Boolean(clamp_negative_total),
      ]
    );


    return res.status(200).json({
      message:
        'Scoring rules saved successfully',

      scoring_rules:
        result.rows[0],
    });

  } catch (error) {

    console.error(
      'Save scoring rules error:',
      error.message
    );

    return res.status(500).json({
      message:
        'Could not save scoring rules',
    });
  }
});


// ========================================
// GET SCORING RULES
// GET /api/scoring-rules/:exam_id
// ========================================

router.get('/:exam_id', async (req, res) => {
  const { exam_id } = req.params;

  try {

    const result = await pool.query(
      `
        SELECT
          exam_id,
          marks_correct,
          marks_wrong,
          marks_blank,
          pass_percentage,
          ambiguous_as,
          clamp_negative_total,
          created_at,
          updated_at
        FROM exam_scoring_rules
        WHERE exam_id = $1
      `,
      [exam_id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        message:
          'Scoring rules not found for this exam',
      });
    }

    return res.status(200).json({
      scoring_rules:
        result.rows[0],
    });

  } catch (error) {

    console.error(
      'Get scoring rules error:',
      error.message
    );

    return res.status(500).json({
      message:
        'Could not fetch scoring rules',
    });
  }
});


module.exports = router;