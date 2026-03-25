const express = require('express');
const rateLimit = require('express-rate-limit');
const { RedisStore } = require('rate-limit-redis');
const router = express.Router();
const { getRedis, scanKeysPaginated, geoAddDriver, geoRemoveDriver } = require('../lib/redis.js');
const { verifyToken } = require('../lib/auth.js');
const { sanitizeNumber, isValidLatLng } = require('../lib/validation.js');

const KEY_PREFIX = 'driver_status:';
const TTL_SECONDS = 600; // 10 menit

// Harus sebelum /:uid/status agar tidak tertangkap sebagai uid
// Pagination: ?limit=50&cursor=0 (hindari full SCAN saat banyak driver)
router.get('/status', async (req, res) => {
  try {
    const redis = getRedis();
    if (!redis) return res.status(503).json({ error: 'Redis not available' });

    const limit = Math.min(parseInt(req.query.limit, 10) || 50, 100);
    const cursor = parseInt(req.query.cursor, 10) || 0;

    const { keys, nextCursor } = await scanKeysPaginated(KEY_PREFIX + '*', cursor, limit);

    const drivers = [];
    if (keys.length > 0) {
      // node-redis v4: mGet(mkeys: string[]) — jangan spread variadic
      const values = await redis.mGet(keys);
      for (let i = 0; i < values.length; i++) {
        const raw = values[i];
        if (raw) {
          try {
            drivers.push(JSON.parse(raw));
          } catch (_) {}
        }
      }
    }

    res.json({ drivers, nextCursor: nextCursor === 0 ? null : nextCursor });
  } catch (err) {
    console.error('GET /driver/status:', err);
    res.status(500).json({ error: err.message });
  }
});

router.post('/location', verifyToken, (req, res, next) => driverLocationPerUidLimiter()(req, res, next), async (req, res) => {
  try {
    const redis = getRedis();
    if (!redis) return res.status(503).json({ error: 'Redis not available' });

    const uid = req.uid;
    const { latitude, longitude, status, city, maxPassengers, routeOriginLat, routeOriginLng, routeDestLat, routeDestLng, routeOriginText, routeDestText, routeJourneyNumber, routeStartedAt, estimatedDurationSeconds, currentPassengerCount, routeFromJadwal, routeSelectedIndex, scheduleId } = req.body;

    if (latitude == null || longitude == null) {
      return res.status(400).json({ error: 'latitude and longitude required' });
    }
    if (!isValidLatLng(latitude, longitude)) {
      return res.status(400).json({ error: 'Invalid latitude or longitude' });
    }

    const citySlug = (city && String(city).trim()) || 'default';
    const data = {
      uid,
      city: citySlug,
      latitude: parseFloat(latitude),
      longitude: parseFloat(longitude),
      lastUpdated: new Date().toISOString(),
      status: status || 'siap_kerja',
      ...(routeOriginLat != null && { routeOriginLat: parseFloat(routeOriginLat) }),
      ...(routeOriginLng != null && { routeOriginLng: parseFloat(routeOriginLng) }),
      ...(routeDestLat != null && { routeDestLat: parseFloat(routeDestLat) }),
      ...(routeDestLng != null && { routeDestLng: parseFloat(routeDestLng) }),
      ...(routeOriginText != null && { routeOriginText }),
      ...(routeDestText != null && { routeDestText }),
      ...(routeJourneyNumber != null && { routeJourneyNumber }),
      ...(routeStartedAt != null && { routeStartedAt }),
      ...(estimatedDurationSeconds != null && { estimatedDurationSeconds }),
      ...(currentPassengerCount != null && { currentPassengerCount }),
      ...(maxPassengers != null && maxPassengers > 0 && { maxPassengers: Math.floor(maxPassengers) }),
      ...(routeFromJadwal != null && { routeFromJadwal }),
      ...(routeSelectedIndex != null && { routeSelectedIndex }),
      ...(scheduleId != null && { scheduleId }),
    };

    const key = KEY_PREFIX + uid;
    await redis.setEx(key, TTL_SECONDS, JSON.stringify(data));
    try {
      await geoAddDriver(citySlug, uid, parseFloat(longitude), parseFloat(latitude));
    } catch (geoErr) {
      console.warn('[driver/location] GEOADD failed:', geoErr.message);
    }
    if (process.env.REDIS_PUBLISH_DRIVER_LOCATION === '1') {
      try {
        await redis.publish(
          'driver:location',
          JSON.stringify({
            uid,
            city: citySlug,
            lat: data.latitude,
            lng: data.longitude,
            ts: Date.now(),
          }),
        );
      } catch (pubErr) {
        console.warn('[driver/location] publish:', pubErr.message);
      }
    }
    res.json({ ok: true });
  } catch (err) {
    console.error('POST /driver/location:', err);
    res.status(500).json({ error: err.message });
  }
});

// PATCH /api/driver/status – partial update (Tahap 4.1: currentPassengerCount saja).
router.patch('/status', verifyToken, async (req, res) => {
  try {
    const redis = getRedis();
    if (!redis) return res.status(503).json({ error: 'Redis not available' });

    const { currentPassengerCount } = req.body;
    if (currentPassengerCount == null || typeof currentPassengerCount !== 'number') {
      return res.status(400).json({ error: 'currentPassengerCount required (number)' });
    }

    const key = KEY_PREFIX + req.uid;
    const raw = await redis.get(key);
    if (!raw) {
      return res.status(404).json({ error: 'Driver status not found' });
    }
    const data = JSON.parse(raw);
    data.currentPassengerCount = Math.max(0, Math.floor(currentPassengerCount));
    data.lastUpdated = new Date().toISOString();
    await redis.setEx(key, TTL_SECONDS, JSON.stringify(data));
    res.json({ ok: true });
  } catch (err) {
    console.error('PATCH /driver/status:', err);
    res.status(500).json({ error: err.message });
  }
});

router.get('/:uid/status', async (req, res) => {
  try {
    const redis = getRedis();
    if (!redis) return res.status(503).json({ error: 'Redis not available' });

    const uid = req.params.uid;
    const key = KEY_PREFIX + uid;
    const raw = await redis.get(key);
    if (!raw) {
      return res.status(404).json({ error: 'Driver not found' });
    }
    const data = JSON.parse(raw);
    res.json(data);
  } catch (err) {
    console.error('GET /driver/:uid/status:', err);
    res.status(500).json({ error: err.message });
  }
});

router.delete('/status', verifyToken, async (req, res) => {
  try {
    const redis = getRedis();
    if (!redis) return res.status(503).json({ error: 'Redis not available' });

    const key = KEY_PREFIX + req.uid;
    let city = 'default';
    try {
      const raw = await redis.get(key);
      if (raw) {
        const data = JSON.parse(raw);
        if (data.city) city = data.city;
      }
    } catch (_) {}
    try {
      await geoRemoveDriver(city, req.uid);
    } catch (geoErr) {
      console.warn('[driver/status] ZREM failed:', geoErr.message);
    }
    await redis.del(key);
    res.json({ ok: true });
  } catch (err) {
    console.error('DELETE /driver/status:', err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
