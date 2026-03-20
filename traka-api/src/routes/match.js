const express = require('express');
const router = express.Router();
const { getRedis, geoSearchDrivers } = require('../lib/redis.js');
const { isValidLatLng } = require('../lib/validation.js');

const DRIVER_STATUS_PREFIX = 'driver_status:';
const STATUS_SIAP_KERJA = 'siap_kerja';

function bearingDeg(lat1, lng1, lat2, lng2) {
  const toRad = Math.PI / 180;
  const φ1 = lat1 * toRad;
  const φ2 = lat2 * toRad;
  const Δλ = (lng2 - lng1) * toRad;
  const y = Math.sin(Δλ) * Math.cos(φ2);
  const x =
    Math.cos(φ1) * Math.sin(φ2) -
    Math.sin(φ1) * Math.cos(φ2) * Math.cos(Δλ);
  return ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360;
}

function angleDiffDeg(a, b) {
  let d = Math.abs(a - b) % 360;
  if (d > 180) d = 360 - d;
  return d;
}

/** Skor komposit: jarak + arah ke tujuan penumpang vs ujung rute driver + kapasitas + fresh lastUpdated */
function matchScoreForDriver(status, distanceKm, destLat, destLng) {
  const distKm = (distanceKm || 0) + 0.0001;
  const distScore = 1 / distKm;
  const maxP = status.maxPassengers;
  const cur = status.currentPassengerCount ?? 0;
  const capScore =
    maxP != null && maxP > 0 ? Math.max(0, (maxP - cur) / maxP) : 0.5;
  let lastMs = 60000;
  if (status.lastUpdated) {
    const t = new Date(status.lastUpdated).getTime();
    if (!Number.isNaN(t)) lastMs = Date.now() - t;
  }
  const recencyScore = Math.max(0, 1 - Math.min(lastMs / 30000, 1));
  let directionScore = 0.55;
  const dLat = status.latitude;
  const dLng = status.longitude;
  if (
    destLat != null &&
    destLng != null &&
    status.routeDestLat != null &&
    status.routeDestLng != null &&
    dLat != null &&
    dLng != null
  ) {
    const toRouteEnd = bearingDeg(
      dLat,
      dLng,
      status.routeDestLat,
      status.routeDestLng,
    );
    const toPassengerDest = bearingDeg(dLat, dLng, destLat, destLng);
    const diff = angleDiffDeg(toRouteEnd, toPassengerDest);
    directionScore =
      diff < 35 ? 1 : diff < 75 ? 0.7 : Math.max(0.15, 1 - diff / 180);
  }
  return (
    distScore * 0.4 +
    directionScore * 0.28 +
    capScore * 0.17 +
    recencyScore * 0.15
  );
}

/**
 * GET /api/match/drivers – cari driver terdekat dari titik pickup (#9).
 * Query: lat, lng, destLat?, destLng?, city (default: default), radius (km, default: 5), limit (default: 20)
 * Jika destLat & destLng valid: urutkan juga dengan skor arah/kapasitas (matchScore).
 * Response: { drivers: [{ uid, distance, matchScore?, ...driverStatus }] }
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
    const destLatRaw = req.query.destLat != null ? parseFloat(req.query.destLat) : NaN;
    const destLngRaw = req.query.destLng != null ? parseFloat(req.query.destLng) : NaN;
    const useDestScore =
      !Number.isNaN(destLatRaw) &&
      !Number.isNaN(destLngRaw) &&
      isValidLatLng(destLatRaw, destLngRaw);

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

    if (useDestScore && drivers.length > 1) {
      const destLat = destLatRaw;
      const destLng = destLngRaw;
      for (const d of drivers) {
        d.matchScore = matchScoreForDriver(d, d.distance, destLat, destLng);
      }
      drivers.sort((a, b) => (b.matchScore || 0) - (a.matchScore || 0));
    }

    res.json({ drivers });
  } catch (err) {
    console.error('GET /match/drivers:', err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
