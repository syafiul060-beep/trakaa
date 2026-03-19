const express = require('express');
const router = express.Router();
const { getRedis, geoSearchDrivers } = require('../lib/redis.js');
const { isValidLatLng } = require('../lib/validation.js');

const DRIVER_STATUS_PREFIX = 'driver_status:';
const STATUS_SIAP_KERJA = 'siap_kerja';

/**
 * GET /api/match/drivers – cari driver terdekat dari titik pickup (#9).
 * Query: lat, lng, city (default: default), radius (km, default: 5), limit (default: 20)
 * Response: { drivers: [{ uid, distance, ...driverStatus }] }
 * Filter: hanya driver status siap_kerja, punya route (origin/dest).
 */
router.get('/drivers', async (req, res) => {
  try {
    const redis = getRedis();
    if (!redis) return res.status(503).json({ error: 'Redis not available' });

    const lat = parseFloat(req.query.lat);
    const lng = parseFloat(req.query.lng);
    const city = (req.query.city && String(req.query.city).trim()) || 'default';
    const radius = Math.min(Math.max(parseFloat(req.query.radius) || 5, 0.5), 50);
    const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 20, 1), 50);
    const minCapacity = parseInt(req.query.minCapacity, 10);

    if (Number.isNaN(lat) || Number.isNaN(lng)) {
      return res.status(400).json({ error: 'lat and lng required (query params)' });
    }
    if (!isValidLatLng(lat, lng)) {
      return res.status(400).json({ error: 'Invalid lat or lng' });
    }

    const geoResults = await geoSearchDrivers(city, lng, lat, radius, limit);
    if (geoResults.length === 0) {
      return res.json({ drivers: [] });
    }

    const keys = geoResults.map((r) => DRIVER_STATUS_PREFIX + r.uid);
    const values = await redis.mGet(...keys);
    const drivers = [];
    for (let i = 0; i < geoResults.length; i++) {
      const raw = values[i];
      if (!raw) continue;
      try {
        const status = JSON.parse(raw);
        if (status.status !== STATUS_SIAP_KERJA) continue;
        if (status.routeOriginLat == null || status.routeDestLat == null) continue;
        if (!Number.isNaN(minCapacity) && minCapacity > 0) {
          const maxP = status.maxPassengers;
          const current = status.currentPassengerCount ?? 0;
          if (maxP != null && maxP > 0 && (maxP - current) < minCapacity) continue;
        }
        const { uid, distance } = geoResults[i];
        drivers.push({
          uid,
          distance,
          ...status,
        });
      } catch (_) {}
    }

    res.json({ drivers });
  } catch (err) {
    console.error('GET /match/drivers:', err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
