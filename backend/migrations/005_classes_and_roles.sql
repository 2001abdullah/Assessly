-- Student management: roles, classes, enrolment, attendance, announcements,
-- notifications and richer profiles. Idempotent like every migration here.

BEGIN;

-- --- users: role + profile ----------------------------------------------------
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS role text NOT NULL DEFAULT 'teacher',
  ADD COLUMN IF NOT EXISTS username text,
  ADD COLUMN IF NOT EXISTS phone text,
  ADD COLUMN IF NOT EXISTS institution text,
  ADD COLUMN IF NOT EXISTS bio text,
  ADD COLUMN IF NOT EXISTS avatar bytea,
  ADD COLUMN IF NOT EXISTS avatar_updated_at timestamptz,
  ADD COLUMN IF NOT EXISTS must_change_password boolean NOT NULL DEFAULT false;

-- Students created by a teacher sign in with a username instead of an email.
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS users_username_unique
  ON users (lower(username)) WHERE username IS NOT NULL;

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_valid;
ALTER TABLE users ADD CONSTRAINT users_role_valid
  CHECK (role IN ('teacher', 'student'));

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_login_required;
ALTER TABLE users ADD CONSTRAINT users_login_required
  CHECK (email IS NOT NULL OR username IS NOT NULL);

-- --- classes -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS classes (
  id uuid PRIMARY KEY,
  teacher_id integer NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name varchar(120) NOT NULL,
  subject varchar(120),
  section varchar(60),
  description text,
  join_code varchar(12) NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_classes_teacher_id ON classes (teacher_id);

-- The roster. user_id is null for a student the teacher added without an
-- account; status 'pending' is a join request waiting for approval.
CREATE TABLE IF NOT EXISTS class_students (
  id uuid PRIMARY KEY,
  class_id uuid NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
  user_id integer REFERENCES users(id) ON DELETE SET NULL,
  name varchar(120) NOT NULL,
  roll_number varchar(32) NOT NULL,
  email varchar(255),
  status varchar(12) NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT class_students_status_valid CHECK (status IN ('pending', 'active')),
  CONSTRAINT class_students_roll_unique UNIQUE (class_id, roll_number)
);
CREATE UNIQUE INDEX IF NOT EXISTS class_students_user_unique
  ON class_students (class_id, user_id) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_class_students_user_id ON class_students (user_id);

-- --- exams belong to a class; results are private until published -------------
ALTER TABLE exams
  ADD COLUMN IF NOT EXISTS class_id uuid REFERENCES classes(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS results_published_at timestamptz;
CREATE INDEX IF NOT EXISTS idx_exams_class_id ON exams (class_id);
CREATE INDEX IF NOT EXISTS idx_exam_results_exam_roll ON exam_results (exam_id, roll_number);

-- --- attendance: one session per class per day ---------------------------------
CREATE TABLE IF NOT EXISTS attendance_sessions (
  id uuid PRIMARY KEY,
  class_id uuid NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
  session_date date NOT NULL,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT attendance_sessions_one_per_day UNIQUE (class_id, session_date)
);

CREATE TABLE IF NOT EXISTS attendance_records (
  session_id uuid NOT NULL REFERENCES attendance_sessions(id) ON DELETE CASCADE,
  class_student_id uuid NOT NULL REFERENCES class_students(id) ON DELETE CASCADE,
  status varchar(10) NOT NULL,
  PRIMARY KEY (session_id, class_student_id),
  CONSTRAINT attendance_records_status_valid
    CHECK (status IN ('present', 'absent', 'late', 'excused'))
);
CREATE INDEX IF NOT EXISTS idx_attendance_records_student
  ON attendance_records (class_student_id);

-- --- announcements -----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS announcements (
  id uuid PRIMARY KEY,
  class_id uuid NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
  author_id integer NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title varchar(200) NOT NULL,
  body text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_announcements_class ON announcements (class_id, created_at DESC);

-- --- in-app notifications + push device tokens -----------------------------------
CREATE TABLE IF NOT EXISTS notifications (
  id uuid PRIMARY KEY,
  user_id integer NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type varchar(40) NOT NULL,
  title varchar(200) NOT NULL,
  body text NOT NULL DEFAULT '',
  data jsonb NOT NULL DEFAULT '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS device_tokens (
  token text PRIMARY KEY,
  user_id integer NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform varchar(20) NOT NULL DEFAULT 'android',
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens (user_id);

COMMIT;
