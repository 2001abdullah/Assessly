require('dotenv').config();

const fs = require('fs');
const path = require('path');
const pool = require('../config/db');

async function migrate() {
  const { rows } = await pool.query(
    "SELECT to_regclass('public.users') AS users_table",
  );

  if (!rows[0].users_table) {
    const initialSchema = fs.readFileSync(
      path.join(__dirname, '..', 'migrations', '000_initial_schema.sql'),
      'utf8',
    );
    await pool.query(initialSchema);
    console.log('Applied initial database schema');
  }

  const ownershipMigration = fs.readFileSync(
    path.join(__dirname, '..', 'migrations', '001_add_exam_owner.sql'),
    'utf8',
  );
  await pool.query(ownershipMigration);
  console.log('Database migrations are up to date');
}

migrate()
  .catch((error) => {
    console.error('Database migration failed:', error);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
