# Per-user accounts: what was wrong and what changed

## Why every user saw the same home screen
1. The database had no owner on exams: `exams` had no `user_id`, and `GET /api/exam` returned every exam.
2. Only `/api/auth/me` checked the login token. Exams, answer keys, scoring rules, scans and results
   were open to anyone, and the app never sent the token to them.
3. The app had no logout button, the profile icon did nothing, and the greeting was a fixed
   "Welcome Back" for everyone.

## What changed
**Backend**
- `middleware/ownership.js` (new): a user can only reach exams they created, and the answer keys, scoring
  rules, scans and results under them. Someone else's data answers 404 (never confirms it exists).
  Scoring also checks the scan was uploaded for that same exam.
- `server.js`: every data route now requires a valid token.
- `routes/exam.js`: new exams are stamped with the creator; the list returns only the caller's exams.
- `routes/{answerKeys,results,scoringRules,scoring,omr}.js`: ownership checks.
- `routes/login.js`: login also returns the user (id, name, email); `/me` returns the profile from the
  database; tokens last 7 days (override with `JWT_EXPIRES_IN`), not 1 hour.
- `migrations/001_add_exam_owner.sql` (new): adds `exams.user_id`.
- `tests/ownership.test.js` (new): `node tests/ownership.test.js`, 12 checks, no database needed.

**App**
- `services/authed_http.dart` (new): sends the signed-in user's token on every request; a 401 signs the
  user out and shows the login screen.
- All data services (`exam`, `answer_key`, `scoring_rules`, `scoring`, `omr`) use it.
- `providers/auth_provider.dart`: keeps the signed-in user; `restoreSession()` validates the saved token
  at start-up (expired token -> login screen instead of a broken home screen).
- `screens/profile_screen.dart` (new) + working profile icon: name, email, Log out.
- Home greeting shows the user's first name.

## Deploy in this order (important)
1. Back up the database.
2. Run `backend/migrations/001_add_exam_owner.sql`.
3. **Assign your existing exams to an account** (the UPDATE at the bottom of the migration). Exams with no
   owner are invisible to everyone, by design.
4. Deploy the backend and the new app together. An old app build sends no token and will get 401 everywhere.

## Not tested / not done
- The Node changes were syntax-checked and the ownership logic tested against an in-memory stand-in for
  Postgres. Express and pg were not installed here, so the full server was not started, and the Dart code
  was not compiled. Run `flutter analyze` and try two accounts on a real device.
- Not built: password reset (the "forgot password" screen is untouched), changing name/password, sharing
  an exam between users, roles.
- The database schema is not in the archive, so the migration reads `users.id`'s type instead of assuming it.
