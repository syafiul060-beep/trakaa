/**
 * Script untuk update app_config/settings dengan konfigurasi kontribusi optimal.
 * Jalankan: cd traka/functions && node scripts/update-app-config-contribution.js
 *
 * Pastikan: serviceAccountKey.json ada di functions/ (dari Firebase Console >
 * Project Settings > Service Accounts > Generate new private key)
 */

const admin = require('firebase-admin');
const path = require('path');

const PROJECT_ID = 'syafiul-traka';

if (!admin.apps.length) {
  const keyPath = path.join(__dirname, '..', 'serviceAccountKey.json');
  const fs = require('fs');
  if (fs.existsSync(keyPath)) {
    const serviceAccount = require(keyPath);
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount), projectId: PROJECT_ID });
  } else {
    console.error('File serviceAccountKey.json tidak ditemukan di folder functions/');
    console.error('Buat dari Firebase Console > Project Settings > Service Accounts > Generate new private key');
    process.exit(1);
  }
}

const firestore = admin.firestore();

const CONTRIBUTION_CONFIG = {
  minKontribusiTravelRupiah: 5000,
  maxKontribusiTravelPerRuteRupiah: 30000,
  tarifKontribusiTravelDalamProvinsiPerKm: 90,
  tarifKontribusiTravelBedaProvinsiPerKm: 110,
  tarifKontribusiTravelBedaPulauPerKm: 140,
};

async function main() {
  console.log('Update app_config/settings - kontribusi optimal...\n');

  try {
    const ref = firestore.collection('app_config').doc('settings');
    await ref.set(CONTRIBUTION_CONFIG, { merge: true });
    console.log('Berhasil! Field yang di-update:');
    Object.entries(CONTRIBUTION_CONFIG).forEach(([k, v]) => console.log(`  ${k}: ${v}`));
    console.log('\nSelesai.');
  } catch (e) {
    console.error('Error:', e.message);
    process.exit(1);
  }
}

main();
