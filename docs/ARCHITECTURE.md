# How Assessly works

This guide is for anyone reading or changing the code. It explains how the
three parts fit together, follows one answer sheet from camera to saved
result, and says where each responsibility lives.

## The big picture

```text
┌──────────────── Flutter app (lib/) ────────────────┐
│ screens/   UI and navigation                        │
│ providers/ app state (ChangeNotifier + provider)    │
│ services/  one class per API area, plain HTTP       │
│ utils/     camera-frame analyzer, image resize      │
└───────────────┬─────────────────────────────────────┘
                │ HTTPS, JSON (+ multipart for photos)
                │ Authorization: Bearer <JWT>
┌───────────────▼─────────── Node API (backend/) ────┐
│ server.js      middleware + router wiring           │
│ middleware/    JWT auth, per-user ownership, logs    │
│ routes/        one router per resource              │
│ services/      scoring + Python bridge, email       │
└───────┬───────────────────────────────┬─────────────┘
        │ SQL (pg pool)                 │ child process, JSON on stdout
┌───────▼────────┐          ┌───────────▼── backend/omr/ ─┐
│ PostgreSQL     │          │ generate.py  sheet PDF       │
│ migrations/    │          │ scan.py      photo -> marks  │
└────────────────┘          │ score.py     marks -> result │
                            │ omr_engine/  the CV library  │
                            └──────────────────────────────┘
```

The API has no image-processing code, and the Python code knows nothing
about HTTP or the database. Node calls Python by spawning a script with
file paths as arguments and parsing the single JSON document it prints (see
`backend/services/scoring.js` → `runPythonJson`).

## The teacher's workflow

1. **Create an exam** (`CreateExamScreen` → `POST /api/exam`): title, subject,
   number of questions, and how many digits the roll and registration numbers
   have.
2. **Print the sheet** (`ExamDetailsScreen` → `GET /api/omr/exam/:id/sheet`).
   `generate.py` lays out a sheet for exactly that configuration: corner
   markers, timing marks down both edges, ID digit columns, and the question
   bubbles.
3. **Enter the answer key** (`AnswerKeyScreen` → `POST /api/answer-key/batch`).
4. **Set scoring rules** (`ScoringRulesScreen` → `PUT /api/scoring-rules/:id`).
   Scoring refuses to run until both the key and the rules exist.
5. **Scan sheets** (`ScanOmrScreen` / `CameraScanScreen`), one at a time or
   in batch mode.
6. **Review results** (`StudentResultsScreen`, `ResultScreen`,
   `ResultsHubScreen`) or export them as CSV.

## Life of one scan

```text
CameraScanScreen                                     (phone)
  │ camera frames ─► OmrFrameAnalyzer: sheet found? upright? sharp? steady?
  │ auto-capture a full-resolution still
  ▼
GradingService.grade()                               lib/services/grading_service.dart
  │ 1. OmrService.scanOmr()   ImageOptimizer shrinks big gallery photos
  │      POST /api/omr/scan   multipart: image, exam_id
  │                                                   (server)
  │      routes/omr.js
  │        ├─ ownership check: exam belongs to caller, else 404
  │        ├─ new temp dir
  │        ├─ generate.py ─► the exam's template JSON (bubble coordinates)
  │        ├─ scan.py ─► SheetScan JSON (answers, roll, quality, errors)
  │        ├─ INSERT omr_scans + omr_answers   (one transaction)
  │        └─ delete temp dir (the photo is never kept)
  │      ◄─ scan JSON + result_id (= the scan's id)
  │
  │    scan.ok == false?  → friendlyScanError() shows advice, stop
  │
  │ 2. ScoringService.scoreScan()
  │      POST /api/scoring/score   { exam_id, scan_id }
  │      routes/scoring.js → services/scoring.js
  │        ├─ already scored? return the saved result (idempotent)
  │        ├─ load exam, answer key, rules, stored scan
  │        ├─ score.py ─► marks, percentage, grade, passed, per-question outcomes
  │        └─ INSERT exam_results
  │      ◄─ result_id + result
  ▼
ResultsProvider.invalidate(examId) → open screens refresh
```

Why the template is regenerated on every scan: sheet generation is
deterministic, so rebuilding it from the exam's settings gives the same
bubble positions as the PDF the teacher printed, and no template file has to
be stored. This is also why changing an exam's question count or digit
counts after printing makes the old printouts unreadable.

**Batch mode** reuses the same pipeline. `BatchScanProvider` is an app-wide
queue: the camera adds each captured photo and keeps going, while the queue
uploads and grades sheets one at a time in the background, even after the
user leaves the scan screen. Failed sheets keep their photo so they can be
retried. The server also has a `POST /api/omr/batch` endpoint for
multi-image uploads, but the app does not use it.

## Scoring rules

Marks are exam-wide: the same values apply to every question.

| Outcome | Marks |
| --- | --- |
| correct | `marks_correct` (≥ 0) |
| wrong | `marks_wrong` (≤ 0; negative for negative marking) |
| blank | `marks_blank` (currently must be 0) |
| ambiguous (two marks, too faint, unreadable) | `ambiguous_as`: `review` = 0 and the result is flagged `needs_review`; `wrong` or `blank` = those marks |
| question with no key | not scored |

`clamp_negative_total` stops a sheet from going below 0 in total. Grades
come from fixed bands in `omr_engine/scoring.py`: A+ ≥ 80, A ≥ 70,
A- ≥ 60, B ≥ 50, C ≥ 40, D ≥ 33, otherwise F. `passed` compares the
percentage with `pass_percentage`.

A saved result keeps the totals from when it was scored. The
question-by-question view (`GET /api/results/:id/details`) recomputes each
question's marks with the current rules, for display only.

## Accounts, tokens and data isolation

- Registration and login live in `routes/auth.js`. Passwords are hashed with
  bcrypt (12 rounds). Emails are stored lower-cased and compared
  case-insensitively. An unknown email and a wrong password get the same 401,
  so nobody can probe which accounts exist.
- Google sign-in: the app gets an ID token from Google, and the server
  verifies it against `GOOGLE_CLIENT_ID`, creates or links the account, and
  issues its own JWT.
- A login returns a JWT (default lifetime 7 days). The app stores it in
  `SharedPreferences` (`AuthService`) and `AuthedHttp` sends it with every
  request.
- **Isolation:** exams have a `user_id`, and everything else hangs off an
  exam. `middleware/ownership.js` checks every exam id, result id and scan id
  a request mentions against the caller. Someone else's data answers 404,
  never 403, so its existence is not revealed. `backend/tests/ownership.test.js`
  covers these checks.
- **Session expiry:** any 401 from the API calls `AuthedHttp.onUnauthorized`,
  which `main.dart` wires to "log out, clear every provider's cache, go to
  Login".
- **Password reset:** a 6-digit code is emailed. Only its SHA-256 hash is
  stored, and it is single-use and expires after 15 minutes. The request
  endpoint always answers 202, whether or not the account exists.
- **Account deletion** (`DELETE /api/auth/me`) removes the user, and database
  cascades remove all of their exams and everything under them.

## Data model

```text
users ─┬─< exams ─┬─< answer_keys           one row per keyed question
       │          ├── exam_scoring_rules     one row per exam
       │          ├─< omr_scans ─< omr_answers   one row per question read
       │          └─< exam_results ── (1:1) omr_scans
       └─< password_reset_tokens
```

Everything under an exam is deleted with it (`ON DELETE CASCADE`), and
reset tokens cascade from their user. `exams.user_id` does not cascade, so
account deletion deletes the user's exams explicitly first.
`omr_scans.raw_result` keeps the engine's full JSON so a scan can be
re-scored later without the photo.

**Migrations** (`backend/migrations/`): `000_initial_schema.sql` builds the
original schema on an empty database, and the numbered files after it add
changes. `scripts/migrate.js` runs all of them on every `npm start`, so each
one must be safe to run repeatedly (`IF NOT EXISTS`, guarded constraints).
To change the schema, add `005_<what>.sql` in the same style.

## The OMR engine in one paragraph

`omr_engine` uses classical computer vision only, with no machine learning.
It finds the four corner markers, corrects perspective to a canonical page,
locks onto the timing marks to correct each row, samples every bubble's
darkness, and calibrates per sheet to decide marked, blank, faint or
multiple. It also reports image quality (sharpness, contrast, skew) and
warnings. See [backend/omr/README.md](../backend/omr/README.md) and the
module docstrings. `pipeline.py` is the best place to start reading.

The phone runs a lightweight Dart port of the corner/timing detection
(`lib/utils/omr_frame_analyzer.dart`) only to coach the user and decide when
to capture. The real reading always happens on the server.

### Tuning the camera on real devices

These settings live in `lib/utils/omr_frame_analyzer.dart` (`AnalyzerConfig`,
`SheetProfile`) and `lib/screens/camera_scan_screen.dart`:

- `minFocus`: if auto-capture keeps saying "Focusing...", lower it. The manual
  shutter always works.
- The camera resolution preset (`veryHigh`, 1080p): use `high` on slow
  phones.
- `SheetProfile`: the physical positions of the corner and timing marks.
  There is one timing mark per question row, and the row count depends on
  the question count, so the camera builds the profile for each exam with
  `SheetProfile.forExam`. That is a Dart copy of the grid solver in
  `omr_engine/layout.py`, and the two must stay in sync (a unit test checks
  it against known backend layouts).

## Where to find things

| I want to change... | Look in |
| --- | --- |
| A screen's layout | `lib/screens/…`, shared widgets in `lib/widgets/app_widgets.dart` |
| Colours, fonts | `lib/themes/` |
| Navigation / route names | `lib/routes/app_routes.dart` |
| The API base URL or timeouts | `lib/services/api_config.dart` |
| How errors are shown for failed scans | `lib/utils/scan_errors.dart` |
| An endpoint | `backend/routes/<resource>.js` (list at the top of each file) |
| Who may access what | `backend/middleware/ownership.js` |
| How a scan becomes marks | `backend/services/scoring.js`, `backend/omr/omr_engine/scoring.py` |
| Sheet layout / bubble reading | `backend/omr/omr_engine/layout.py`, `bubbles.py`, `detect.py` |
| Engine thresholds | `backend/omr/omr_engine/config.py` |
| Database schema | a new file in `backend/migrations/` |
| Deployment | `render.yaml`, `backend/Dockerfile`, `.github/workflows/` |

## Operations

- **Logs:** one JSON line per request (pino), with an `x-request-id` that is
  also returned to the client. Passwords, tokens and `Authorization` headers
  are redacted.
- **Health:** `GET /health` checks the database connection. Render uses it
  as the health check.
- **Metrics:** `GET /metrics` serves Prometheus metrics (process stats plus
  `assessly_http_request_duration_seconds` by route pattern). It only answers
  with `Authorization: Bearer $METRICS_TOKEN` and returns 404 otherwise.
- **Limits:** JSON bodies up to 1 MB, images up to 15 MB, 20 images per
  batch request. Rate limits per IP per 15 minutes: 20 requests to
  `/api/auth` and 60 to `/api/omr`.
- **Shutdown:** on SIGTERM the server stops accepting connections, finishes
  in-flight requests, then closes the database pool.
