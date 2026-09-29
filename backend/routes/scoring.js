// Scoring route, mounted at /api/scoring (JWT required).
//
//   POST /score  { exam_id, scan_id, name? }
//
// Scores a stored OMR scan (from POST /api/omr/scan) against the exam's answer
// key and scoring rules and saves it in exam_results. Idempotent: scoring the
// same scan again returns the saved result instead of creating a second one.

const express = require('express');
const pool = require('../config/db');
const { ScoringError, saveResult, scoreScan } = require('../services/scoring');
const { requireExamAndScanInBody } = require('../middleware/ownership');

const router = express.Router();

// Shapes a saved exam_results row like a fresh scoreScan() result.
function resultFromRow(row, name) {
  return {
    roll: row.roll_number,
    registration: row.registration_number,
    name,
    correct: row.correct,
    wrong: row.wrong,
    blank: row.blank,
    ambiguous: row.ambiguous,
    marks: Number(row.marks),
    max_marks: Number(row.max_marks),
    percentage: Number(row.percentage),
    grade: row.grade,
    passed: row.passed,
    outcomes: [],
  };
}

router.post('/score', requireExamAndScanInBody, async (req, res) => {
  const { exam_id: examId, scan_id: scanId, name = '' } = req.body;

  if (!examId || !scanId) {
    return res.status(400).json({ message: 'exam_id and scan_id are required' });
  }

  try {
    const existing = await pool.query('SELECT * FROM exam_results WHERE scan_id = $1', [scanId]);
    if (existing.rows.length > 0) {
      const row = existing.rows[0];
      return res.status(200).json({
        message: 'This OMR scan has already been scored',
        result_id: row.id,
        exam_id: row.exam_id,
        scan_id: row.scan_id,
        result: resultFromRow(row, name),
      });
    }

    const result = await scoreScan({ examId, scanId, name });
    const resultId = await saveResult({ examId, scanId, scored: result });

    return res.status(200).json({
      message: 'OMR scan scored and result saved successfully',
      result_id: resultId,
      exam_id: examId,
      scan_id: scanId,
      result,
    });
  } catch (error) {
    if (error instanceof ScoringError) {
      return res.status(error.status).json({ message: error.message });
    }
    console.error('Scoring API error:', error.message);
    return res.status(500).json({ message: 'The sheet could not be scored' });
  }
});

module.exports = router;
