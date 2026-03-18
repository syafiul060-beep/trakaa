/**
 * Script untuk menambahkan/update konfigurasi TURN panggilan suara di app_config/settings.
 * Jalankan: cd traka/functions && node scripts/set-voice-call-turn.js
 *
 * Edit TURN_CONFIG di bawah sesuai TURN server Anda, lalu jalankan script.
 * Pastikan: serviceAccountKey.json ada di functions/ (Firebase Console >
 * Project Settings > Service Accounts > Generate new private key)
 */

const admin = require('firebase-admin');
const path = require('path');

const PROJECT_ID = 'syafiul-traka';

// Edit ini sesuai TURN server Anda (Twilio, Xirsys, coturn, dll)
const TURN_CONFIG = {
  voiceCallTurnUrls: ['turn:turn.example.com:3478'],
  voiceCallTurnUsername: 'user',
  voiceCallTurnCredential: 'secret',
};

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

async function main() {
  console.log('Update app_config/settings - Voice Call TURN...\n');

  try {
    const ref = firestore.collection('app_config').doc('settings');
    await ref.set(TURN_CONFIG, { merge: true });
    console.log('Berhasil! Field yang di-update:');
    Object.entries(TURN_CONFIG).forEach(([k, v]) => console.log(`  ${k}: ${JSON.stringify(v)}`));
    console.log('\nSelesai.');
  } catch (e) {
    console.error('Error:', e.message);
    process.exit(1);
  }
}

main();
