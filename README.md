# Assessly

Assessly is an exam assessment platform designed to make objective-test
evaluation faster, more consistent, and easier to manage. It combines a
cross-platform Flutter application with a Node.js API, PostgreSQL persistence,
and a Python-based optical mark recognition (OMR) pipeline.

## Install the Android beta

[Download Assessly v1.0.0 Beta 2 for Android](https://github.com/2001abdullah/Assessly/releases/download/v1.0.0-beta.2/Assessly-v1.0.0-beta.2.apk)

[Download the latest Android APK release](https://github.com/2001abdullah/Assessly/releases/latest)

[Build/download an Android release with GitHub Actions](https://github.com/2001abdullah/Assessly/actions/workflows/android-release.yml)

[Build/download the iOS archive with GitHub Actions](https://github.com/2001abdullah/Assessly/actions/workflows/ios-release.yml)

Open the link on an Android device, download the APK, and allow installation
from the browser or file manager if Android prompts you. This beta is intended
for testing and is distributed outside Google Play.

The iOS workflow currently provides an unsigned Xcode archive for testing and
validation. A directly installable iPhone release requires Apple Developer
signing and provisioning.

## The problem

Evaluating paper-based multiple-choice exams manually is repetitive and
time-consuming. It also introduces avoidable risks:

- Human errors when transferring answers from paper to a score sheet
- Slow result turnaround for teachers and administrators
- Difficulty applying consistent negative-marking and pass/fail rules
- Scattered exam definitions, answer keys, and student results
- Limited visibility into the quality of scanned answer sheets

Assessly addresses this workflow by letting an examiner create an exam,
configure its answer key and scoring rules, upload or select a scanned answer
sheet, and receive a structured result with marks, percentage, grade, and
answer statistics.

## Current status

Assessly is an active MVP project. The core assessment workflow is implemented,
while additional production hardening and reporting features are planned.

### Currently working

- User registration and login flow
- Password hashing with bcrypt
- Exam creation, listing, details, and deletion
- Answer-key configuration for objective questions
- Configurable scoring rules, including:
  - Marks for correct answers
  - Marks for wrong answers
  - Marks for blank answers
  - Pass percentage
  - Treatment of ambiguous answers
  - Optional negative-score clamping
- OMR answer-sheet image selection and camera capture from the Flutter application
- Reusable pure-Dart OMR frame analyzer in
  `lib/services/omr_frame_analyzer.dart` for sheet detection and capture coaching
- OMR scanning through the backend and Python processing boundary
- Scan validation and structured scan-result persistence
- Automatic scoring of a completed scan against the selected exam
- Result screen showing:
  - Pass/fail status
  - Marks and maximum marks
  - Percentage and grade
  - Roll and registration information
  - Correct, wrong, blank, and ambiguous answer counts
- Health-check endpoint for backend and PostgreSQL connectivity
- Input validation and user-facing error handling across the main workflow

## Planned improvements

The following items are planned for future iterations:

- Persistent result history and result search/filtering
- Teacher and administrator dashboards with aggregate analytics
- Exporting results to CSV and PDF
- Batch scanning and bulk result processing
- Student-specific result sharing
- Improved scan review tools for low-confidence or ambiguous responses
- Role-based access control for teachers, administrators, and students
- Cloud deployment with managed PostgreSQL and object storage
- Automated database migrations and seed data
- Automated unit, integration, and end-to-end test coverage
- Production observability, rate limiting, and stronger API security
- Polished onboarding, profile management, and account recovery flows

## Technology stack

### Client application

- **Flutter**
- **Dart**
- **Provider** for application state management
- **HTTP** for REST API communication
- **File Picker** for selecting answer-sheet images
- **Image Picker** for taking answer-sheet pictures with the device camera
- **Shared Preferences** for local preferences and session-related storage

### Backend

- **Node.js**
- **Express 5**
- **PostgreSQL**
- **node-postgres (`pg`)** for database access
- **JWT** for authentication tokens
- **bcrypt** for password hashing
- **Multer** for multipart image uploads
- **PDFKit** for PDF-related generation
- **QRCode** for QR-code functionality

### OMR and scoring

- **Python**
- OpenCV-compatible image processing through the OMR engine
- JSON-based process boundary between the Node.js API and Python scanner
- Configurable answer-sheet templates
- Confidence and quality information for scanned fields and answers

## High-level architecture

```text
Flutter application
        |
        | REST / JSON / multipart upload
        v
Node.js + Express API
        |
        +--> PostgreSQL
        |
        +--> Python OMR scanner
                    |
                    +--> Structured scan result
        |
        +--> Scoring and result APIs
```

The Node.js API owns request validation, exam and scoring-rule persistence,
file handling, and orchestration. The Python process focuses on interpreting
the answer-sheet image and returning structured JSON. The Flutter client
consumes the API and presents the workflow and results to the user.

## Project structure

```text
lib/                  Flutter application
  screens/            Authentication, exam, scanning, and result screens
  services/           API-facing client services
  providers/          Flutter state providers
  models/             Client-side models
backend/              Node.js API
  routes/             Authentication, exam, answer-key, scoring, and OMR APIs
  config/             PostgreSQL connection setup
  omr/                Python OMR and scoring process boundary
android/, ios/, ...   Flutter platform projects
```

## Local development

### Prerequisites

- Flutter SDK
- Dart SDK compatible with the version specified in `pubspec.yaml`
- Node.js and npm
- PostgreSQL
- Python with the dependencies required by the OMR engine

### 1. Configure the backend

Create `backend/.env` locally. Do not commit this file:

```env
DB_USER=your_postgres_user
DB_HOST=localhost
DB_NAME=assessly
DB_PASSWORD=your_postgres_password
DB_PORT=5432
JWT_SECRET=replace_with_a_long_random_secret
OMR_PYTHON=path_to_your_python_executable
```

Create the required PostgreSQL database and ensure the schema used by the
backend is available before starting the API.

### 2. Install backend dependencies and start the API

```bash
cd backend
npm install
npm start
```

The API runs on port `5000` by default. For development with automatic
restarts:

```bash
npm run dev
```

The health endpoint is available at:

```text
http://localhost:5000/health
```

### 3. Run the Flutter application

From the repository root:

```bash
flutter pub get
flutter run
```

The Flutter client defaults to `http://10.0.2.2:5000` on Android emulators
because that address points to the host computer from the emulator. A
physical Android phone cannot use `10.0.2.2`; connect the phone and computer
to the same network and start the app with the computer's LAN IPv4 address:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.123:5000
```

Replace `192.168.1.123` with the computer's actual LAN address. The backend
must be running on port `5000`, and the computer firewall must allow inbound
TCP connections to that port. Verify connectivity from the phone browser
using `http://192.168.1.123:5000/health` before trying to register or log in.

To build a phone APK against the deployed Render backend locally:

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://assessly-api.onrender.com
```

You can also build it from GitHub without changing source code. Open
**Actions > Android Release > Run workflow**, enter the current Render API URL
in `api_base_url`, and download the `assessly-android-release` artifact. If a
release tag is supplied, the workflow also attaches the APK to a GitHub
release.

### iOS release

Open **Actions > iOS Release > Run workflow**, enter the Render API URL, and
download the `assessly-ios-unsigned` artifact. This workflow runs on a macOS
runner and provides an unsigned Xcode archive. Installing the app on a
physical iPhone or publishing to the App Store requires an Apple Developer
account, a registered bundle ID, and signing certificates/profiles.
The current iOS bundle ID is `com.example.assessly`.

## API overview

The backend currently exposes endpoints for:

- Authentication and login
- Exam management
- Answer-key management
- Scoring-rule management
- OMR image scanning
- Scan scoring
- Result retrieval
- Service and database health checks

For OMR scanning, the API accepts a multipart image upload at
`POST /api/omr/scan`. The scan is associated with an exam and returns a
structured result that can then be passed to the scoring workflow.

The scan screen supports both **Take Photo** and **Gallery**. The reusable
analyzer in `lib/services/omr_frame_analyzer.dart` is platform-independent
and accepts luminance frames through `LumaFrame`, so live-camera coaching can
be connected without coupling detection logic to Flutter or a camera plugin.
The current capture flow takes a high-quality still image and sends it through
the existing backend OMR pipeline.

## Account status

Registration, JWT login, local token persistence, and token removal on logout
are implemented. A logout action is available from the account icon on the
home screen. Per-user data isolation is **not** implemented yet: the exam,
answer-key, scoring, result, and OMR routes currently do not require the JWT
or filter records by an owner/user ID. Adding that safely requires the
database schema/migration for ownership columns and applying the same
authorization checks consistently across those routes.

## Security

- Never commit `backend/.env` or other secret files.
- Use a strong, unique `JWT_SECRET` outside local development.
- Use separate database credentials for development and production.
- Rotate any credential that has ever been exposed publicly.
- Review the repository history before making the GitHub repository public.

## Contributing

Contributions are welcome. Before opening a pull request:

1. Keep secrets and local environment files out of Git.
2. Explain the user-facing or architectural impact of the change.
3. Test the affected Flutter and backend workflows locally.
4. Keep API and README documentation aligned with the implementation.

## License

No license has been selected for this project yet. Until a license is added,
all rights are reserved by the project owner.
