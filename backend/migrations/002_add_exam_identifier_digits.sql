BEGIN;

ALTER TABLE exams
  ADD COLUMN IF NOT EXISTS roll_digits integer NOT NULL DEFAULT 7,
  ADD COLUMN IF NOT EXISTS registration_digits integer NOT NULL DEFAULT 10;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'exams_roll_digits_range'
  ) THEN
    ALTER TABLE exams ADD CONSTRAINT exams_roll_digits_range
      CHECK (roll_digits BETWEEN 1 AND 14);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'exams_registration_digits_range'
  ) THEN
    ALTER TABLE exams ADD CONSTRAINT exams_registration_digits_range
      CHECK (registration_digits BETWEEN 0 AND 16);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'exams_identifier_digits_fit'
  ) THEN
    ALTER TABLE exams ADD CONSTRAINT exams_identifier_digits_fit
      CHECK (roll_digits + registration_digits <= 26);
  END IF;
END $$;

COMMIT;
