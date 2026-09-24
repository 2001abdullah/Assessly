const express = require('express');
const crypto = require('crypto');
const { scoreScan } = require('../services/scoring');
const pool = require('../config/db');

const { requireExamAndScanInBody } = require('../middleware/ownership');

const router = express.Router();

router.post('/score', requireExamAndScanInBody, async (req, res) => {
  const {
    exam_id,
    scan_id,
    name = '',
  } = req.body;

  // ------------------------------------------------------------
  // Validate request
  // ------------------------------------------------------------

  if (!exam_id || !scan_id) {
    return res.status(400).json({
      message: 'exam_id and scan_id are required',
    });
  }

  try {

    // ----------------------------------------------------------
    // 1. Check if this scan was already scored
    // ----------------------------------------------------------

    const existingResult = await pool.query(
      `
        SELECT *
        FROM exam_results
        WHERE scan_id = $1
      `,
      [scan_id]
    );

    if (existingResult.rows.length > 0) {
      const existing = existingResult.rows[0];

      // Make sure the existing result belongs
      // to the requested exam
      if (
        String(existing.exam_id) !==
        String(exam_id)
      ) {
        return res.status(400).json({
          message:
            'This OMR scan already belongs to a different exam result',
        });
      }

      return res.status(200).json({
        message:
          'This OMR scan has already been scored',

        result_id:
          existing.id,

        exam_id:
          existing.exam_id,

        scan_id:
          existing.scan_id,

        result: {
          roll:
            existing.roll_number,

          registration:
            existing.registration_number,

          name,

          correct:
            existing.correct,

          wrong:
            existing.wrong,

          blank:
            existing.blank,

          ambiguous:
            existing.ambiguous,

          marks:
            Number(existing.marks),

          max_marks:
            Number(existing.max_marks),

          percentage:
            Number(existing.percentage),

          grade:
            existing.grade,

          passed:
            existing.passed,

          outcomes: [],
        },
      });
    }


    // ----------------------------------------------------------
    // 2. Score the OMR scan
    // ----------------------------------------------------------

    const result = await scoreScan({
      examId: exam_id,
      scanId: scan_id,
      name,
    });


    // ----------------------------------------------------------
    // 3. Save scored result
    // ----------------------------------------------------------

    const resultId = crypto.randomUUID();

    const needsReview =
      result.ambiguous > 0;


    await pool.query(
      `
        INSERT INTO exam_results (
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
          needs_review
        )
        VALUES (
          $1,
          $2,
          $3,
          $4,
          $5,
          $6,
          $7,
          $8,
          $9,
          $10,
          $11,
          $12,
          $13,
          $14,
          $15
        )
      `,
      [
        resultId,

        exam_id,

        scan_id,

        result.roll || null,

        result.registration || null,

        result.correct,

        result.wrong,

        result.blank,

        result.ambiguous,

        result.marks,

        result.max_marks,

        result.percentage,

        result.grade,

        result.passed,

        needsReview,
      ]
    );


    // ----------------------------------------------------------
    // 4. Return result
    // ----------------------------------------------------------

    return res.status(200).json({
      message:
        'OMR scan scored and result saved successfully',

      result_id:
        resultId,

      exam_id,

      scan_id,

      result,
    });

  } catch (error) {

    console.error(
      'Scoring API error:',
      error.message
    );

    return res.status(500).json({
      message:
        error.message,
    });
  }
});


module.exports = router;