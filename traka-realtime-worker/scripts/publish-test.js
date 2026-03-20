/**
 * Uji manual: PUBLISH satu event ke driver:location (sama bentuknya dengan traka-api).
 * Usage: node scripts/publish-test.js
 * Pastikan .env berisi REDIS_URL (atau export REDIS_URL).
 */
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const Redis = require('ioredis');

const url = process.env.REDIS_URL;
if (!url) {
  console.error('Set REDIS_URL in .env');
  process.exit(1);
}

const payload = {
  uid: 'test-uid',
  city: 'default',
  lat: -3.32,
  lng: 114.59,
  ts: Date.now(),
};

const r = new Redis(url, { maxRetriesPerRequest: null });
r.publish('driver:location', JSON.stringify(payload))
  .then((n) => {
    console.log('PUBLISH ok, subscribers received:', n);
    return r.quit();
  })
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
