const express = require('express');
const router = express.Router();
const { verifyToken } = require('../lib/auth.js');
const {
  createMethod,
  listByDriver,
  updateMethod,
  suspendMethod,
} = require('../lib/driver_payment.js');

router.get('/', verifyToken, async (req, res) => {
  try {
    const methods = await listByDriver(req.uid);
    res.json({ methods });
  } catch (err) {
    console.error('GET /driver/payment-methods:', err);
    res.status(500).json({ error: err.message });
  }
});

router.post('/', verifyToken, async (req, res) => {
  try {
    const out = await createMethod(req.uid, req.body || {});
    res.status(201).json(out);
  } catch (err) {
    const code = err.statusCode || 500;
    if (code >= 500) console.error('POST /driver/payment-methods:', err);
    res.status(code).json({ error: err.message });
  }
});

router.patch('/:id', verifyToken, async (req, res) => {
  try {
    const out = await updateMethod(req.params.id, req.uid, req.body || {});
    res.json(out);
  } catch (err) {
    const code = err.statusCode || 500;
    if (code >= 500) console.error('PATCH /driver/payment-methods:', err);
    res.status(code).json({ error: err.message });
  }
});

router.delete('/:id', verifyToken, async (req, res) => {
  try {
    const out = await suspendMethod(req.params.id, req.uid);
    res.json(out);
  } catch (err) {
    const code = err.statusCode || 500;
    if (code >= 500) console.error('DELETE /driver/payment-methods:', err);
    res.status(code).json({ error: err.message });
  }
});

module.exports = router;
