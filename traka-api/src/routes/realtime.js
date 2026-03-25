const express = require('express');
const { verifyToken } = require('../lib/auth.js');
const { mintWsTicket } = require('../lib/wsTicket.js');

const router = express.Router();

const TTL_SEC = 600;

/**
 * POST /api/realtime/ws-ticket
 * Header: Authorization: Bearer <Firebase ID token>
 * Body: kosong
 * Response: { ticket, expiresIn } untuk auth Socket.IO traka-realtime-worker.
 */
router.post('/ws-ticket', verifyToken, (req, res) => {
  const secret = process.env.REALTIME_WS_TICKET_SECRET;
  if (!secret || secret.length < 16) {
    return res.status(503).json({
      error: 'Realtime ticket not configured',
      hint: 'Set REALTIME_WS_TICKET_SECRET (min 16 chars) on API and worker',
    });
  }
  try {
    const ticket = mintWsTicket(req.uid, TTL_SEC, secret);
    return res.json({ ticket, expiresIn: TTL_SEC });
  } catch (e) {
    return res.status(500).json({ error: 'Could not mint ticket' });
  }
});

module.exports = router;
