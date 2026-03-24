const express = require('express');
const router = express.Router();
const { verifyToken } = require('../lib/auth.js');
const { verifyAdmin } = require('../middleware/admin.js');
const { listPendingReview, adminSetStatus } = require('../lib/driver_payment.js');

router.get('/pending', verifyToken, verifyAdmin, async (req, res) => {
  try {
    const methods = await listPendingReview();
    res.json({ methods });
  } catch (err) {
    console.error('GET /admin/payment-methods/pending:', err);
    res.status(500).json({ error: err.message });
  }
});

router.post('/:id/approve', verifyToken, verifyAdmin, async (req, res) => {
  try {
    const note = (req.body && req.body.adminNote) || null;
    const out = await adminSetStatus(req.params.id, 'active', note);
    res.json(out);
  } catch (err) {
    const code = err.statusCode || 500;
    if (code >= 500) console.error('POST approve payment-method:', err);
    res.status(code).json({ error: err.message });
  }
});

router.post('/:id/reject', verifyToken, verifyAdmin, async (req, res) => {
  try {
    const note = (req.body && req.body.adminNote) || 'rejected';
    const out = await adminSetStatus(req.params.id, 'suspended', note);
    res.json(out);
  } catch (err) {
    const code = err.statusCode || 500;
    if (code >= 500) console.error('POST reject payment-method:', err);
    res.status(code).json({ error: err.message });
  }
});

module.exports = router;
