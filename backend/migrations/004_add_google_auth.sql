BEGIN;

ALTER TABLE users
  ALTER COLUMN password_hash DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS google_subject text;

CREATE UNIQUE INDEX IF NOT EXISTS users_google_subject_unique
  ON users (google_subject)
  WHERE google_subject IS NOT NULL;

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_auth_method_required;
ALTER TABLE users ADD CONSTRAINT users_auth_method_required
  CHECK (password_hash IS NOT NULL OR google_subject IS NOT NULL);

COMMIT;
