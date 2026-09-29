const assert = require('assert');
const pool = require('../config/db');

async function main() {
  const tables = await pool.query(
    `SELECT tablename FROM pg_tables
      WHERE schemaname = 'public' AND tablename = ANY($1::text[])`,
    [[
      'users', 'exams', 'answer_keys', 'exam_scoring_rules',
      'omr_scans', 'omr_answers', 'exam_results', 'password_reset_tokens',
    ]],
  );
  assert.strictEqual(tables.rows.length, 8, 'all production tables must exist');

  const cascade = await pool.query(
    `SELECT confdeltype FROM pg_constraint
      WHERE conname = 'password_reset_tokens_user_id_fkey'`,
  );
  assert.strictEqual(cascade.rows[0]?.confdeltype, 'c', 'reset tokens must cascade on user deletion');

  const googleColumn = await pool.query(
    `SELECT is_nullable FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'users'
        AND column_name = 'google_subject'`,
  );
  assert.strictEqual(googleColumn.rows[0]?.is_nullable, 'YES');

  console.log('Database schema checks passed');
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
