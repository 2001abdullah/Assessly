const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const pool = require('../config/db');

const BUNDLED_PYTHON = path.join(
  __dirname,
  '..',
  'omr',
  '.venv',
  'Scripts',
  'python.exe'
);

function resolvePythonPath({
  env = process.env,
  platform = process.platform,
  existsSync = fs.existsSync,
} = {}) {
  if (env.OMR_PYTHON && env.OMR_PYTHON.trim()) {
    return env.OMR_PYTHON.trim();
  }

  if (platform === 'win32') {
    return existsSync(BUNDLED_PYTHON)
      ? BUNDLED_PYTHON
      : 'python';
  }

  return 'python3';
}

const SCORING_SCRIPT = path.join(
  __dirname,
  '..',
  'omr',
  'score.py'
);

/**
 * Convert PostgreSQL exam data and answer-key rows
 * into the AnswerKey format expected by Python.
 *
 * IMPORTANT:
 * Marking is EXAM-WIDE.
 *
 * Example:
 *
 *   marks_correct = 1
 *   marks_wrong   = -0.5
 *   marks_blank   = 0
 *
 * These same values are applied to every question.
 */
function buildPythonAnswerKey(
  exam,
  answerKeyRows,
  scoringRules
) {
  const answers = {};

  for (const row of answerKeyRows) {
    const questionNumber =
      Number(row.question_number);

    answers[String(questionNumber)] =
      row.correct_answer
        ? String(row.correct_answer)
            .trim()
            .toUpperCase()
        : null;
  }

  return {
    key_id: String(exam.id),

    name: exam.title,

    total_questions:
      Number(exam.total_questions),

    answers,

    rules: {
      marks_correct:
        Number(scoringRules.marks_correct),

      marks_wrong:
        Number(scoringRules.marks_wrong),

      marks_blank:
        Number(scoringRules.marks_blank),

      pass_percentage:
        Number(scoringRules.pass_percentage),

      ambiguous_as:
        scoringRules.ambiguous_as,

      clamp_negative_total:
        Boolean(
          scoringRules.clamp_negative_total
        ),
    },
  };
}

/**
 * Run the Python scoring worker.
 */
function runPythonScorer(
  scanData,
  answerKeyData,
  options = {}
) {
  return new Promise(
    (resolve, reject) => {

      const tempDir =
        fs.mkdtempSync(
          path.join(
            os.tmpdir(),
            'assessly-score-'
          )
        );

      const scanPath =
        path.join(
          tempDir,
          'scan.json'
        );

      const answerKeyPath =
        path.join(
          tempDir,
          'answer-key.json'
        );

      try {

        fs.writeFileSync(
          scanPath,
          JSON.stringify(scanData),
          'utf8'
        );

        fs.writeFileSync(
          answerKeyPath,
          JSON.stringify(answerKeyData),
          'utf8'
        );

        const args = [
          SCORING_SCRIPT,
          '--scan',
          scanPath,
          '--answer-key',
          answerKeyPath,
        ];

        if (options.questions) {
          args.push(
            '--questions',
            String(options.questions)
          );
        }

        if (options.name) {
          args.push(
            '--name',
            options.name
          );
        }

        const python = spawn(
          resolvePythonPath(),
          args,
          {
            windowsHide: true,
          }
        );

        let stdout = '';
        let stderr = '';

        python.stdout.on(
          'data',
          (data) => {
            stdout +=
              data.toString();
          }
        );

        python.stderr.on(
          'data',
          (data) => {
            stderr +=
              data.toString();
          }
        );

        python.on(
          'error',
          (error) => {
            cleanup();

            reject(
              new Error(
                `Could not start Python scoring process: ${error.message}`
              )
            );
          }
        );

        python.on(
          'close',
          (code) => {
            cleanup();

            if (code !== 0) {
              return reject(
                new Error(
                  stderr.trim() ||
                  `Python scoring process exited with code ${code}`
                )
              );
            }

            try {

              const result =
                JSON.parse(
                  stdout
                );

              resolve(result);

            } catch (error) {

              reject(
                new Error(
                  `Invalid scoring output: ${error.message}\n${stdout}`
                )
              );
            }
          }
        );

      } catch (error) {

        cleanup();

        reject(error);
      }

      function cleanup() {
        try {
          fs.rmSync(
            tempDir,
            {
              recursive: true,
              force: true,
            }
          );
        } catch (error) {
          console.error(
            'Scoring cleanup error:',
            error.message
          );
        }
      }
    }
  );
}

/**
 * Score an existing OMR scan against
 * an exam's answer key.
 */
async function scoreScan({
  examId,
  scanId,
  name = '',
}) {

  const examResult =
    await pool.query(
      `
        SELECT
          id,
          title,
          total_questions
        FROM exams
        WHERE id = $1
      `,
      [examId]
    );

  if (
    examResult.rows.length === 0
  ) {
    throw new Error(
      'Exam not found'
    );
  }

  const exam =
    examResult.rows[0];

  const answerKeyResult =
    await pool.query(
      `
        SELECT
          question_number,
          correct_answer
        FROM answer_keys
        WHERE exam_id = $1
        ORDER BY question_number ASC
      `,
      [examId]
    );

  if (
    answerKeyResult.rows.length === 0
  ) {
    throw new Error(
      'No answer key found for this exam'
    );
  }

  const scoringRulesResult =
    await pool.query(
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
      [examId]
    );

  if (
    scoringRulesResult.rows.length === 0
  ) {
    throw new Error(
      'Scoring rules not found for this exam'
    );
  }

  const scoringRules =
    scoringRulesResult.rows[0];

  const scanResult =
    await pool.query(
      `
        SELECT
          *
        FROM omr_scans
        WHERE id = $1
      `,
      [scanId]
    );

  if (
    scanResult.rows.length === 0
  ) {
    throw new Error(
      'OMR scan not found'
    );
  }

  // Make sure this scan belongs to the
  // exam being scored.
  const scanRow =
    scanResult.rows[0];

  if (
    String(scanRow.exam_id) !==
    String(examId)
  ) {
    throw new Error(
      'OMR scan does not belong to this exam'
    );
  }

  const answerResult =
    await pool.query(
      `
        SELECT
          question_number,
          value,
          status,
          confidence,
          scores
        FROM omr_answers
        WHERE scan_id = $1
        ORDER BY question_number ASC
      `,
      [scanId]
    );

  const scanData = {

    ok:
      scanRow.ok,

    template_id:
      scanRow.template_id,

    source:
      scanRow.source_name || '',

    roll:
      scanRow.roll_number
        ? {
            name: 'roll',
            value:
              scanRow.roll_number,
          }
        : null,

    registration:
      scanRow.registration_number
        ? {
            name: 'registration',
            value:
              scanRow.registration_number,
          }
        : null,

    answers:
      answerResult.rows.map(
        (row) => ({
          key:
            `question_${row.question_number}`,
          kind:
            'question',
          index:
            Number(
              row.question_number
            ),
          owner:
            '',
          value:
            row.value || null,
          status:
            row.status || 'blank',
          confidence:
            row.confidence
              ? Number(
                  row.confidence
                )
              : 0,
          scores:
            row.scores || [],
          labels:
            [],
        })
      ),

    quality:
      scanRow.quality || {},

    warnings:
      scanRow.warnings || [],

    errors:
      scanRow.errors || [],

    qr_payload:
      scanRow.qr_payload || '',

    elapsed_ms:
      0,

    needs_review:
      scanRow.needs_review || false,

    debug_image_path:
      '',
  };

  const answerKeyData =
    buildPythonAnswerKey(
      exam,
      answerKeyResult.rows,
      scoringRules
    );

  return runPythonScorer(
    scanData,
    answerKeyData,
    {
      questions:
        Number(
          exam.total_questions
        ),

      name,
    }
  );
}

module.exports = {
  buildPythonAnswerKey,
  resolvePythonPath,
  runPythonScorer,
  scoreScan,
};
