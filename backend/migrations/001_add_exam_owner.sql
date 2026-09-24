-- Ties every exam to the user who created it.
-- Run once against your Assessly database, e.g.:
--   psql "$DATABASE_URL" -f backend/migrations/001_add_exam_owner.sql
--
-- Answer keys, scoring rules, scans and results already reference an exam, so
-- they become per-user automatically through exams.user_id.

BEGIN;

-- Use the same type as users.id (integer or uuid) so the foreign key always fits.
DO $$
DECLARE
  id_type text;
BEGIN
  SELECT format_type(atttypid, atttypmod)
    INTO id_type
    FROM pg_attribute
   WHERE attrelid = 'users'::regclass
     AND attname = 'id'
     AND NOT attisdropped;

  IF id_type IS NULL THEN
    RAISE EXCEPTION 'users.id not found - is the users table in this schema?';
  END IF;

  EXECUTE format(
    'ALTER TABLE exams ADD COLUMN IF NOT EXISTS user_id %s REFERENCES users(id)',
    id_type
  );
END $$;

CREATE INDEX IF NOT EXISTS idx_exams_user_id ON exams (user_id);

-- ---------------------------------------------------------------------------
-- EXISTING EXAMS: they have no owner yet, and the API only shows a user their
-- own exams, so until you assign them nobody will see them.
-- Edit the email below to the account that should own all current exams, then
-- uncomment:
--
-- UPDATE exams
--    SET user_id = (SELECT id FROM users WHERE email = 'you@example.com')
--  WHERE user_id IS NULL;
-- ---------------------------------------------------------------------------

COMMIT;

-- Optional, once every exam has an owner:
--   ALTER TABLE exams ALTER COLUMN user_id SET NOT NULL;
