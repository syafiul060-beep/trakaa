const express = require('express');
const router = express.Router();
const { getPg } = require('../lib/pg.js');
const { verifyToken } = require('../lib/auth.js');
const { isValidUid } = require('../lib/validation.js');

router.get('/:uid', verifyToken, async (req, res) => {
  try {
    const uid = req.params.uid;
    if (!isValidUid(uid)) {
      return res.status(400).json({ error: 'Invalid user ID' });
    }
    const pg = getPg();
    if (!pg) return res.status(503).json({ error: 'PostgreSQL not available' });

    const r = await pg.query('SELECT * FROM users WHERE id = $1', [uid]);
    const row = r.rows[0];
    if (!row) return res.status(404).json({ error: 'User not found' });
    res.json(row);
  } catch (err) {
    console.error('GET /users/:uid:', err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
