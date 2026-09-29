# Assessly

Assessly grades paper multiple-choice exams from a phone photo. A teacher
creates an exam, prints the answer sheet Assessly generates for it, sets the
answer key and marking scheme, and scans completed sheets with the camera.
Each sheet is read by an optical mark recognition (OMR) engine, scored, and
saved with marks, percentage, grade, pass/fail and a per-question breakdown.

It has three parts:

| Part | Tech | Lives in |
| --- | --- | --- |
| Mobile app | Flutter (Android, iOS) | `lib/` |
| REST API | Node.js, Express 5, PostgreSQL | `backend/` |
| OMR engine | Python, OpenCV, ReportLab | `backend/omr/` |

**Status:** beta. The full workflow works end to end. See
[PRODUCTION_READINESS.md](PRODUCTION_READINESS.md) for what still has to happen
before a public launch.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how the pieces fit, what
  happens during a scan, the data model, and where to find things in the code.
  Start here.
- [docs/API.md](docs/API.md): every HTTP endpoint.
- [backend/omr/README.md](backend/omr/README.md): the Python OMR engine and
  its command-line scripts.
- [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md): release assessment and
  deployment checklist.
- [PRIVACY_POLICY.md](PRIVACY_POLICY.md) and
  [ACCOUNT_DELETION.md](ACCOUNT_DELETION.md): public pages required by the app
  stores.

## Features

- Two roles, chosen after onboarding: **teachers** manage classes and grading;
  **students** see their own results, progress and attendance
- Classes with join codes; join requests the teacher approves; students
  added by hand, with an optional generated login
- Daily attendance (present, absent, late, excused), announcements, and an
  in-app notification centre (push via Firebase when configured)
- Results published per exam, matched to students by roll number; students
  see their rank and the class average
- Charts for teachers (class trends, pass rates, grades, attendance,
  leaderboard, students who need attention) and for students (own trend
  against the class, grades, attendance)
- CSV reports of class results and attendance
- Profiles with photo, details and password change
- Accounts: email/password (bcrypt), Google sign-in, emailed password-reset
  codes, in-app account deletion
- Exams with a configurable number of questions and roll/registration digits
- A printable, exam-specific OMR answer sheet (PDF)
- Answer key entry and a per-exam marking scheme: marks for correct, wrong and
  blank answers, a pass percentage, how to treat ambiguous marks, and optional
  clamping of negative totals to zero
- A live camera scanner that finds the sheet, coaches the user ("move closer",
  "too dark", "glare"...) and captures automatically; gallery import as well
- Batch scanning: capture sheet after sheet while they are graded in the
  background
- Results per exam and per student, question-by-question review, CSV export
- Strict per-user data isolation: users only ever see their own exams

## Local development

### Prerequisites

- Flutter SDK (Dart `^3.13`)
- Node.js 20+ and npm
- PostgreSQL 14+
- Python 3.10+

### 1. Backend

```bash
cd backend
cp .env.example .env          # then fill in the values
npm install
python -m venv omr/.venv
omr/.venv/bin/pip install -r requirements.txt    # Windows: omr\.venv\Scripts\pip ...
npm run migrate               # create / upgrade the schema
npm run dev                   # restarts on file changes
```

On Windows the API finds `omr/.venv` automatically. On macOS and Linux, set
`OMR_PYTHON=omr/.venv/bin/python` in `.env`; otherwise `python3` from `PATH`
is used.

Create the empty database named in `DB_NAME` first. `npm start` also runs
the migrations before starting the server.

The API listens on port `5000`. Check it with
`http://localhost:5000/health`.

Only `DB_*` (or `DATABASE_URL`) and `JWT_SECRET` are required locally.
Password reset needs the `SMTP_*` variables, and Google sign-in needs
`GOOGLE_CLIENT_ID`. Every variable is described in
[backend/.env.example](backend/.env.example).

### 2. App

```bash
flutter pub get
flutter run
```

Without configuration the app talks to `http://10.0.2.2:5000` on an Android
emulator (the host computer) and `http://127.0.0.1:5000` elsewhere. On a
physical phone, put the phone and computer on the same network, allow
inbound TCP 5000 through the computer's firewall, and pass the computer's LAN
address:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.123:5000
```

Open `http://192.168.1.123:5000/health` in the phone's browser first to
confirm that the phone can reach the server.

For Google sign-in, also pass the Web OAuth client ID. It must be the same
value as the backend's `GOOGLE_CLIENT_ID`:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://192.168.1.123:5000 \
  --dart-define=GOOGLE_WEB_CLIENT_ID=1234-abc.apps.googleusercontent.com
```

In Google Cloud, create an Android client and a Web client in the same
project. Register the package name `com.abdullah.assessly` with the SHA-1 and
SHA-256 fingerprints of the debug key, the upload key and the Play App Signing
key.

## Tests

```bash
flutter analyze
flutter test                 # widget tests + OMR frame analyzer

cd backend
npm test                     # ownership + Python path checks (no database)
npm run migrate && npm run test:db   # schema checks (needs a database)
```

CI runs all of these on every push (`.github/workflows/quality.yml`).

## Builds and deployment

- **Backend:** `render.yaml` deploys `backend/Dockerfile` (Node 20 + a Python
  virtualenv) and a managed PostgreSQL database to Render. Migrations run on
  every start.
- **Android:** `flutter build apk --release --dart-define=API_BASE_URL=https://<api>`.
  A release build needs `android/key.properties` and the upload keystore, and
  deliberately fails without them. In GitHub, **Actions → Android Release**
  builds a signed APK and AAB, and pushing a `v*` tag publishes them as a
  GitHub release.
- **Push notifications (Android):** the app reads
  `android/app/google-services.json` (Firebase project, committed; not a
  secret). The backend sends pushes only when `FIREBASE_SERVICE_ACCOUNT`
  holds the Firebase service-account key (secret, set on Render only).
  Without it, notifications stay in the in-app notification centre.
- **iOS:** **Actions → iOS Release** produces an unsigned archive. Installing
  on devices or shipping to the App Store needs an Apple Developer account and
  signing. The bundle ID is still `com.example.assessly` and must be changed
  before release.

## Security notes

- Never commit `backend/.env`, `android/key.properties` or keystores. They
  are already in `.gitignore`.
- Use a long random `JWT_SECRET` (the server refuses to start with fewer than
  32 characters) and a separate `METRICS_TOKEN`.
- Use separate database credentials for development and production.
- Uploaded sheet photos are processed in a temporary directory and deleted.
  Only the structured scan results are stored.

## License

No license has been chosen yet. Until one is added, all rights are reserved by
the project owner.
