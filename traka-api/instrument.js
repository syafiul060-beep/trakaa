/**
 * Sentry instrumentation - WAJIB di-require paling awal (sebelum modul lain).
 * Set SENTRY_DSN di .env untuk mengaktifkan error tracking.
 */
require('dotenv').config();
const Sentry = require('@sentry/node');

if (process.env.SENTRY_DSN) {
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    // SENTRY_ENVIRONMENT override untuk dev lokal (PM2 set NODE_ENV=production)
    environment: process.env.SENTRY_ENVIRONMENT || process.env.NODE_ENV || 'development',
    // Produksi: 0.2 untuk lebih banyak trace (alert latency); dev: 0.1
    tracesSampleRate: process.env.NODE_ENV === 'production' ? 0.2 : 0.1,
    // Abaikan error dari /health agar tidak trigger alert (sering ECONNRESET dari monitoring)
    beforeSend(event, hint) {
      const msg = (hint?.originalException?.message || '').toLowerCase();
      const transaction = event.transaction || event.request?.url || '';
      if (
        transaction.includes('/health') ||
        (msg.includes('econnreset') && transaction.includes('health'))
      ) {
        return null; // jangan kirim ke Sentry
      }
      return event;
    },
  });
}
