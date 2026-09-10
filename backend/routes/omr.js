const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const express = require('express');
const multer = require('multer');
const pool = require('../config/db');

const router = express.Router();

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 15 * 1024 * 1024 },
});

const backendRoot = path.resolve(__dirname, '..');

const defaultTemplate = path.join(
  backendRoot,
  'omr',
  'templates',
  'sample_template.json',
);

const resultDirectory = path.join(
  backendRoot,
  'data',
  'omr-results',
);

const pythonScript = path.join(
  backendRoot,
  'omr',
  'scan.py',
);

const bundledPython = path.join(
  backendRoot,
  'omr',
  '.venv',
  'Scripts',
  'python.exe',
);


function runScanner(imagePath, templatePath, sourceName) {
  const python = process.env.OMR_PYTHON
    || (
      process.platform === 'win32' &&
      fs.existsSync(bundledPython)
        ? bundledPython
        : (
          process.platform === 'win32'
            ? 'python'
            : 'python3'
        )
    );

  return new Promise((resolve, reject) => {
    const child = spawn(
      python,
      [
        pythonScript,
        '--image',
        imagePath,
        '--template',
        templatePath,
        '--source-name',
        sourceName,
      ],
      {
        cwd: backendRoot,
        windowsHide: true,
      },
    );

    let stdout = '';
    let stderr = '';

    child.stdout.on(
      'data',
      (chunk) => {
        stdout += chunk.toString();
      },
    );

    child.stderr.on(
      'data',
      (chunk) => {
        stderr += chunk.toString();
      },
    );

    child.on(
      'error',
      (error) => {
        reject(error);
      },
    );

    child.on(
      'close',
      (code) => {
        if (code !== 0) {
          reject(
            new Error(
              stderr.trim()
              || `OMR scanner exited with code ${code}`,
            ),
          );

          return;
        }

        try {
          resolve(
            JSON.parse(stdout),
          );
        } catch (error) {
          reject(
            new Error(
              `OMR scanner returned invalid JSON: ${error.message}`,
            ),
          );
        }
      },
    );
  });
}


router.post(
  '/scan',
  upload.fields([
    {
      name: 'image',
      maxCount: 1,
    },
    {
      name: 'template',
      maxCount: 1,
    },
  ]),
  async (req, res) => {

    const image =
      req.files?.image?.[0];

    const template =
      req.files?.template?.[0];

    const { exam_id } =
      req.body;


    // ------------------------------------------------------------
    // Validate image
    // ------------------------------------------------------------

    if (!image) {
      return res.status(400).json({
        message: 'image file is required',
      });
    }


    // ------------------------------------------------------------
    // Validate exam_id
    // ------------------------------------------------------------

    if (!exam_id) {
      return res.status(400).json({
        message: 'exam_id is required',
      });
    }


    // ------------------------------------------------------------
    // Verify that the exam exists
    // ------------------------------------------------------------

    const examResult =
      await pool.query(
        `
          SELECT id
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


    const requestId =
      crypto.randomUUID();

    let temporaryDirectory;


    try {

      // ----------------------------------------------------------
      // Create temporary directory
      // ----------------------------------------------------------

      temporaryDirectory =
        await fs.promises.mkdtemp(
          path.join(
            os.tmpdir(),
            'assessly-omr-',
          ),
        );


      // ----------------------------------------------------------
      // Temporary image path
      // ----------------------------------------------------------

      const imagePath =
        path.join(
          temporaryDirectory,
          path.basename(
            image.originalname
              || 'scan-image',
          ),
        );


      // ----------------------------------------------------------
      // Template path
      // ----------------------------------------------------------

      const templatePath =
        template
          ? path.join(
              temporaryDirectory,
              path.basename(
                template.originalname
                  || 'template.json',
              ),
            )
          : defaultTemplate;


      // ----------------------------------------------------------
      // Result JSON path
      // ----------------------------------------------------------

      const resultPath =
        path.join(
          resultDirectory,
          `${requestId}.json`,
        );


      // ----------------------------------------------------------
      // Save uploaded image
      // ----------------------------------------------------------

      await fs.promises.writeFile(
        imagePath,
        image.buffer,
      );


      // ----------------------------------------------------------
      // Save uploaded template if provided
      // ----------------------------------------------------------

      if (template) {
        await fs.promises.writeFile(
          templatePath,
          template.buffer,
        );
      }


      // ----------------------------------------------------------
      // Run Python OMR scanner
      // ----------------------------------------------------------

      const result =
        await runScanner(
          imagePath,
          templatePath,
          image.originalname
            || requestId,
        );


      // ----------------------------------------------------------
      // Database transaction
      // ----------------------------------------------------------

      const client =
        await pool.connect();

      try {

        await client.query(
          'BEGIN',
        );


        // --------------------------------------------------------
        // Save OMR scan
        // --------------------------------------------------------

        await client.query(
          `
            INSERT INTO omr_scans (
              id,
              exam_id,
              source_name,
              template_id,
              ok,
              roll_number,
              registration_number,
              qr_payload,
              needs_review,
              quality,
              warnings,
              errors,
              raw_result
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
              $10::jsonb,
              $11::jsonb,
              $12::jsonb,
              $13::jsonb
            )
          `,
          [
            requestId,

            exam_id,

            result.source
              || image.originalname
              || '',

            result.template_id,

            result.ok,

            result.roll?.value
              || null,

            result.registration?.value
              || null,

            result.qr_payload
              || '',

            result.needs_review,

            JSON.stringify(
              result.quality
                || {},
            ),

            JSON.stringify(
              result.warnings
                || [],
            ),

            JSON.stringify(
              result.errors
                || [],
            ),

            JSON.stringify(
              result,
            ),
          ],
        );


        // --------------------------------------------------------
        // Save individual answers
        // --------------------------------------------------------

        for (
          const answer
          of result.answers || []
        ) {

          await client.query(
            `
              INSERT INTO omr_answers (
                scan_id,
                question_number,
                value,
                status,
                confidence,
                scores
              )
              VALUES (
                $1,
                $2,
                $3,
                $4,
                $5,
                $6::jsonb
              )
            `,
            [
              requestId,

              answer.index,

              answer.value
                || null,

              answer.status,

              answer.confidence,

              JSON.stringify(
                answer.scores
                  || [],
              ),
            ],
          );
        }


        // --------------------------------------------------------
        // Commit transaction
        // --------------------------------------------------------

        await client.query(
          'COMMIT',
        );

      } catch (error) {

        await client.query(
          'ROLLBACK',
        );

        throw error;

      } finally {

        client.release();
      }


      // ----------------------------------------------------------
      // Save result JSON file
      // ----------------------------------------------------------

      await fs.promises.mkdir(
        resultDirectory,
        {
          recursive: true,
        },
      );

      await fs.promises.writeFile(
        resultPath,
        JSON.stringify(
          result,
          null,
          2,
        ),
        'utf8',
      );


      // ----------------------------------------------------------
      // Response
      // ----------------------------------------------------------

      return res.status(200).json({
        ...result,

        result_id:
          requestId,

        exam_id,

        result_file:
          path.relative(
            backendRoot,
            resultPath,
          ),
      });

    } catch (error) {

      console.error(
        'OMR scan error:',
        error.message,
      );

      return res.status(500).json({
        message:
          'OMR scan could not be completed',
      });

    } finally {

      // ----------------------------------------------------------
      // Remove temporary directory
      // ----------------------------------------------------------

      if (temporaryDirectory) {

        await fs.promises.rm(
          temporaryDirectory,
          {
            recursive: true,
            force: true,
          },
        );
      }
    }
  },
);


module.exports = router;