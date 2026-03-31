/**
 * Merge field pricing/nav premium (dan field lain di JSON) ke app_config/settings.
 * `firebase deploy` tidak menulis data dokumen — jalankan ini setelah deploy atau di CI.
 *
 * Lokal:
 *   cd traka/functions
 *   # letakkan serviceAccountKey.json di folder functions/ (sama seperti set-voice-call-turn.js)
 *   npm run seed:app-config
 *
 * File JSON lain:
 *   node scripts/seed_app_config_settings.js ../docs/app_config_settings_nav_premium_legacy.example.json
 *
 * Hanya cetak (tanpa tulis):
 *   node scripts/seed_app_config_settings.js --dry-run
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const DEFAULT_JSON = path.join(__dirname, '..', '..', 'docs', 'app_config_settings_pricing.example.json');

function readDefaultProjectId() {
  const firebasercPath = path.join(__dirname, '..', '..', '.firebaserc');
  if (!fs.existsSync(firebasercPath)) {
    return process.env.FIREBASE_PROJECT_ID || process.env.GCLOUD_PROJECT || null;
  }
  const j = JSON.parse(fs.readFileSync(firebasercPath, 'utf8'));
  return j.projects?.default || process.env.FIREBASE_PROJECT_ID || null;
}

const args = process.argv.slice(2).filter((a) => a !== '--dry-run');
const dryRun = process.argv.includes('--dry-run');
const jsonPath = path.resolve(process.cwd(), args[0] || DEFAULT_JSON);

if (!fs.existsSync(jsonPath)) {
  console.error('File JSON tidak ada:', jsonPath);
  process.exit(1);
}

const payload = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) {
  console.error('JSON harus berupa object.');
  process.exit(1);
}

const PROJECT_ID = readDefaultProjectId();

async function main() {
  console.log('Project:', PROJECT_ID || '(unknown until write)');
  console.log('Sumber JSON:', jsonPath);
  console.log('Mode:', dryRun ? 'DRY-RUN (tidak menulis)' : 'merge ke app_config/settings');
  console.log('');

  if (dryRun) {
    console.log(JSON.stringify(payload, null, 2));
    return;
  }

  if (!PROJECT_ID) {
    console.error('Tidak bisa menentukan projectId (.firebaserc atau FIREBASE_PROJECT_ID).');
    process.exit(1);
  }

  if (!admin.apps.length) {
    const keyPath = path.join(__dirname, '..', 'serviceAccountKey.json');
    if (fs.existsSync(keyPath)) {
      const serviceAccount = require(keyPath);
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
        projectId: PROJECT_ID,
      });
    } else {
      console.error('File serviceAccountKey.json tidak ditemukan di folder functions/');
      console.error('Firebase Console > Project Settings > Service Accounts > Generate new private key');
      process.exit(1);
    }
  }

  const firestore = admin.firestore();

  try {
    const ref = firestore.collection('app_config').doc('settings');
    await ref.set(payload, { merge: true });
    console.log('Berhasil merge. Field kunci:');
    Object.keys(payload).forEach((k) => console.log(`  ${k}`));
    console.log('\nSelesai.');
  } catch (e) {
    console.error('Error:', e.message);
    process.exit(1);
  }
}

main();
