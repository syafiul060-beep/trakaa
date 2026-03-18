const express = require('express');
const router = express.Router();
const { getPg } = require('../lib/pg.js');
const { verifyToken } = require('../lib/auth.js');

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
        [uid, limit, offset]
      );
      rows = r.rows;
    } else if (role === 'passenger') {
      const r = await pg.query(
        `SELECT * FROM orders WHERE "passengerUid" = $1 ORDER BY "updatedAt" DESC NULLS LAST LIMIT $2 OFFSET $3`,
        [uid, limit, offset]
      );
      rows = r.rows;
    } else {
      const r = await pg.query(
        `SELECT * FROM orders WHERE "driverUid" = $1 OR "passengerUid" = $1 ORDER BY "updatedAt" DESC NULLS LAST LIMIT $2 OFFSET $3`,
        [uid, uid, limit, offset]
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
