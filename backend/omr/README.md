# Assessly OMR engine

Optical mark recognition for Assessly answer sheets, in Python. It uses only
deterministic computer vision (OpenCV + NumPy), with no machine learning and
no network calls. The package has no knowledge of HTTP or the database. The
Node API calls the three scripts below as child processes and reads the JSON
they print on stdout (see `backend/services/scoring.js`).

## Scripts (the process boundary)

| Script | Input | Output (stdout) |
| --- | --- | --- |
| `generate.py` | `--exam-name --subject --questions --roll-digits --registration-digits --output sheet.pdf [--template-output template.json]` | `{template_id, questions}`, plus the PDF and optionally the template JSON |
| `scan.py` | `--image photo.jpg --template template.json [--config engine.json] [--source-name label]` | SheetScan JSON: `ok`, `roll`, `registration`, `answers[]`, `quality`, `warnings`, `errors` |
| `score.py` | `--scan scan.json --answer-key key.json [--questions N] [--name ...]` | ScoredResult JSON: counts, `marks`, `max_marks`, `percentage`, `grade`, `passed`, `outcomes[]` |

Each script exits with a non-zero code and a message on stderr on failure.
An image that is not a readable sheet is **not** a failure: `scan.py` exits 0
with `"ok": false` and the reasons in `errors`.

The template (bubble coordinates) is always regenerated from the exam's
settings. Generation is deterministic, so it matches the printed sheet.
`templates/sample_template.json` is kept only as a reference layout: the
app's camera guide (`lib/utils/omr_frame_analyzer.dart`, `SheetProfile`) was
calibrated against it.

## Package layout (`omr_engine/`)

Read in this order to follow a scan:

| Module | Role |
| --- | --- |
| `pipeline.py` | `OMRProcessor.process()`: runs the whole read, start here |
| `imageops.py` | loading, grayscale, thresholds, sharpness / contrast |
| `detect.py` | finds the corner markers, warps to the canonical page, locks the timing marks (retries rotated orientations) |
| `bubbles.py` | samples each bubble's darkness and calibrates per sheet: marked / blank / faint / multi |
| `decode.py` | turns digit-column readings into roll / registration numbers |
| `models.py` | the result dataclasses (`SheetScan`, `GroupReading`, `ScoredResult`...) and their JSON form |
| `scoring.py` | answer key + rules → marks, grade bands, pass/fail |
| `template.py`, `layout.py` | the sheet description and the layout solver that places everything on A4 |
| `generator.py` | draws the printable PDF (ReportLab) |
| `config.py` | every tunable threshold (`EngineConfig`) |
| `debug.py` | optional overlay image showing what was read (`debug_path`) |

## Running it by hand

```bash
cd backend
omr/.venv/bin/python omr/generate.py --exam-name Demo --questions 40 \
    --output /tmp/demo.pdf --template-output /tmp/demo.json
omr/.venv/bin/python omr/scan.py --image photo.jpg --template /tmp/demo.json
```

## Dependencies

`backend/requirements.txt`: `numpy`, `opencv-python-headless`, `reportlab`.
The Docker image installs them into `/opt/assessly-venv` and sets
`OMR_PYTHON` to it.
