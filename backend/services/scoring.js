// Scoring and the Node <-> Python process boundary.
//
// The OMR engine is Python (backend/omr). Node never imports it; it spawns a
// script, passes file paths as arguments, and reads one JSON document from
// stdout. This module owns:
//
//   resolvePythonPath  which Python executable to use
//   runPythonJson      spawn a script and parse its JSON output
//   scoreScan          load exam + answer key + rules + stored scan from
//                      PostgreSQL and run omr/score.py on them
//   saveResult         persist a scored result in exam_results
//
// routes/omr.js reuses resolvePythonPath/runPythonJson for scanning and sheet
// generation.

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { spawn } = require('child_process');
const pool = require('../config/db');

const OMR_DIR = path.join(__dirname, '..', 'omr');
const BUNDLED_PYTHON = path.join(OMR_DIR, '.venv', 'Scripts', 'python.exe');
const SCORING_SCRIPT = path.join(OMR_DIR, 'score.py');

// Statuses the OMR engine uses for a question it could not read confidently.
const AMBIGUOUS_STATUSES = new Set(['multi', 'faint', 'unreadable']);

/**
 * A problem the caller can fix (missing answer key, wrong exam, ...). Routes
 * send its message to the client; any other error is logged and hidden.
 */
class ScoringError extends Error {
  constructor(message, status = 422) {
    super(message);
    this.name = 'ScoringError';
    this.status = status;
  }
}

/**
 * OMR_PYTHON wins (Docker/Render set it to the image's virtualenv). On
 * Windows development machines, backend/omr/.venv is used when present.
 * Dependencies are injectable for tests.
 */
function resolvePythonPath({
  env = process.env,
  platform = process.platform,
  existsSync = fs.existsSync,
} = {}) {
  if (env.OMR_PYTHON && env.OMR_PYTHON.trim()) {
    return env.OMR_PYTHON.trim();
  }
  if (platform === 'win32') {
    return existsSync(BUNDLED_PYTHON) ? BUNDLED_PYTHON : 'python';
  }
  return 'python3';
}

/**
 * Runs `python <script> ...args`. Resolves with the parsed stdout JSON when
 * `parseJson` is true (otherwise with undefined); rejects with stderr on a
 * non-zero exit.
 */
function runPythonJson(script, args, { parseJson = true } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(resolvePythonPath(), [script, ...args], {
      cwd: path.join(__dirname, '..'),
      windowsHide: true,
    });

    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk.toString(); });
    child.stderr.on('data', (chunk) => { stderr += chunk.toString(); });

    child.on('error', (error) => {
      reject(new Error(`Could not start Python (${path.basename(script)}): ${error.message}`));
    });
    child.on('close', (code) => {
      if (code !== 0) {
        return reject(new Error(stderr.trim() || `${path.basename(script)} exited with code ${code}`));
      }
      if (!parseJson) return resolve();
      try {
        return resolve(JSON.parse(stdout));
      } catch (error) {
        return reject(new Error(`${path.basename(script)} returned invalid JSON: ${error.message}`));
      }
    });
  });
}

/**
 * Turns a detected roll/registration field into display text. An exact value
 * wins; otherwise the per-digit readings are joined with '?' for unread
 * digits ([2, 6, null] -> "26?"). Returns null when nothing was read.
 */
function formatDetectedIdentifier(field, fallback = null) {
  const exact = fallback ?? field?.value;
  if (exact !== null && exact !== undefined && String(exact).trim()) {
    return String(exact).trim();
  }
  if (!Array.isArray(field?.digits)) return null;

  const isRead = (digit) => digit !== null && digit !== undefined;
  if (!field.digits.some(isRead)) return null;
  return field.digits.map((digit) => (isRead(digit) ? String(digit) : '?')).join('');
}

/**
 * Builds the AnswerKey JSON that omr/score.py expects. Marking is exam-wide:
 * the same marks_correct / marks_wrong / marks_blank apply to every question.
 */
function buildPythonAnswerKey(exam, answerKeyRows, scoringRules) {
  const answers = {};
  for (const row of answerKeyRows) {
    answers[String(Number(row.question_number))] = row.correct_answer
      ? String(row.correct_answer).trim().toUpperCase()
      : null;
  }

  return {
    key_id: String(exam.id),
    name: exam.title,
    total_questions: Number(exam.total_questions),
    answers,
    rules: {
      marks_correct: Number(scoringRules.marks_correct),
      marks_wrong: Number(scoringRules.marks_wrong),
      marks_blank: Number(scoringRules.marks_blank),
      pass_percentage: Number(scoringRules.pass_percentage),
      ambiguous_as: scoringRules.ambiguous_as,
      clamp_negative_total: Boolean(scoringRules.clamp_negative_total),
    },
  };
}

/**
 * Writes the scan and answer key to a temp dir and runs omr/score.py on them.
 * The temp dir is always removed.
 */
async function runPythonScorer(scanData, answerKeyData, options = {}) {
  const tempDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'assessly-score-'));
  try {
    const scanPath = path.join(tempDir, 'scan.json');
    const answerKeyPath = path.join(tempDir, 'answer-key.json');
    await fs.promises.writeFile(scanPath, JSON.stringify(scanData), 'utf8');
    await fs.promises.writeFile(answerKeyPath, JSON.stringify(answerKeyData), 'utf8');

    const args = ['--scan', scanPath, '--answer-key', answerKeyPath];
    if (options.questions) args.push('--questions', String(options.questions));
    if (options.name) args.push('--name', options.name);

    return await runPythonJson(SCORING_SCRIPT, args);
  } finally {
    await fs.promises.rm(tempDir, { recursive: true, force: true });
  }
}

// Rebuilds a roll/registration field from the stored scan, preferring the
// (possibly corrected) column value over the engine's raw reading.
function identifierField(rawField, columnValue, name) {
  if (rawField) return { ...rawField, value: columnValue || rawField.value || null };
  return columnValue ? { name, value: columnValue } : null;
}

/**
 * Scores a stored OMR scan against its exam's answer key and scoring rules.
 * Does not save anything; see saveResult. Throws ScoringError for problems
 * the user can fix.
 */
async function scoreScan({ examId, scanId, name = '' }) {
  const examResult = await pool.query(
    'SELECT id, title, total_questions FROM exams WHERE id = $1',
    [examId],
  );
  if (examResult.rows.length === 0) throw new ScoringError('Exam not found', 404);
  const exam = examResult.rows[0];

  const answerKeyResult = await pool.query(
    `SELECT question_number, correct_answer
       FROM answer_keys
      WHERE exam_id = $1
      ORDER BY question_number ASC`,
    [examId],
  );
  if (answerKeyResult.rows.length === 0) {
    throw new ScoringError('No answer key found for this exam');
  }

  const scoringRulesResult = await pool.query(
    `SELECT marks_correct, marks_wrong, marks_blank, pass_percentage,
            ambiguous_as, clamp_negative_total
       FROM exam_scoring_rules
      WHERE exam_id = $1`,
    [examId],
  );
  if (scoringRulesResult.rows.length === 0) {
    throw new ScoringError('Scoring rules not found for this exam');
  }

  const scanResult = await pool.query('SELECT * FROM omr_scans WHERE id = $1', [scanId]);
  if (scanResult.rows.length === 0) throw new ScoringError('OMR scan not found', 404);
  const scanRow = scanResult.rows[0];
  if (String(scanRow.exam_id) !== String(examId)) {
    throw new ScoringError('OMR scan does not belong to this exam', 400);
  }

  const answerResult = await pool.query(
    `SELECT question_number, value, status, confidence, scores
       FROM omr_answers
      WHERE scan_id = $1
      ORDER BY question_number ASC`,
    [scanId],
  );

  const rawResult = scanRow.raw_result && typeof scanRow.raw_result === 'object'
    ? scanRow.raw_result
    : {};
  const rawRoll = rawResult.roll && typeof rawResult.roll === 'object' ? rawResult.roll : null;
  const rawRegistration = rawResult.registration && typeof rawResult.registration === 'object'
    ? rawResult.registration
    : null;

  // Same shape as the engine's SheetScan JSON (omr_engine/models.py).
  const scanData = {
    ok: scanRow.ok,
    template_id: scanRow.template_id,
    source: scanRow.source_name || '',
    roll: identifierField(rawRoll, scanRow.roll_number, 'roll'),
    registration: identifierField(rawRegistration, scanRow.registration_number, 'registration'),
    answers: answerResult.rows.map((row) => ({
      key: `question_${row.question_number}`,
      kind: 'question',
      index: Number(row.question_number),
      owner: '',
      value: row.value || null,
      status: row.status || 'blank',
      confidence: row.confidence ? Number(row.confidence) : 0,
      scores: row.scores || [],
      labels: [],
    })),
    quality: scanRow.quality || {},
    warnings: scanRow.warnings || [],
    errors: scanRow.errors || [],
    qr_payload: scanRow.qr_payload || '',
    elapsed_ms: 0,
    needs_review: scanRow.needs_review || false,
    debug_image_path: '',
  };

  const scoredResult = await runPythonScorer(
    scanData,
    buildPythonAnswerKey(exam, answerKeyResult.rows, scoringRulesResult.rows[0]),
    { questions: Number(exam.total_questions), name },
  );

  scoredResult.roll = formatDetectedIdentifier(
    rawRoll,
    scoredResult.roll || scanRow.roll_number,
  );
  scoredResult.registration = formatDetectedIdentifier(
    rawRegistration,
    scoredResult.registration || scanRow.registration_number,
  );
  return scoredResult;
}

/**
 * Stores a scoreScan() result. A scan has at most one result
 * (UNIQUE(scan_id)); if another request saved one first, that row's id is
 * returned instead of failing. Returns the result id.
 */
async function saveResult({ examId, scanId, scored }) {
  const inserted = await pool.query(
    `INSERT INTO exam_results
       (id, exam_id, scan_id, roll_number, registration_number, correct,
        wrong, blank, ambiguous, marks, max_marks, percentage, grade,
        passed, needs_review)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
     ON CONFLICT (scan_id) DO NOTHING
     RETURNING id`,
    [
      crypto.randomUUID(), examId, scanId,
      scored.roll || null, scored.registration || null,
      scored.correct, scored.wrong, scored.blank, scored.ambiguous,
      scored.marks, scored.max_marks, scored.percentage, scored.grade,
      scored.passed, scored.ambiguous > 0,
    ],
  );
  if (inserted.rows[0]) return inserted.rows[0].id;

  const existing = await pool.query('SELECT id FROM exam_results WHERE scan_id = $1', [scanId]);
  return existing.rows[0].id;
}

module.exports = {
  AMBIGUOUS_STATUSES,
  ScoringError,
  buildPythonAnswerKey,
  formatDetectedIdentifier,
  resolvePythonPath,
  runPythonJson,
  runPythonScorer,
  saveResult,
  scoreScan,
};
