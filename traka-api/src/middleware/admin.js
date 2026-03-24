const admin = require('firebase-admin');
const { initFirebase } = require('../lib/auth.js');

/**
 * Setelah verifyToken. Cek Firestore users/{uid}.role == 'admin'
 */
function verifyAdmin(req, res, next) {
  initFirebase();
  if (!req.uid) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  admin
    .firestore()
    .collection('users')
    .doc(req.uid)
    .get()
    .then((doc) => {
      if (!doc.exists || doc.data().role !== 'admin') {
        return res.status(403).json({ error: 'Admin only' });
      }
      next();
    })
    .catch((e) => {
      console.error('verifyAdmin', e);
      res.status(500).json({ error: e.message });
    });
}

module.exports = { verifyAdmin };
