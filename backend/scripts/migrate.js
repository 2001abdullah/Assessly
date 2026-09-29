// Brings the database schema up to date. Runs on every `npm start`.
//
// 1. On an empty database, applies migrations/000_initial_schema.sql
//    (a pg_dump of the original schema).
// 2. Applies every other migrations/NNN_*.sql file in name order.
//
// There is no "applied migrations" table: every numbered migration must be
// idempotent (CREATE ... IF NOT EXISTS, ADD COLUMN IF NOT EXISTS, guarded
// constraints) because it runs again on each start. Keep new migrations that
// way, or add migration tracking before writing one that is not.

require('dotenv').config();

const fs = require('fs');
const path = require('path');
const pool = require('../config/db');

const MIGRATIONS_DIR = path.join(__dirname, '..', 'migrations');
const INITIAL_SCHEMA = '000_initial_schema.sql';

function readMigration(name) {
  return fs.readFileSync(path.join(MIGRATIONS_DIR, name), 'utf8');
}

async function migrate() {
  const client = await pool.connect();

  try {
    const { rows } = await client.query(
      "SELECT to_regclass('public.users') AS users_table",
    );

    if (!rows[0].users_table) {
      await client.query(readMigration(INITIAL_SCHEMA));
      console.log('Applied initial database schema');
    }

    // pg_dump clears the session search path while restoring a schema.
    // Reset it before running migrations that use unqualified table names.
    await client.query('SET search_path TO public');

    const migrations = fs.readdirSync(MIGRATIONS_DIR)
      .filter((name) => /^\d{3}_.+\.sql$/.test(name) && name !== INITIAL_SCHEMA)
      .sort();

    for (const name of migrations) {
      await client.query(readMigration(name));
    }
    console.log(`Database migrations are up to date (${migrations.length} checked)`);
  } finally {
    client.release();
  }
}

migrate()
  .catch((error) => {
    console.error('Database migration failed:', error);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
