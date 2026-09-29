// OMR routes, mounted at /api/omr (JWT required, upload rate limit).
//
//   POST /scan                multipart: image, exam_id, optional template
//                             -> engine scan JSON + result_id (the scan id)
//   POST /batch               multipart: images[], exam_id
//                             -> scans AND scores each image
//   GET  /exam/:exam_id/sheet -> printable answer-sheet PDF for the exam
//
// Every request works in its own temp directory, which is deleted afterwards.
// Uploaded images are never kept; only the structured scan is stored
// (omr_scans + omr_answers).
//
// Answer-sheet layout: unless a template JSON is uploaded, the template is
// regenerated from the exam (question count, roll/registration digits) with
// omr/generate.py. Generation is deterministic, so this matches the PDF the
// teacher printed from GET /exam/:exam_id/sheet.

const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const express = require('express');
const multer = require('multer');
const pool = require('../config/db');
const { runPythonJson, saveResult, scoreScan } = require('../services/scoring');
const { userOwnsExam } = require('../middleware/ownership');

const router = express.Router();

const MAX_IMAGE_BYTES = 15 * 1024 * 1024;
// Uploads are held in memory, so this bounds one batch request's RAM use.
const MAX_BATCH_IMAGES = 20;

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_IMAGE_BYTES },
});

const OMR_DIR = path.resolve(__dirname, '..', 'omr');
const SCAN_SCRIPT = path.join(OMR_DIR, 'scan.py');
const GENERATE_SCRIPT = path.join(OMR_DIR, 'generate.py');

async function withTempDir(prefix, fn) {
  const dir = await fs.promises.mkdtemp(path.join(os.tmpdir(), prefix));
  try {
    return await fn(dir);
  } finally {
    await fs.promises.rm(dir, { recursive: true, force: true });
  }
}

async function loadExam(examId) {
  const result = await pool.query(
    'SELECT title, subject, total_questions, roll_digits, registration_digits FROM exams WHERE id = $1',
    [examId],
  );
  return result.rows[0];
}

// Runs omr/scan.py on one image; resolves with the engine's SheetScan JSON.
function runScanner(imagePath, templatePath, sourceName) {
  return runPythonJson(SCAN_SCRIPT, [
    '--image', imagePath,
    '--template', templatePath,
    '--source-name', sourceName,
  ]);
}

// Renders the exam's answer sheet to `pdfPath` and, if given, writes the
// matching template JSON (bubble positions) to `templatePath`.
function runGenerator(pdfPath, exam, templatePath) {
  return runPythonJson(GENERATE_SCRIPT, [
    '--exam-name', String(exam.title),
    '--subject', String(exam.subject || ''),
    '--questions', String(exam.total_questions),
    '--roll-digits', String(exam.roll_digits ?? 7),
    '--registration-digits', String(exam.registration_digits ?? 10),
    '--output', pdfPath,
    ...(templatePath ? ['--template-output', templatePath] : []),
  ], { parseJson: false });
}

async function generateTemplate(dir, exam) {
  const templatePath = path.join(dir, 'exam-template.json');
  await runGenerator(path.join(dir, 'exam-sheet.pdf'), exam, templatePath);
  return templatePath;
}

// Scans one uploaded image in `dir` and stores the result. Returns
// { scanId, result }.
async function scanImage({ dir, image, templatePath, examId }) {
  const scanId = crypto.randomUUID();
  const sourceName = image.originalname || scanId;
  // Fixed file name: the client-supplied name is only used as a label.
  const extension = path.extname(sourceName);
  const safeExtension = /^\.[a-z0-9]{1,5}$/i.test(extension) ? extension : '';
  const imagePath = path.join(dir, `upload-${scanId}${safeExtension}`);
  await fs.promises.writeFile(imagePath, image.buffer);

  const result = await runScanner(imagePath, templatePath, sourceName);
  await saveScanResult({ examId, scanId, result, sourceName });
  return { scanId, result };
}

// Stores the engine output: one omr_scans row (summary + raw JSON) and one
// omr_answers row per question, in a single transaction.
async function saveScanResult({ examId, scanId, result, sourceName }) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `
        INSERT INTO omr_scans (
          id, exam_id, source_name, template_id, ok, roll_number,
          registration_number, qr_payload, needs_review, quality, warnings,
          errors, raw_result
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb,
                $11::jsonb, $12::jsonb, $13::jsonb)
      `,
      [
        scanId, examId, result.source || sourceName || '', result.template_id,
        result.ok, result.roll?.value || null, result.registration?.value || null,
        result.qr_payload || '', result.needs_review, JSON.stringify(result.quality || {}),
        JSON.stringify(result.warnings || []), JSON.stringify(result.errors || []),
        JSON.stringify(result),
      ],
    );

    for (const answer of result.answers || []) {
      await client.query(
        `
          INSERT INTO omr_answers
            (scan_id, question_number, value, status, confidence, scores)
          VALUES ($1, $2, $3, $4, $5, $6::jsonb)
        `,
        [scanId, answer.index, answer.value || null, answer.status,
          answer.confidence, JSON.stringify(answer.scores || [])],
      );
    }
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

router.post(
  '/scan',
  upload.fields([{ name: 'image', maxCount: 1 }, { name: 'template', maxCount: 1 }]),
  async (req, res) => {
    const image = req.files?.image?.[0];
    const template = req.files?.template?.[0];
    const { exam_id: examId } = req.body;

    if (!image) return res.status(400).json({ message: 'image file is required' });
    if (!examId) return res.status(400).json({ message: 'exam_id is required' });
    // Only the exam's owner may upload scans for it (404 for anyone else).
    if (!(await userOwnsExam(examId, req.user.id))) {
      return res.status(404).json({ message: 'Exam not found' });
    }

    try {
      const { scanId, result } = await withTempDir('assessly-omr-', async (dir) => {
        let templatePath;
        if (template) {
          templatePath = path.join(dir, 'uploaded-template.json');
          await fs.promises.writeFile(templatePath, template.buffer);
        } else {
          templatePath = await generateTemplate(dir, await loadExam(examId));
        }
        return scanImage({ dir, image, templatePath, examId });
      });

      // result_id is the scan id; pass it as scan_id to POST /api/scoring/score.
      return res.status(200).json({ ...result, result_id: scanId, exam_id: examId });
    } catch (error) {
      console.error('OMR scan error:', error.message);
      return res.status(500).json({ message: 'OMR scan could not be completed' });
    }
  },
);

// Scans and scores up to MAX_BATCH_IMAGES sheets one after another. One bad
// image does not fail the batch: each entry reports ok / error separately.
router.post('/batch', upload.array('images', MAX_BATCH_IMAGES), async (req, res) => {
  const images = req.files || [];
  const { exam_id: examId } = req.body;
  if (!examId) return res.status(400).json({ message: 'exam_id is required' });
  if (!images.length) return res.status(400).json({ message: 'images are required' });
  if (!(await userOwnsExam(examId, req.user.id))) {
    return res.status(404).json({ message: 'Exam not found' });
  }

  try {
    const results = await withTempDir('assessly-omr-batch-', async (dir) => {
      const templatePath = await generateTemplate(dir, await loadExam(examId));
      const entries = [];
      for (const image of images) {
        try {
          const { scanId, result: scan } = await scanImage({ dir, image, templatePath, examId });
          // Not a readable sheet: report it instead of saving a 0-mark result.
          if (!scan.ok) {
            entries.push({
              source: image.originalname,
              ok: false,
              scan_id: scanId,
              error: (scan.errors || []).join('; ') || 'This sheet could not be read',
            });
            continue;
          }
          const scored = await scoreScan({ examId, scanId });
          const resultId = await saveResult({ examId, scanId, scored });
          entries.push({
            source: image.originalname,
            ok: true,
            result_id: resultId,
            scan_id: scanId,
            roll_number: scored.roll || null,
            registration_number: scored.registration || null,
            marks: scored.marks,
            percentage: scored.percentage,
          });
        } catch (error) {
          console.error('OMR batch item error:', error.message);
          entries.push({ source: image.originalname, ok: false, error: 'This sheet could not be read' });
        }
      }
      return entries;
    });
    return res.status(200).json({ exam_id: examId, count: results.length, results });
  } catch (error) {
    console.error('OMR batch error:', error.message);
    return res.status(500).json({ message: 'OMR batch could not be completed' });
  }
});

router.get('/exam/:exam_id/sheet', async (req, res) => {
  const { exam_id: examId } = req.params;
  if (!(await userOwnsExam(examId, req.user.id))) {
    return res.status(404).json({ message: 'Exam not found' });
  }

  const exam = await loadExam(examId);
  const dir = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'assessly-omr-sheet-'));
  const cleanup = () => fs.promises.rm(dir, { recursive: true, force: true });
  const outputPath = path.join(dir, 'omr-sheet.pdf');

  try {
    await runGenerator(outputPath, exam);
    const fileName = `${String(exam.title).replace(/[^a-z0-9]+/gi, '-')}-omr.pdf`;
    // res.download streams asynchronously, so clean up in its callback.
    return res.download(outputPath, fileName, cleanup);
  } catch (error) {
    await cleanup();
    console.error('OMR generation error:', error.message);
    return res.status(500).json({ message: 'Could not generate the answer sheet' });
  }
});

module.exports = router;
