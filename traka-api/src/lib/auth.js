const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');

let authInitialized = false;

function initFirebase() {
  if (authInitialized) return;
  try {
    const json = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
    if (json) {
      const serviceAccount = JSON.parse(json);
      admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
      authInitialized = true;
      return;
    }
    const p = process.env.FIREBASE_SERVICE_ACCOUNT_PATH || path.join(process.cwd(), 'firebase-service-account.json');
    const resolvedPath = path.isAbsolute(p) ? p : path.resolve(process.cwd(), p);
    if (fs.existsSync(resolvedPath)) {
      const serviceAccount = require(resolvedPath);
      admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
      authInitialized = true;
    } else {
      console.warn('Firebase service account not found (set FIREBASE_SERVICE_ACCOUNT_JSON or FIREBASE_SERVICE_ACCOUNT_PATH)');
    }
  } catch (err) {
    console.warn('Firebase Admin init error:', err.message);
  }
}

async function verifyToken(req, res, next) {
  initFirebase();
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing or invalid token' });
  }
  const token = authHeader.split('Bearer ')[1];
  try {
    const decoded = await admin.auth().verifyIdToken(token);
    req.uid = decoded.uid;
    next();
  } catch (err) {
    return res.status(401).json({ error: 'Invalid token' });
  }
}

module.exports = { verifyToken, initFirebase };
