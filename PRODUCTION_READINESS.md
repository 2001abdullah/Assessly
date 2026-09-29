# Production readiness review

Reviewed: 2026-09-29

## Verdict

Assessly is suitable for controlled beta testing, but it is not ready for an
unrestricted production launch. The core client/API/OMR flow exists and access
ownership has automated coverage. The release blockers below should be closed
before processing real student records at scale.

## Release blockers

1. **Git history:** current scan persistence is PostgreSQL only and the 82
   runtime JSON files were removed from the working tree. If they held real
   student data, purge them from remote Git history after committing or stashing
   all work; history rewriting is intentionally not run on a dirty worktree.
2. **External service configuration:** password recovery now uses hashed,
   single-use, 15-minute codes, but the Render SMTP variables must be populated
   with a production mail provider before deployment.
3. **Infrastructure monitoring:** the API emits structured JSON logs, request
   IDs, default process metrics, and request-duration metrics at `/metrics`.
   Connect those outputs to a log/metrics provider and configure alert rules.
4. **Test depth:** maintained analyzer, widget, ownership, and Python-path tests
   pass. Database migration, SMTP, scoring, and full device-to-API flows still
   need an isolated CI database and external-service test environment.
5. **Store publication:** Android uses a release-only upload key and produces an
   AAB, but Play Console credentials, listing assets, Data safety answers,
   privacy-policy URL, and account-deletion URL still require owner setup.

## Architecture and data flow

```text
Flutter UI -> provider/service layer -> HTTPS REST API
                                      -> PostgreSQL
                                      -> Python OMR subprocess -> scan JSON
```

- `lib/screens/` contains user workflows.
- `lib/providers/` owns screen-facing state.
- `lib/services/` contains API and grading boundaries.
- `backend/server.js` composes public authentication routes and protected API
  routers.
- `backend/middleware/ownership.js` enforces resource ownership.
- `backend/omr/` contains the Python scanner and answer-sheet generator.
- `backend/migrations/` is the source of truth for database schema changes.

## Required release checks

```bash
flutter analyze
flutter test
cd backend
npm test
npm run migrate
npm run test:db
```

Also verify a release build with the production API URL, `/health` against the
deployed database, registration/login/logout, exam CRUD, answer-key entry,
camera and gallery scans, scoring, result history, and cross-account isolation.

## Deployment checklist

- Use HTTPS only and inject `API_BASE_URL` at build time.
- Store `DATABASE_URL` and a high-entropy `JWT_SECRET` in the platform secret
  store; never in source control.
- Back up PostgreSQL and test restoration.
- Apply migrations once per release and record their outcome.
- Set request-body and upload limits at both proxy and API layers.
- Define retention rules for scan results; uploaded images are temporary and
  deleted after processing.
- Verify in-app account deletion and publish a public account-deletion page for
  Google Play.
- Set `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, and `EMAIL_FROM`
  in Render and verify delivery, expiry, reuse prevention, and invalid codes.
- Configure Google Android/Web OAuth clients, Render `GOOGLE_CLIENT_ID`, the
  `GOOGLE_WEB_CLIENT_ID` Actions secret, and both upload/app-signing certificate
  fingerprints before testing Google sign-in on a Play-distributed build.
- Configure the monitoring service to scrape `/metrics` with
  `Authorization: Bearer <METRICS_TOKEN>`.
- Add privacy policy, support contact, and incident-response ownership.
- Run dependency and container vulnerability scanning in CI.
- Pin a supported Flutter SDK and Node.js major version in CI/deployment.

## Repository hygiene

Generated build output, dependencies, virtual environments, secrets, uploads,
and future OMR runtime results are ignored. Previously tracked runtime results
and obsolete image fixtures have been removed from the working tree. If those
files contained real personal data, purge them from remote Git history after
the current dirty worktree has been safely committed or stashed.
