// Ownership checks: a signed-in user may only touch exams they created, and
// the answer keys, scoring rules, scans and results that belong to those exams.
//
// Every check answers 404 (not 403) for someone else's data, so the API never
// confirms that another user's exam exists.
//
// Requires authMiddleware to have run first (it sets req.user from the JWT).

const pool = require('../config/db');

// Postgres "invalid input syntax" (e.g. a non-UUID string used as an exam id).
const INVALID_TEXT_REPRESENTATION = '22P02';

async function ownsQuery(sql, params) {
  try {
    const result = await pool.query(sql, params);
    return result.rows.length > 0;
  } catch (error) {
    if (error && error.code === INVALID_TEXT_REPRESENTATION) return false;
    throw error;
  }
}

function userOwnsExam(examId, userId) {
  return ownsQuery(
    'SELECT 1 FROM exams WHERE id = $1 AND user_id = $2',
    [examId, userId],
  );
}

function userOwnsResult(resultId, userId) {
  return ownsQuery(
    `SELECT 1
       FROM exam_results r
       JOIN exams e ON e.id = r.exam_id
      WHERE r.id = $1 AND e.user_id = $2`,
    [resultId, userId],
  );
}

function userOwnsScanOfExam(scanId, examId, userId) {
  return ownsQuery(
    `SELECT 1
       FROM omr_scans s
       JOIN exams e ON e.id = s.exam_id
      WHERE s.id = $1 AND s.exam_id = $2 AND e.user_id = $3`,
    [scanId, examId, userId],
  );
}

function notFound(res, what) {
  return res.status(404).json({ message: `${what} not found` });
}

// For router.param('exam_id' | 'id', examParam): runs for every route in that
// router that has the parameter.
async function examParam(req, res, next, value) {
  try {
    if (!(await userOwnsExam(value, req.user.id))) return notFound(res, 'exam');
    return next();
  } catch (error) {
    return next(error);
  }
}

// For router.param('id', resultParam) where :id is an exam_results id.
async function resultParam(req, res, next, value) {
  try {
    if (!(await userOwnsResult(value, req.user.id))) return notFound(res, 'result');
    return next();
  } catch (error) {
    return next(error);
  }
}

// For routes that receive exam_id in the JSON/form body. A missing exam_id is
// left for the route's own validation to report as 400.
async function requireExamInBody(req, res, next) {
  try {
    const examId = req.body && req.body.exam_id;
    if (!examId) return next();
    if (!(await userOwnsExam(examId, req.user.id))) return notFound(res, 'exam');
    return next();
  } catch (error) {
    return next(error);
  }
}

// For POST /api/scoring/score: the exam must be the caller's AND the scan must
// have been uploaded for that same exam.
async function requireExamAndScanInBody(req, res, next) {
  try {
    const { exam_id: examId, scan_id: scanId } = req.body || {};
    if (!examId || !scanId) return next();
    if (!(await userOwnsExam(examId, req.user.id))) return notFound(res, 'exam');
    if (!(await userOwnsScanOfExam(scanId, examId, req.user.id))) {
      return notFound(res, 'scan');
    }
    return next();
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  userOwnsExam,
  userOwnsResult,
  userOwnsScanOfExam,
  examParam,
  resultParam,
  requireExamInBody,
  requireExamAndScanInBody,
};
