// Shared PostgreSQL connection pool.
//
// Production (Render) sets DATABASE_URL; local development uses the DB_*
// variables. TLS is on in production. Certificate verification is off because
// Render's managed database uses a certificate Node does not trust by default;
// supply the provider's CA here if you move to a network you do not control.

const { Pool, types } = require('pg');

// Return DATE columns (attendance days) as 'YYYY-MM-DD' strings. The default
// converts them to a JS Date at local midnight, which shifts the day in any
// timezone east or west of UTC.
const DATE_OID = 1082;
types.setTypeParser(DATE_OID, (value) => value);

const pool = new Pool({
  connectionString: process.env.DATABASE_URL || undefined,
  user: process.env.DB_USER,
  host: process.env.DB_HOST,
  database: process.env.DB_NAME,
  password: process.env.DB_PASSWORD,
  port: Number(process.env.DB_PORT || 5432),
  ssl: process.env.NODE_ENV === 'production'
    ? { rejectUnauthorized: false }
    : false,
  connectionTimeoutMillis: 10_000,
  idleTimeoutMillis: 30_000,
  keepAlive: true,
  keepAliveInitialDelayMillis: 10_000,
});

module.exports = pool;