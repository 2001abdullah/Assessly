# Assessly API reference

Base URL: the deployed API (for example `https://assessly-api.onrender.com`),
or `http://localhost:5000` in development.

- Request and response bodies are JSON unless noted.
- Errors always look like `{ "message": "human readable text" }`.
- 🔒 marks endpoints that need `Authorization: Bearer <token>`. A missing,
  invalid or expired token gives **401**.
- Ids of exams, scans and results are UUIDs. A resource that does not exist
  **or belongs to another user** gives **404**.

## Service

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/health` | `200 {status:"ok", database:"connected", version}` or `503` when the database is unreachable |
| GET | `/metrics` | Prometheus text. Requires `Bearer <METRICS_TOKEN>`; returns 404 otherwise |

## Auth: `/api/auth`

Public. Limited to 20 requests per IP per 15 minutes.

| Method | Path | Body | Success |
| --- | --- | --- | --- |
| POST | `/register` | `{name, email, password}` (password ≥ 8 chars) | `201 {user}`. `409` if the email is taken |
| POST | `/login` | `{email, password}` | `200 {token, user:{id,name,email}}`. `401` on a bad email or password |
| POST | `/google` | `{id_token}` (Google ID token) | same as login. `409` if the email is linked to a different Google account; `503` if not configured |
| POST | `/forgot-password` | `{email}` | always `202` |
| POST | `/reset-password` | `{email, code, password}` | `200`. `400` if the code is invalid or expired |
| GET 🔒 | `/me` | | `200 {user:{id,name,email,created_at}}` |
| DELETE 🔒 | `/me` | | `200`. Deletes the account and all of its data |

## Exams: `/api/exam` 🔒

| Method | Path | Body / result |
| --- | --- | --- |
| POST | `/` | `{title, subject?, total_questions, roll_digits=7, registration_digits=10}` → `201 {exam}`. Roll digits 1–14, registration digits 0–16, at most 26 combined |
| GET | `/` | `{exams:[...]}`, newest first |
| GET | `/:id` | `{exam}` |
| PUT | `/:id` | same body as POST → `{exam}` |
| DELETE | `/:id` | deletes the exam with its key, rules, scans and results |
| GET | `/:id/summary` | `{exam, summary:{students, passed, failed, highest_marks, lowest_marks, average_marks, average_percentage, pass_rate}}` |

## Answer key: `/api/answer-key` 🔒

| Method | Path | Body / result |
| --- | --- | --- |
| POST | `/batch` | `{exam_id, answers:[{question_number, correct_answer}]}`. **Replaces** the whole key |
| POST | `/` | `{exam_id, question_number, correct_answer}`. Adds one answer. `409` if that question is already keyed (use `/batch` to change it) |
| GET | `/exam/:exam_id` | `{exam_id, count, answer_keys:[...]}` |

## Scoring rules: `/api/scoring-rules` 🔒

| Method | Path | Body / result |
| --- | --- | --- |
| PUT | `/:exam_id` | `{marks_correct=1 (≥0), marks_wrong=-0.5 (≤0), marks_blank=0 (must be 0), pass_percentage=40 (0–100), ambiguous_as='review'\|'wrong'\|'blank', clamp_negative_total=true}` → `{scoring_rules}` |
| GET | `/:exam_id` | `{scoring_rules}`. `404` until rules are saved |

## OMR: `/api/omr` 🔒

Limited to 60 requests per IP per 15 minutes. Images can be up to 15 MB, in
any format OpenCV reads (JPEG, PNG...).

| Method | Path | Body / result |
| --- | --- | --- |
| POST | `/scan` | multipart: `image`, `exam_id`, optional `template` (JSON; defaults to the exam's generated layout). Returns the engine's scan JSON plus `result_id` (the **scan** id) and `exam_id`. Check `ok`: `false` means the sheet could not be read, and `errors` says why |
| POST | `/batch` | multipart: `images` (up to 20), `exam_id`. Scans **and** scores each image and returns `{count, results:[{source, ok, result_id?, scan_id?, marks?, percentage?, error?}]}` |
| GET | `/exam/:exam_id/sheet` | `application/pdf`: the printable answer sheet for this exam |

Main fields of the scan JSON:

```jsonc
{
  "ok": true,
  "needs_review": false,
  "roll":         { "value": "1234567", "digits": ["1","2","3","4","5","6","7"], ... },
  "registration": { "value": "0000000042", ... },
  "answers": [ { "index": 1, "value": "A", "status": "marked", "confidence": 0.97, ... } ],
  "quality": { "grade": "good", "score": 0.9, "sharpness": ..., "contrast": ..., "skew_deg": ... },
  "warnings": [], "errors": [],
  "result_id": "<scan uuid>", "exam_id": "<exam uuid>"
}
```

An answer's `status` is one of `marked`, `blank`, `faint`, `multi` or
`unreadable`. The last three count as ambiguous.

## Scoring: `/api/scoring` 🔒

| Method | Path | Body / result |
| --- | --- | --- |
| POST | `/score` | `{exam_id, scan_id, name?}` → `{result_id, result:{roll, registration, correct, wrong, blank, ambiguous, marks, max_marks, percentage, grade, passed, outcomes}}`. Scoring the same scan again returns the saved result. `422` if the exam has no answer key or scoring rules yet |

## Results: `/api/results` 🔒

| Method | Path | Result |
| --- | --- | --- |
| GET | `/:id` | `{result}`: the saved summary row |
| GET | `/:id/details` | `{result:{exam, student, summary, scoring_rules, questions:[{question_number, given_answer, correct_answer, status, marks, confidence}]}}`. Question `status` is one of `correct`, `wrong`, `blank`, `ambiguous` or `not_keyed` |
| GET | `/exam/:exam_id` | `{exam, count, results:[...]}`, highest percentage first |
| GET | `/exam/:exam_id/export.csv` | `text/csv` download, one row per result |

## Roles

Every account is a `teacher` (the default) or a `student`. Login, register
and Google sign-in accept a `role`, the portal the user chose. Signing in to
the wrong portal returns **403** with a message naming the right one. The JWT
carries the role:

- `/api/omr`, `/api/exam`, `/api/answer-key`, `/api/scoring-rules`,
  `/api/scoring`, `/api/results` and `/api/classes` are teacher-only.
- `/api/student` is student-only.
- `/api/profile` and `/api/notifications` accept either role.

Students a teacher adds with a generated login sign in with a **username**
(e.g. `ab12cd-15`) in the `email` field, and must change the temporary
password (`user.must_change_password`).

## Classes: `/api/classes` 🔒 teacher

| Method | Path | Body / result |
| --- | --- | --- |
| GET | `/` | `{classes}` with `student_count`, `pending_count`, `exam_count`, `last_attendance` |
| POST | `/` | `{name, subject?, section?, description?}` → `201 {class}` with a 6-character `join_code` |
| GET | `/dashboard?date=YYYY-MM-DD` | home-screen numbers: `{summary:{classes, students, pending_requests, exams, attendance_taken_today, unpublished_exams}, classes, recent_exams}` |
| GET / PUT / DELETE | `/:class_id` | read, update or delete. Deleting keeps the exams, with no class |
| POST | `/:class_id/join-code` | issue a new code (the old one stops working) |
| GET | `/:class_id/students` | roster, pending requests first, with `attendance_rate` |
| POST | `/:class_id/students` | `{name, roll_number, email?, create_login?}` → `{student, credentials?}`. The credentials (username + temporary password) are returned **only here** |
| PATCH | `/:class_id/students/:id` | `{status:'active'}` approves a request; `{name?, roll_number?}` edits |
| DELETE | `/:class_id/students/:id` | remove, or decline a request |
| POST | `/:class_id/students/:id/reset-password` | new temporary password (teacher-created logins only) |
| GET | `/:class_id/students/:id/report` | the student's results, rank and attendance |
| GET | `/:class_id/exams` | exams of the class |
| GET | `/:class_id/attendance` | sessions with present / absent / late / excused counts |
| GET / PUT | `/:class_id/attendance/:date` | read, or save `{records:[{student_id, status}], note?}`. Newly absent students are notified |
| GET / POST | `/:class_id/announcements` | list, or post `{title, body}` (notifies students) |
| DELETE | `/:class_id/announcements/:id` | |
| GET | `/:class_id/analytics` | `{summary, exams, attendance, grade_distribution, leaderboard, at_risk, students}` |
| GET | `/:class_id/reports/results.csv`, `/attendance.csv` | CSV downloads |

Results reach students through the class: a result belongs to the roster
entry whose roll number matches, ignoring leading zeros. Only the latest
result per roll per exam counts.

## Publishing: `/api/exam/:id/publish` 🔒 teacher

`POST /api/exam/:id/publish` makes the exam's results visible to its class
and notifies the students. `POST /api/exam/:id/unpublish` hides them again.
`POST /api/exam` and `PUT /api/exam/:id` accept `class_id`.

## Student: `/api/student` 🔒 student

| Method | Path | Result |
| --- | --- | --- |
| GET | `/overview` | `{classes, summary:{exams_taken, average, best, passed, attendance_rate, attendance}, trend, grade_distribution, class_ranks, recent_results}` |
| GET | `/classes` | my classes with `status` (`pending` / `active`) |
| POST | `/classes/join` | `{code, roll_number}` → join request; the teacher is notified |
| DELETE | `/classes/:class_id` | leave |
| GET | `/results` | my **published** results with `rank`, `out_of`, `class_average`, `class_highest` |
| GET | `/results/:result_id` | per-question breakdown (own, published results only) |
| GET | `/attendance` | per class: counts, `rate`, day-by-day `records` |
| GET | `/announcements` | from my active classes |

A student never sees another student's name or marks.

## Profile: `/api/profile` 🔒 any role

| Method | Path | Body / result |
| --- | --- | --- |
| GET / PUT | `/` | `{user}` / update `{name, phone?, institution?, bio?}` |
| PUT | `/password` | `{current_password, new_password}` |
| PUT / DELETE | `/avatar` | multipart `avatar` (JPEG or PNG, up to 1 MB) / remove |
| GET | `/avatar/:user_id` | the image. Only for yourself, your students, or your teachers |

## Notifications: `/api/notifications` 🔒 any role

`GET /` → `{notifications, unread}`; `POST /:id/read`; `POST /read-all`;
`POST /devices {token, platform}` / `DELETE /devices {token}` register or
forget a push token. Types: `results_published`, `announcement`,
`attendance_absent`, `join_request`, `enrolment_approved`.

## Typical call sequence

```text
POST /api/auth/login                      -> token
POST /api/exam                            -> exam.id
GET  /api/omr/exam/{exam.id}/sheet        -> print it
POST /api/answer-key/batch
PUT  /api/scoring-rules/{exam.id}
POST /api/omr/scan        (per sheet)     -> result_id (scan id)
POST /api/scoring/score   {exam_id, scan_id: result_id} -> result_id (result)
GET  /api/results/{result_id}/details
```
