/**
 * Traka realtime worker — Tahap 4 skeleton
 *
 * - SUBSCRIBE Redis channel `driver:location` (publish dari traka-api saat REDIS_PUBLISH_DRIVER_LOCATION=1)
 * - Broadcast ke room Socket.IO `gh5:<geohash5>` (ngeohash precision 5)
 *
 * Klien: emit `join` dengan { lat, lng } atau { hash } (5 char) untuk socket.join(room).
 */
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const http = require('http');
const express = require('express');
const cors = require('cors');
const { Server } = require('socket.io');
const Redis = require('ioredis');
const ngeohash = require('ngeohash');
const { verifyWsTicket } = require('./wsTicket.js');

const PORT = Number(process.env.PORT) || 3100;
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || '*')
  .split(',')
  .map((o) => o.trim());

const app = express();
app.use(cors({ origin: ALLOWED_ORIGINS.includes('*') ? true : ALLOWED_ORIGINS }));
app.get('/health', (req, res) => {
  res.json({
    ok: true,
    service: 'traka-realtime-worker',
    uptimeSeconds: Math.floor(process.uptime()),
  });
});

const httpServer = http.createServer(app);

const io = new Server(httpServer, {
  cors: {
    origin: ALLOWED_ORIGINS.includes('*') ? true : ALLOWED_ORIGINS,
    methods: ['GET', 'POST'],
  },
});

const devSecret = process.env.SOCKET_AUTH_DEV_SECRET;

io.use((socket, next) => {
  if (!devSecret) {
    return next();
  }
  const token =
    socket.handshake.auth?.token ||
    socket.handshake.query?.token ||
    '';
  if (token === devSecret) {
    return next();
  }
  return next(new Error('Unauthorized'));
});

io.on('connection', (socket) => {
  socket.on('join', (payload, ack) => {
    try {
      if (!payload || typeof payload !== 'object') {
        if (typeof ack === 'function') ack({ ok: false, error: 'invalid payload' });
        return;
      }
      let hash;
      if (payload.lat != null && payload.lng != null) {
        hash = ngeohash.encode(
          Number(payload.lat),
          Number(payload.lng),
          5,
        );
      } else if (typeof payload.hash === 'string' && payload.hash.length >= 5) {
        hash = payload.hash.slice(0, 5);
      }
      if (!hash) {
        if (typeof ack === 'function') ack({ ok: false, error: 'need lat/lng or hash' });
        return;
      }
      const room = `gh5:${hash}`;
      socket.join(room);
      if (typeof ack === 'function') {
        ack({ ok: true, room, hash });
      }
    } catch (e) {
      if (typeof ack === 'function') ack({ ok: false, error: e.message });
    }
  });

  socket.on('leave', (payload, ack) => {
    try {
      const hash =
        payload?.hash ||
        (payload?.lat != null && payload?.lng != null
          ? ngeohash.encode(Number(payload.lat), Number(payload.lng), 5)
          : null);
      if (hash) {
        socket.leave(`gh5:${hash}`);
      }
      if (typeof ack === 'function') ack({ ok: true });
    } catch (e) {
      if (typeof ack === 'function') ack({ ok: false, error: e.message });
    }
  });
});

const redisUrl = process.env.REDIS_URL;
if (!redisUrl) {
  console.error('Missing REDIS_URL');
  process.exit(1);
}

const subscriber = new Redis(redisUrl, {
  maxRetriesPerRequest: null,
  enableReadyCheck: true,
});

subscriber.on('error', (err) => {
  console.error('[redis subscriber]', err.message);
});

subscriber.subscribe('driver:location', (err) => {
  if (err) {
    console.error('[redis] SUBSCRIBE failed:', err.message);
    process.exit(1);
  }
  console.log('[redis] subscribed to driver:location');
});

subscriber.on('message', (channel, message) => {
  if (channel !== 'driver:location') return;
  let data;
  try {
    data = JSON.parse(message);
  } catch {
    return;
  }
  const lat = Number(data.lat);
  const lng = Number(data.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;

  const hash = ngeohash.encode(lat, lng, 5);
  const room = `gh5:${hash}`;
  io.to(room).emit('driver:location', data);
});

httpServer.listen(PORT, () => {
  console.log(`traka-realtime-worker listening on :${PORT}`);
  if (!devSecret && !ticketSecret) {
    console.warn('[auth] No SOCKET_AUTH_DEV_SECRET or REALTIME_WS_TICKET_SECRET — open WS (dev only)');
  } else if (ticketSecret) {
    console.log('[auth] REALTIME_WS_TICKET_SECRET set — require HMAC ticket or dev secret');
  }
});
