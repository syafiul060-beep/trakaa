/**
 * Script admin: generate kode recovery untuk user (nomor hilang/tidak aktif).
 * Jalankan: cd traka/functions && node scripts/create-recovery-token.js <uid>
 *
 * Verifikasi identitas user dulu (KTP, dll) sebelum jalankan.
 * Kirim kode ke user via WhatsApp/email. Kode berlaku 15 menit.
 *
 * Pastikan: serviceAccountKey.json ada di functions/
 */

const admin = require('firebase-admin');
const path = require('path');

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'syafiul-traka';
const CODE_LENGTH = 8;
const CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function generateCode() {
  let s = '';
  for (let i = 0; i < CODE_LENGTH; i++) {
    s += CHARS.charAt(Math.floor(Math.random() * CHARS.length));
  }
  return s;
}

async function main() {
  const uid = process.argv[2];
  if (!uid) {
    console.error('Usage: node create-recovery-token.js <uid>');
    console.error('Contoh: node create-recovery-token.js abc123xyz');
    process.exit(1);
  }

  if (!admin.apps.length) {
    const keyPath = path.join(__dirname, '..', 'serviceAccountKey.json');
    const fs = require('fs');
    if (!fs.existsSync(keyPath)) {
      console.error('serviceAccountKey.json tidak ditemukan. Buat dari Firebase Console.');
      process.exit(1);
    }
    const serviceAccount = require(keyPath);
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount), projectId: PROJECT_ID });
  }

  const auth = admin.auth();
  const db = admin.firestore();

  try {
    await auth.getUser(uid);
  } catch (e) {
    console.error('User tidak ditemukan:', uid);
    process.exit(1);
  }

  const customToken = await auth.createCustomToken(uid);
  let code = generateCode();
  const ref = db.collection('recovery_codes').doc(code);
  if ((await ref.get()).exists) {
    code = generateCode();
  }
  await ref.set({
    token: customToken,
    uid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log('\n=== KODE RECOVERY ===');
  console.log('Kode:', code);
  console.log('Berlaku: 15 menit');
  console.log('Kirim ke user. User buka app > Login > "Nomor hilang? Masukkan kode recovery"');
  console.log('====================\n');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
