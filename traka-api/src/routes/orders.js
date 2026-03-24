const express = require('express');
const router = express.Router();
const { getPg } = require('../lib/pg.js');
const { verifyToken } = require('../lib/auth.js');
const {
  getFirestore,
  isPassengerVerificationBlocking,
  findDuplicatePendingFirestore,
  normalizeBody,
  validateNormalized,
  buildFirestorePayload,
  insertOrderPostgres,
  ORDER_KIRIM_BARANG,
  ORDER_TRAVEL,
} = require('../lib/order_create.js');

/**
 * POST /api/orders — buat order (penumpang). Selaras OrderService.createOrder + ORDER_CREATE_HYBRID.md
 * Dual-write: Firestore (sumber untuk app) + PostgreSQL jika DATABASE_URL aktif.
 */
router.post('/', verifyToken, async (req, res) => {
  try {
    const db = getFirestore();
    if (!db) {
      return res.status(503).json({ error: 'Firestore not configured (Firebase Admin)' });
    }

    const n = normalizeBody(req.body || {});
    const vErr = validateNormalized(n);
    if (vErr) {
      return res.status(400).json({ error: vErr.error });
    }

    if (n.passengerUid !== req.uid) {
      return res.status(403).json({ error: 'passengerUid must match authenticated user' });
    }

    if (await isPassengerVerificationBlocking(db, n.passengerUid)) {
      return res.status(403).json({ error: 'admin_verification_blocking' });
    }

    if (n.orderType === ORDER_TRAVEL && !n.bypassDuplicatePendingTravel) {
      const dup = await findDuplicatePendingFirestore(
        db,
        n.passengerUid,
        n.driverUid,
        ORDER_TRAVEL,
      );
      if (dup) {
        return res.status(409).json({
          error: 'duplicate_pending_travel',
          existingOrderId: dup,
        });
      }
    }

    if (n.orderType === ORDER_KIRIM_BARANG && !n.bypassDuplicatePendingKirimBarang) {
      const dup = await findDuplicatePendingFirestore(
        db,
        n.passengerUid,
        n.driverUid,
        ORDER_KIRIM_BARANG,
      );
      if (dup) {
        return res.status(409).json({
          error: 'duplicate_pending_kirim_barang',
          existingOrderId: dup,
        });
      }
    }

    const orderRef = db.collection('orders').doc();
    const id = orderRef.id;
    const { data } = buildFirestorePayload(n, id);

    try {
      await orderRef.set(data);
    } catch (e) {
      console.error('POST /api/orders Firestore:', e);
      return res.status(500).json({ error: 'firestore_write_failed' });
    }

    const pg = getPg();
    if (pg) {
      try {
        await insertOrderPostgres(pg, id, n);
      } catch (e) {
        console.error('POST /api/orders PostgreSQL:', e.message);
        try {
          await orderRef.delete();
        } catch (_) {}
        return res.status(500).json({
          error: 'postgresql_write_failed',
          detail: process.env.NODE_ENV === 'development' ? e.message : undefined,
        });
      }
    }

    return res.status(201).json({
      id,
      status: n.status,
      orderType: n.orderType,
      driverUid: n.driverUid,
      routeJourneyNumber: n.routeJourneyNumber,
    });
  } catch (err) {
    console.error('POST /api/orders:', err);
    return res.status(500).json({ error: err.message });
  }
});

router.get('/', verifyToken, async (req, res) => {
  try {
    const pg = getPg();
    if (!pg) return res.status(503).json({ error: 'PostgreSQL not available' });

    const uid = req.uid;
    const role = req.query.role; // 'driver' | 'passenger'
    const limit = Math.min(parseInt(req.query.limit, 10) || 50, 100);
    const offset = Math.max(parseInt(req.query.offset, 10) || 0, 0);

    let rows;
    if (role === 'driver') {
      const r = await pg.query(
        `SELECT * FROM orders WHERE "driverUid" = $1 ORDER BY "updatedAt" DESC NULLS LAST LIMIT $2 OFFSET $3`,
        [uid, limit, offset],
      );
      rows = r.rows;
    } else if (role === 'passenger') {
      const r = await pg.query(
        `SELECT * FROM orders WHERE "passengerUid" = $1 ORDER BY "updatedAt" DESC NULLS LAST LIMIT $2 OFFSET $3`,
        [uid, limit, offset],
      );
      rows = r.rows;
    } else {
      const r = await pg.query(
        `SELECT * FROM orders WHERE "driverUid" = $1 OR "passengerUid" = $1 ORDER BY "updatedAt" DESC NULLS LAST LIMIT $2 OFFSET $3`,
        [uid, uid, limit, offset],
      );
      rows = r.rows;
    }

    res.json(rows);
  } catch (err) {
    console.error('GET /orders:', err);
    res.status(500).json({ error: err.message });
  }
});

router.get('/:id', verifyToken, async (req, res) => {
  try {
    const pg = getPg();
    if (!pg) return res.status(503).json({ error: 'PostgreSQL not available' });

    const r = await pg.query('SELECT * FROM orders WHERE id = $1', [req.params.id]);
    const row = r.rows[0];
    if (!row) return res.status(404).json({ error: 'Order not found' });

    const uid = req.uid;
    if (row.driverUid !== uid && row.passengerUid !== uid) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    res.json(row);
  } catch (err) {
    console.error('GET /orders/:id:', err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
