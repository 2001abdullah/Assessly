require('dotenv').config();

const fs = require('fs');
const path = require('path');
const pool = require('../config/db');

async function migrate() {
  const client = await pool.connect();

  try {
    const { rows } = await client.query(
      "SELECT to_regclass('public.users') AS users_table",
    );

    if (!rows[0].users_table) {
      const initialSchema = fs.readFileSync(
        path.join(__dirname, '..', 'migrations', '000_initial_schema.sql'),
        'utf8',
      );
      await client.query(initialSchema);
      console.log('Applied initial database schema');
    }

    // pg_dump clears the session search path while restoring a schema.
    // Reset it before running migrations that use unqualified table names.
    await client.query('SET search_path TO public');

    const ownershipMigration = fs.readFileSync(
      path.join(__dirname, '..', 'migrations', '001_add_exam_owner.sql'),
      'utf8',
    );
    await client.query(ownershipMigration);
    console.log('Database migrations are up to date');
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
