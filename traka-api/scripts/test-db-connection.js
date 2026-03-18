/**
 * Test koneksi PostgreSQL ke Supabase
 * Jalankan: node scripts/test-db-connection.js
 */
require('dotenv').config();
const { Pool } = require('pg');

const url = process.env.DATABASE_URL;
if (!url) {
  console.error('DATABASE_URL tidak ada di .env');
  process.exit(1);
}

// Sembunyikan password di log
const safeUrl = url.replace(/:([^:@]+)@/, ':****@');
console.log('Testing:', safeUrl);
console.log('');

const pool = new Pool({
  connectionString: url,
  ssl: { rejectUnauthorized: false },
  connectionTimeoutMillis: 10000,
});

pool.query('SELECT 1')
  .then(() => {
    console.log('SUCCESS: Koneksi berhasil!');
    process.exit(0);
  })
  .catch((err) => {
    console.error('ERROR:', err.message);
    console.error('Code:', err.code);
    process.exit(1);
  })
  .finally(() => pool.end());
