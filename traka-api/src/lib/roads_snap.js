/**
 * Google Roads API — snap titik GPS ke geometri jalan (map-matching kasar).
 * Membantu ikon driver di peta penumpang tidak «melayang» di jalur paralel/samping jalan.
 *
 * Dikendalikan env: ROADS_SNAP_ENABLED=1, kunci API, throttle per UID (hemat kuota).
 * @see https://developers.google.com/maps/documentation/roads/snap
 */

const ROADS_SNAP_URL = 'https://roads.googleapis.com/v1/snapToRoads';

function distanceMeters(lat1, lon1, lat2, lon2) {
  const R = 6371000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/**
 * @param {number} lat
 * @param {number} lng
 * @param {string} apiKey
 * @returns {Promise<{ lat: number, lng: number } | null>}
 */
async function snapToRoadOnce(lat, lng, apiKey) {
  const path = `${lat},${lng}`;
  const url = new URL(ROADS_SNAP_URL);
  url.searchParams.set('path', path);
  url.searchParams.set('interpolate', 'false');
  url.searchParams.set('key', apiKey);

  const res = await fetch(url.toString(), { method: 'GET' });
  if (!res.ok) {
    return null;
  }
  const json = await res.json();
  const pts = json.snappedPoints;
  if (!Array.isArray(pts) || pts.length === 0) {
    return null;
  }
  const loc = pts[0].location;
  if (!loc || typeof loc.latitude !== 'number' || typeof loc.longitude !== 'number') {
    return null;
  }
  return { lat: loc.latitude, lng: loc.longitude };
}

function roadsApiKey() {
  return (
    process.env.GOOGLE_MAPS_ROADS_API_KEY ||
    process.env.GOOGLE_MAPS_API_KEY ||
    ''
  ).trim();
}

/**
 * Throttle + snap. Tanpa Redis: hanya snap jika throttle tidak diperlukan (single instance) — tetap pakai Redis di route.
 *
 * @param {import('redis').RedisClientType | null} redis
 * @param {string} uid
 * @param {number} lat
 * @param {number} lng
 * @returns {Promise<{ lat: number, lng: number, snapped: boolean }>}
 */
async function maybeSnapDriverLatLng(redis, uid, lat, lng) {
  if (process.env.ROADS_SNAP_ENABLED !== '1') {
    return { lat, lng, snapped: false };
  }
  const apiKey = roadsApiKey();
  if (!apiKey || !redis) {
    return { lat, lng, snapped: false };
  }

  const intervalMs = Math.min(
    Math.max(parseInt(process.env.ROADS_SNAP_MIN_INTERVAL_MS, 10) || 12000, 3000),
    120000,
  );
  const maxJump = Math.min(
    Math.max(parseFloat(process.env.ROADS_SNAP_MAX_JUMP_METERS) || 55, 20),
    120,
  );

  const throttleKey = `roads_snap_throttle:${uid}`;
  try {
    const setOk = await redis.set(throttleKey, '1', { PX: intervalMs, NX: true });
    if (setOk !== 'OK') {
      return { lat, lng, snapped: false };
    }
  } catch (e) {
    console.warn('[roads_snap] throttle:', e.message);
    return { lat, lng, snapped: false };
  }

  try {
    const snapped = await snapToRoadOnce(lat, lng, apiKey);
    if (!snapped) {
      return { lat, lng, snapped: false };
    }
    const d = distanceMeters(lat, lng, snapped.lat, snapped.lng);
    if (d > maxJump) {
      return { lat, lng, snapped: false };
    }
    return { lat: snapped.lat, lng: snapped.lng, snapped: true };
  } catch (e) {
    console.warn('[roads_snap] snapToRoads:', e.message);
    return { lat, lng, snapped: false };
  }
}

module.exports = {
  maybeSnapDriverLatLng,
  distanceMeters,
  snapToRoadOnce,
};
