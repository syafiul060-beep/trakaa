const { Pool } = require('pg');

let pool = null;

async function initPg() {
  let url = process.env.DATABASE_URL;
  if (!url) {
    console.warn('DATABASE_URL not set - PostgreSQL disabled');
    return null;
  }
  // Hapus sslmode dari URL agar ssl config di bawah yang dipakai (terima self-signed)
  try {
    const u = new URL(url);
    u.searchParams.delete('sslmode');
    u.searchParams.delete('ssl');
    url = u.toString();
  } catch (_) {}
  pool = new Pool({
    connectionString: url,
    max: parseInt(process.env.PG_POOL_MAX, 10) || 50,
    min: 2,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
    // Supabase: terima self-signed certificate
    ssl: { rejectUnauthorized: false },
  });
  return pool;
}

function getPg() {
  return pool;
}

module.exports = { initPg, getPg };
