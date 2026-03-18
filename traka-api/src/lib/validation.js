/**
 * Input validation dan sanitization untuk Traka API.
 */

const EMAIL_REGEX = /^[\w.-]+@[\w.-]+\.\w+$/;
const UID_REGEX = /^[a-zA-Z0-9_-]{20,128}$/;

function sanitizeString(val, maxLen = 500) {
  if (val == null) return null;
  const s = String(val).trim();
  return s.length > maxLen ? s.substring(0, maxLen) : s;
}

function sanitizeNumber(val, min, max) {
  if (val == null) return null;
  const n = parseFloat(val);
  if (Number.isNaN(n)) return null;
  if (min != null && n < min) return min;
  if (max != null && n > max) return max;
  return n;
}

function isValidUid(uid) {
  return uid && typeof uid === 'string' && UID_REGEX.test(uid);
}

function isValidEmail(email) {
  return email && typeof email === 'string' && EMAIL_REGEX.test(email.trim().toLowerCase());
}

function isValidLatLng(lat, lng) {
  const la = parseFloat(lat);
  const lo = parseFloat(lng);
  return !Number.isNaN(la) && !Number.isNaN(lo) && la >= -90 && la <= 90 && lo >= -180 && lo <= 180;
}

module.exports = {
  sanitizeString,
  sanitizeNumber,
  isValidUid,
  isValidEmail,
  isValidLatLng,
};
