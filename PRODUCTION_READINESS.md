# Production readiness review

Reviewed: 2026-09-29

## Verdict

**Ready for a controlled beta (known teachers, real but limited data). Not
yet ready for a public store launch.** The code is in good shape. The
remaining blockers are mostly setup work and policy decisions, not missing
features.

## What is in good shape

- **Security basics:** bcrypt passwords, JWTs with a required 32+ character
  secret, rate limits on auth and uploads, parameterised SQL everywhere,
  security headers, redacted logs, and cleartext HTTP disabled in the Android
  release build.
- **Data isolation:** every exam, scan and result lookup is checked against
  the signed-in user and answers 404 for anyone else's data. This is covered
  by `backend/tests/ownership.test.js` and was verified end to end with two
  accounts.
- **Privacy:** uploaded photos are processed in a temporary directory and
  deleted. Account deletion removes all of the user's data. Password-reset
  codes are hashed, single-use and short-lived.
- **Operations:** health check, structured request logs with request ids,
  Prometheus metrics, graceful shutdown, migrations on start, Docker image,
  and a Render blueprint.
- **CI:** `flutter analyze`, `flutter test`, backend unit tests, and
  migration + schema tests against a real PostgreSQL on every push.

## Fixed in this review

| Issue | Impact |
| --- | --- |
| Every scan wrote the exam's generated template into the shared, git-tracked `omr/templates/sample_template.json` | Two teachers scanning at the same time could read sheets with the **other exam's layout**, giving wrong answers. The template is now per request |
| Login looked up the email case-sensitively | Users who typed their email with different capitals could not log in |
| Login answered 404 "user not found" vs 401 "invalid password" | Anyone could check which emails have accounts |
| Batch scoring saved a 0-mark result for images that were not readable sheets | Results for students who don't exist |
| No request timeout except on upload, and a crash on non-JSON error pages | The app could hang forever while a free-tier server woke up, or show a raw `FormatException` |
| Metrics were labelled with raw URL paths | One time series per exam/result id: unbounded memory growth |
| Scoring errors returned internal messages (Python stderr) to the client | Information leak; now generic, with clear messages for fixable problems (missing key or rules) |
| Batch endpoint accepted 100 × 15 MB images in memory | Easy out-of-memory on a small instance; now 20 per request |
| Registration race and duplicate single answers gave 500 | Now 409 |
| Migration 001 opened a transaction it never committed | Worked only by accident |

Dead code was also removed: an empty route file, a duplicate `login.js`
router, an unused copy of the frame analyzer, an unused provider, the unused
synthetic-image module, a stray root `package.json`, and the unused `pdfkit`,
`qrcode` and `pino` dependencies.

## Release blockers

1. **Old scan data in Git history.** Commits before this review contain
   about 80 `backend/data/omr-results/*.json` files, which may hold real roll
   or registration numbers, and the GitHub remote has them. If they are real
   student data, purge them from history (`git filter-repo --path
   backend/data/omr-results --invert-paths`, then force-push and ask
   collaborators to re-clone) **before** the repository becomes public.
2. **Email:** password reset only works once the Render `SMTP_*` and
   `EMAIL_FROM` variables are set to a production mail provider. Verify
   delivery, expiry, and that a code cannot be reused.
3. **Google sign-in:** configure the Android and Web OAuth clients, Render
   `GOOGLE_CLIENT_ID`, the `GOOGLE_WEB_CLIENT_ID` Actions secret, and the
   SHA fingerprints of both the upload and Play App Signing keys.
4. **Hosting plan:** `render.yaml` uses the **free** web service and database.
   The free database expires after a limited period and has no backups, and
   the service sleeps (first request about 50 s). Move to paid plans with
   backups before storing real results, and test a restore.
5. **Store listing:** the Play Console listing, Data safety answers, a public
   HTTPS URL for `PRIVACY_POLICY.md` and `ACCOUNT_DELETION.md`, and a support
   contact. iOS still uses the placeholder bundle ID `com.example.assessly`.
6. **Monitoring:** connect logs and `/metrics` (with `METRICS_TOKEN`) to a
   provider and alert on 5xx rate, latency, and `/health` failures.

## Recommended soon after launch

- Store the JWT in the platform keystore (`flutter_secure_storage`) instead of
  `SharedPreferences`.
- Add a way to revoke tokens (logout currently only forgets the token on the
  device; it stays valid until it expires).
- Run scans in a worker queue instead of inside the HTTP request, so a burst
  of batch uploads cannot exhaust a small instance.
- Add migration tracking (a `schema_migrations` table) before any migration
  that cannot be re-run safely.
- Add backend tests for scoring and the HTTP routes to CI (a smoke test of
  the full register → scan → score → results flow passed locally during
  this review, but it is not in the repository yet).
- Add dependency and container vulnerability scanning to CI, and pin the
  Flutter and Node versions.
- Decide a retention period for scan results and document it in the privacy
  policy.

## Release checklist

```bash
flutter analyze && flutter test
cd backend && npm test && npm run migrate && npm run test:db
```

Then, on a release build pointed at the production API: `/health`,
register / login / Google login / logout, forgot-password email, exam
create / delete, answer key, scoring rules, camera and gallery scans,
batch mode, results and CSV export, a second account cannot see the first
account's data, and account deletion.
