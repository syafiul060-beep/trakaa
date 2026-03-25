/**
 * Verifikasi tiket dari traka-api (lib/wsTicket.js — algoritma sama).
 */
const crypto = require('crypto');

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

module.exports = { verifyWsTicket };
