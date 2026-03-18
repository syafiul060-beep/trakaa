const { Pool } = require('pg');

let pool = null;

async function initPg() {
  const url = process.env.DATABASE_URL;
  if (!url) {
    console.warn('DATABASE_URL not set - PostgreSQL disabled');
    return null;
  }
  pool = new Pool({
    connectionString: url,
    max: parseInt(process.env.PG_POOL_MAX, 10) || 50,
    min: 2,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
    // Supabase SSL: terima self-signed certificate
    ssl: { rejectUnauthorized: false },
  });
  return pool;
}

function getPg() {
  return pool;
}

module.exports = { initPg, getPg };
