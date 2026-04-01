/**
 * Menyelaraskan tarif navigasi premium driver dengan Dart: DriverNavPremiumPricing.
 * Input settings = data app_config/settings.
 */

const minFeeRupiah = 9000;
const maxFeeRupiah = 150000;
const maxTrustedDistanceMeters = 2500000;

const defaultTierMaxKm = [75, 200, 450, 900, 1500, 1e9];
const defaultTierBaseFees = [10000, 18000, 28000, 42000, 55000, 68000];
const defaultSnapFees = [
  5000, 7500, 10000, 12500, 15000, 17500, 20000, 25000, 30000, 40000,
  50000, 60000, 75000, 100000, 150000, 200000,
];

function readPositive(d, key, min = 3000) {
  const v = d?.[key];
  if (v == null) return 0;
  const n = typeof v === "number" ? v : parseInt(String(v), 10);
  return !isNaN(n) && n >= min ? n : 0;
}

function legacyScopeOnlyRupiah(scopeName, d) {
  const min = 3000;
  function legacy() {
    const v = d?.driverNavPremiumFeeRupiah;
    if (v == null) return 0;
    const n = typeof v === "number" ? v : parseInt(String(v), 10);
    return !isNaN(n) && n >= min ? n : 0;
  }
  function forScope(scope) {
    switch (scope) {
      case "dalamProvinsi": {
        const x = readPositive(d, "driverNavPremiumFeeDalamProvinsiRupiah", min);
        if (x > 0) return x;
        const l = legacy();
        if (l > 0) return l;
        return 50000;
      }
      case "antarProvinsi": {
        const x = readPositive(d, "driverNavPremiumFeeAntarProvinsiRupiah", min);
        if (x > 0) return x;
        const l = legacy();
        if (l > 0) return l;
        return 75000;
      }
      case "dalamNegara": {
        const x = readPositive(d, "driverNavPremiumFeeNasionalRupiah", min);
        if (x > 0) return x;
        const l = legacy();
        if (l > 0) return l;
        return 100000;
      }
      default: {
        const l = legacy();
        if (l > 0) return l;
        return 100000;
      }
    }
  }
  return forScope(scopeName);
}

function parseTierMaxKm(d) {
  const raw = d?.driverNavPremiumTierMaxKm;
  if (!Array.isArray(raw) || raw.length < 2) return defaultTierMaxKm.slice();
  const out = [];
  for (const e of raw) {
    const n = typeof e === "number" ? e : parseFloat(String(e));
    if (!isNaN(n) && n > 0) out.push(n);
  }
  if (out.length < 2) return defaultTierMaxKm.slice();
  for (let i = 1; i < out.length; i++) {
    if (out[i] <= out[i - 1]) return defaultTierMaxKm.slice();
  }
  return out;
}

function parseTierBases(d, len) {
  const raw = d?.driverNavPremiumTierBaseFeesRupiah;
  if (!Array.isArray(raw) || raw.length !== len) {
    return len === defaultTierMaxKm.length ? defaultTierBaseFees.slice() : [];
  }
  const out = [];
  for (const e of raw) {
    const n = typeof e === "number" ? e : parseInt(String(e), 10);
    if (n == null || isNaN(n) || n < minFeeRupiah) {
      return len === defaultTierMaxKm.length ? defaultTierBaseFees.slice() : [];
    }
    out.push(n);
  }
  return out;
}

function parseSnapFees(d) {
  const raw = d?.driverNavPremiumSnapFeesRupiah;
  if (!Array.isArray(raw) || raw.length === 0) return defaultSnapFees.slice();
  const out = [];
  for (const e of raw) {
    const n = typeof e === "number" ? e : parseInt(String(e), 10);
    if (n != null && !isNaN(n) && n >= minFeeRupiah && n <= maxFeeRupiah) out.push(n);
  }
  out.sort((a, b) => a - b);
  if (out.length === 0) return defaultSnapFees.slice();
  return out;
}

function scopeMultiplierBps(scope, d) {
  function readBps(key, fallback) {
    const v = d?.[key];
    if (v == null) return fallback;
    const n = typeof v === "number" ? v : parseInt(String(v), 10);
    if (isNaN(n) || n < 50 || n > 300) return fallback;
    return n;
  }
  switch (scope) {
    case "dalamProvinsi":
      return readBps("driverNavPremiumScopeMultBpsDalam", 100);
    case "antarProvinsi":
      return readBps("driverNavPremiumScopeMultBpsAntar", 108);
    case "dalamNegara":
    default:
      return readBps("driverNavPremiumScopeMultBpsNasional", 116);
  }
}

function baseFeeForKm(km, maxKms, bases) {
  for (let i = 0; i < maxKms.length && i < bases.length; i++) {
    if (km <= maxKms[i]) return bases[i];
  }
  return bases.length > 0 ? bases[bases.length - 1] : defaultTierBaseFees[defaultTierBaseFees.length - 1];
}

function snapToNearest(raw, allowed) {
  if (!allowed || allowed.length === 0) {
    let x = Math.round(raw / 1000) * 1000;
    if (x < minFeeRupiah) x = minFeeRupiah;
    if (x > maxFeeRupiah) x = maxFeeRupiah;
    return x;
  }
  let best = allowed[0];
  let bestDiff = Math.abs(raw - best);
  for (const a of allowed) {
    const di = Math.abs(raw - a);
    if (di < bestDiff) {
      bestDiff = di;
      best = a;
    }
  }
  if (best < minFeeRupiah) return minFeeRupiah;
  if (best > maxFeeRupiah) return maxFeeRupiah;
  return best;
}

/**
 * @param {{ scope: string|null|undefined, distanceMeters: number|null|undefined, settings: object|null }} p
 * @return {number}
 */
function computeNavPremiumRupiah({ scope, distanceMeters, settings }) {
  const d = settings || {};
  const enabled = d.driverNavPremiumDistancePricingEnabled === true;
  const useDist = enabled &&
    distanceMeters != null &&
    !isNaN(distanceMeters) &&
    distanceMeters > 0 &&
    distanceMeters <= maxTrustedDistanceMeters;

  if (!useDist) {
    return legacyScopeOnlyRupiah(scope || "dalamNegara", d);
  }

  const km = distanceMeters / 1000.0;
  let maxKms = parseTierMaxKm(d);
  let bases = parseTierBases(d, maxKms.length);
  if (bases.length !== maxKms.length) {
    maxKms = defaultTierMaxKm.slice();
    bases = defaultTierBaseFees.slice();
  }
  const snap = parseSnapFees(d);
  const base = baseFeeForKm(km, maxKms, bases);
  const multBps = scopeMultiplierBps(scope || "dalamNegara", d);
  let rawInt = Math.round((base * multBps) / 100.0);
  if (rawInt < minFeeRupiah) rawInt = minFeeRupiah;
  if (rawInt > maxFeeRupiah) rawInt = maxFeeRupiah;
  return snapToNearest(rawInt, snap);
}

module.exports = {
  computeNavPremiumRupiah,
  minFeeRupiah,
  maxFeeRupiah,
};
