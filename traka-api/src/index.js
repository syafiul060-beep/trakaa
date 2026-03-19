// Sentry harus di-init paling awal
require('../instrument.js');

const express = require('express');
const Sentry = require('@sentry/node');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const { RedisStore } = require('rate-limit-redis');
const driverRoutes = require('./routes/driver.js');
const matchRoutes = require('./routes/match.js');
const ordersRoutes = require('./routes/orders.js');
const usersRoutes = require('./routes/users.js');
const { initRedis, getRedis } = require('./lib/redis.js');
const { initPg, getPg } = require('./lib/pg.js');
const { initFirebase } = require('./lib/auth.js');

const app = express();
const PORT = process.env.PORT || 3001;

// CORS: batasi origin (env ALLOWED_ORIGINS = "https://app.traka.id,https://admin.traka.id")
const allowedOrigins = (process.env.ALLOWED_ORIGINS || '*').split(',').map((o) => o.trim());
const corsOptions = {
  origin: allowedOrigins.includes('*') ? true : allowedOrigins,
  credentials: true,
};
app.use(cors(corsOptions));

app.use(express.json({ limit: '100kb' }));

app.get('/health', async (req, res) => {
  const checks = { api: true, redis: false, pg: false };
  let pgError = null;
  try {
    try {
      const redis = getRedis();
      if (redis) {
        await redis.ping();
        checks.redis = true;
      }
    } catch (_) {}
    try {
      const pg = getPg();
      if (pg) {
        await pg.query('SELECT 1');
        checks.pg = true;
      }
    } catch (e) {
      pgError = e.message;
    }
    const ok = checks.api && checks.redis;
    const body = { ok, status: 'traka-api', checks };
    if (req.query.debug === '1' && pgError) body.pgError = pgError;
    res.status(ok ? 200 : 503).json(body);
  } catch (err) {
    // Jangan crash - selalu kirim response agar monitoring tidak trigger ECONNRESET
    console.error('[health]', err.message);
    res.status(503).json({
      ok: false,
      status: 'traka-api',
      checks: { ...checks, api: false },
      error: req.query.debug === '1' ? err.message : undefined,
    });
  }
});

async function start() {
  try {
    initFirebase();
    await initRedis();
    await initPg();

    // Rate limiting: Redis store (shared across instances) atau fallback memory
    const redis = getRedis();
    const limiter = rateLimit({
      windowMs: 15 * 60 * 1000,
      limit: 100,
      message: { error: 'Terlalu banyak permintaan. Coba lagi nanti.' },
      standardHeaders: true,
      legacyHeaders: false,
      store: redis
        ? new RedisStore({ sendCommand: (...args) => redis.sendCommand(args) })
        : undefined,
    });
    app.use(limiter);

    app.use('/api/driver', driverRoutes);
    app.use('/api/match', matchRoutes);
    app.use('/api/orders', ordersRoutes);
    app.use('/api/users', usersRoutes);

    // Sentry error handler – setelah routes, sebelum listen
    if (process.env.SENTRY_DSN) {
      Sentry.setupExpressErrorHandler(app);
    }

    app.listen(PORT, () => {
      console.log(`Traka API running on http://localhost:${PORT}`);
    });
  } catch (err) {
    console.error('Failed to start:', err);
    process.exit(1);
  }
}

start();
