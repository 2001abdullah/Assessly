# Assessly

Assessly is an exam assessment platform designed to make objective-test
evaluation faster, more consistent, and easier to manage. It combines a
cross-platform Flutter application with a Node.js API, PostgreSQL persistence,
and a Python-based optical mark recognition (OMR) pipeline.

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
- OMR answer-sheet image selection from the Flutter application
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

Configure the API base URL in the Flutter client for the device or emulator
being used. Android emulators commonly reach a host machine using
`10.0.2.2` instead of `localhost`.

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
