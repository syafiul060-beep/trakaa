const redis = require('redis');

let client = null;

async function initRedis() {
  const url = process.env.REDIS_URL || 'redis://localhost:6379';
  client = redis.createClient({
    url,
    socket: {
      reconnectStrategy: (retries) => {
        if (retries > 10) return false;
        return Math.min(retries * 100, 3000);
      },
    },
  });
  client.on('error', (err) => console.error('Redis error:', err));
  await client.connect();
  return client;
}

function getRedis() {
  return client;
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
    const [nextCursor, found] = await client.scan(cursor, { MATCH: pattern, COUNT: 100 });
    cursor = parseInt(nextCursor, 10);
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
    const [nextCursor, found] = await client.scan(cursor, { MATCH: pattern, COUNT: 100 });
    cursor = parseInt(nextCursor, 10);
    for (const k of found) {
      keys.push(k);
      if (keys.length >= limitNum) break;
    }
  } while (cursor !== 0 && keys.length < limitNum);

  return { keys, nextCursor: cursor };
}

module.exports = { initRedis, getRedis, scanKeys, scanKeysPaginated };
