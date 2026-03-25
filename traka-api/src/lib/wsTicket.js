/**
 * Tiket handshake Socket.IO (Tahap 4): HMAC atas payload { uid, exp, v }.
 * Secret sama di traka-api dan traka-realtime-worker (REALTIME_WS_TICKET_SECRET).
 */
const crypto = require('crypto');

function mintWsTicket(uid, ttlSec, secret) {
  if (!uid || typeof uid !== 'string' || !secret || secret.length < 16) {
    throw new Error('mintWsTicket: invalid args');
  }
  const exp = Math.floor(Date.now() / 1000) + ttlSec;
  const payload = JSON.stringify({ uid, exp, v: 1 });
  const body = Buffer.from(payload, 'utf8').toString('base64url');
  const sig = crypto.createHmac('sha256', secret).update(body).digest('base64url');
  return `${body}.${sig}`;
}

function verifyWsTicket(token, secret) {
  if (!token || typeof token !== 'string' || !secret) return null;
  const i = token.lastIndexOf('.');
  if (i <= 0) return null;
  const body = token.slice(0, i);
  const sig = token.slice(i + 1);
  const expect = crypto.createHmac('sha256', secret).update(body).digest('base64url');
  const sigBuf = Buffer.from(sig, 'utf8');
  const expBuf = Buffer.from(expect, 'utf8');
  if (sigBuf.length !== expBuf.length) return null;
  try {
    if (!crypto.timingSafeEqual(sigBuf, expBuf)) return null;
  } catch {
    return null;
  }
  let data;
  try {
    data = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
  } catch {
    return null;
  }
  if (data.v !== 1 || typeof data.uid !== 'string' || typeof data.exp !== 'number') return null;
  if (data.exp < Math.floor(Date.now() / 1000)) return null;
  return data;
}

module.exports = { mintWsTicket, verifyWsTicket };
