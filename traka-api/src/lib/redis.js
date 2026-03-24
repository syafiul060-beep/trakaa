const redis = require('redis');

let client = null;

async function initRedis() {
  const url = process.env.REDIS_URL || 'redis://localhost:6379';
  if (!url || url === 'redis://localhost:6379') {
    console.warn('[Redis] REDIS_URL not set - driver_status & rate limit will use memory (tidak persist)');
    return null;
  }
  try {
    client = redis.createClient({
      url,
      socket: {
        reconnectStrategy: (retries) => {
          if (retries > 10) return false;
          return Math.min(retries * 100, 3000);
        },
      },
    });
    client.on('error', (err) => console.error('[Redis]', err.message));
    await client.connect();
    console.log('[Redis] Connected');
    return client;
  } catch (err) {
    console.error('[Redis] Connection failed:', err.message);
    console.error('[Redis] Cek REDIS_URL (Upstash: rediss://default:TOKEN@xxx.upstash.io:6379)');
    client = null;
    return null;
  }
}

function getRedis() {
  return client;
}

/** node-redis v4+: scan() mengembalikan { cursor, keys }, bukan [cursor, keys]. */
function scanReplyToCursorKeys(reply) {
  if (reply && typeof reply === 'object' && 'keys' in reply) {
    const c = reply.cursor;
    const cursorNum = typeof c === 'string' ? parseInt(c, 10) : Number(c);
    const found = Array.isArray(reply.keys) ? reply.keys : [];
    return { cursor: Number.isFinite(cursorNum) ? cursorNum : 0, found };
  }
  if (Array.isArray(reply) && reply.length >= 2) {
    const cursorNum = typeof reply[0] === 'string' ? parseInt(reply[0], 10) : Number(reply[0]);
    const found = Array.isArray(reply[1]) ? reply[1] : [];
    return { cursor: Number.isFinite(cursorNum) ? cursorNum : 0, found };
  }
  return { cursor: 0, found: [] };
}

/**
 * Scan keys dengan pattern (ganti KEYS * yang tidak aman di production).
 * @param {string} pattern - e.g. 'driver_status:*'
 * @returns {Promise<string[]>}
 */
async function scanKeys(pattern) {
  if (!client) return [];
  const keys = [];
  let cursor = 0;
  do {
    const reply = await client.scan(cursor, { MATCH: pattern, COUNT: 100 });
    const { cursor: nextCursor, found } = scanReplyToCursorKeys(reply);
    cursor = nextCursor;
    keys.push(...found);
  } while (cursor !== 0);
  return keys;
}

/**
 * Scan keys dengan pagination (untuk GET /driver/status - hindari full scan).
 * @param {string} pattern - e.g. 'driver_status:*'
 * @param {number} startCursor - cursor dari request sebelumnya (0 = mulai)
 * @param {number} limit - max keys yang dikembalikan
 * @returns {Promise<{ keys: string[], nextCursor: number }>}
 */
async function scanKeysPaginated(pattern, startCursor = 0, limit = 50) {
  if (!client) return { keys: [], nextCursor: 0 };
  const keys = [];
  const limitNum = Math.min(Math.max(parseInt(limit, 10) || 50, 1), 100);
  let cursor = parseInt(startCursor, 10) || 0;

  do {
    const reply = await client.scan(cursor, { MATCH: pattern, COUNT: 100 });
    const { cursor: nextCursor, found } = scanReplyToCursorKeys(reply);
    cursor = nextCursor;
    for (const k of found) {
      keys.push(k);
      if (keys.length >= limitNum) break;
    }
  } while (cursor !== 0 && keys.length < limitNum);

  return { keys, nextCursor: cursor };
}

/**
 * GEO helpers (#9) – driver matching by proximity.
 * Key: drivers:geo:{city}
 */
async function geoAddDriver(city, uid, lng, lat) {
  if (!client) return;
  const key = `drivers:geo:${city}`;
  await client.sendCommand(['GEOADD', key, String(lng), String(lat), `driver_${uid}`]);
}

async function geoRemoveDriver(city, uid) {
  if (!client) return;
  const key = `drivers:geo:${city}`;
  await client.sendCommand(['ZREM', key, `driver_${uid}`]);
}

/**
 * Cari driver terdekat dari titik (lat, lng).
 * @returns {Promise<Array<{uid: string, distance: number}>>}
 */
async function geoSearchDrivers(city, lng, lat, radiusKm = 5, limit = 20) {
  if (!client) return [];
  const key = `drivers:geo:${city}`;
  const raw = await client.sendCommand([
    'GEORADIUS', key, String(lng), String(lat), String(radiusKm), 'km',
    'WITHDIST', 'ASC', 'COUNT', String(limit),
  ]);
  if (!Array.isArray(raw)) return [];
  const results = [];
  for (let i = 0; i < raw.length; i++) {
    const item = raw[i];
    if (Array.isArray(item) && item.length >= 2) {
      results.push({
        uid: String(item[0]).replace(/^driver_/, ''),
        distance: parseFloat(item[1]) || 0,
      });
    }
  }
  return results;
}

module.exports = {
  initRedis,
  getRedis,
  scanKeys,
  scanKeysPaginated,
  geoAddDriver,
  geoRemoveDriver,
  geoSearchDrivers,
};
