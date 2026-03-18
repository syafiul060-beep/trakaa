/**
 * Migrasi data Firestore ke PostgreSQL
 * Butuh: Firebase Admin SDK + akses Firestore
 * Jalankan: node scripts/migrate-firestore-to-pg.js
 */
require('dotenv').config();
const admin = require('firebase-admin');
const { Pool } = require('pg');
const path = require('path');
const fs = require('fs');

const serviceAccountPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH || path.join(process.cwd(), 'firebase-service-account.json');
if (!fs.existsSync(serviceAccountPath)) {
  console.error('Firebase service account not found. Set FIREBASE_SERVICE_ACCOUNT_PATH');
  process.exit(1);
}

const serviceAccount = require(serviceAccountPath);
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const firestore = admin.firestore();

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
if (!process.env.DATABASE_URL) {
  console.error('DATABASE_URL not set');
  process.exit(1);
}

function toPgTimestamp(date) {
  return date ? date.toISOString() : null;
}

async function migrateUsers() {
  const snap = await firestore.collection('users').get();
  let count = 0;
  for (const doc of snap.docs) {
    const d = doc.data();
    await pool.query(
      `INSERT INTO users (id, email, "phoneNumber", "displayName", "photoUrl", "driverSIMVerifiedAt", "driverSIMNomorHash", "vehicleMerek", "vehicleType", "vehicleJumlahPenumpang", role, region, latitude, longitude)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
       ON CONFLICT (id) DO UPDATE SET
         email = EXCLUDED.email, "phoneNumber" = EXCLUDED."phoneNumber", "displayName" = EXCLUDED."displayName",
         "photoUrl" = EXCLUDED."photoUrl", region = EXCLUDED.region, latitude = EXCLUDED.latitude, longitude = EXCLUDED.longitude, "updatedAt" = NOW()`,
      [
        doc.id,
        d.email || null,
        d.phoneNumber || null,
        d.displayName || null,
        d.photoUrl || null,
        d.driverSIMVerifiedAt?.toDate?.() ? toPgTimestamp(d.driverSIMVerifiedAt.toDate()) : null,
        d.driverSIMNomorHash || null,
        d.vehicleMerek || null,
        d.vehicleType || null,
        d.vehicleJumlahPenumpang ?? null,
        d.role || null,
        d.region || null,
        (typeof d.latitude === 'number') ? d.latitude : null,
        (typeof d.longitude === 'number') ? d.longitude : null,
      ]
    );
    count++;
  }
  console.log(`Migrated ${count} users`);
}

async function migrateOrders() {
  const snap = await firestore.collection('orders').get();
  let count = 0;
  for (const doc of snap.docs) {
    const d = doc.data();
    const ts = (f) => (f?.toDate ? toPgTimestamp(f.toDate()) : null);
    await pool.query(
      `INSERT INTO orders (id, "orderNumber", "passengerUid", "driverUid", "routeJourneyNumber", "passengerName", "passengerPhotoUrl", "originText", "destText", "originLat", "originLng", "destLat", "destLng", "passengerLat", "passengerLng", "passengerLocationText", status, "driverAgreed", "passengerAgreed", "driverCancelled", "passengerCancelled", "adminCancelled", "adminCancelledAt", "adminCancelReason", "orderType", "receiverUid", "receiverName", "receiverPhotoUrl", "receiverAgreedAt", "receiverLat", "receiverLng", "receiverLocationText", "receiverScannedAt", "jumlahKerabat", "agreedPrice", "agreedPriceAt", "createdAt", "updatedAt", "completedAt", "lastMessageAt", "lastMessageSenderUid", "lastMessageText", "driverLastReadAt", "chatHiddenByPassenger", "chatHiddenByDriver", "chatHiddenByReceiver", "passengerLastReadAt", "receiverLastReadAt", "passengerBarcodePayload", "driverBarcodePickupPayload", "driverBarcodePayload", "passengerScannedPickupAt", "destinationValidationLevel", "driverScannedAt", "pickupLat", "pickupLng", "passengerScannedAt", "dropLat", "dropLng", "tripDistanceKm", "ferryDistanceKm", "tripFareRupiah", "tripBarangFareRupiah", "scheduleId", "scheduledDate", "driverArrivedAtPickupAt", "passengerTrackDriverPaidAt", "passengerLacakBarangPaidAt", "receiverLacakBarangPaidAt", "autoConfirmPickup", "autoConfirmComplete")
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25, $26, $27, $28, $29, $30, $31, $32, $33, $34, $35, $36, $37, $38, $39, $40, $41, $42, $43, $44, $45, $46, $47, $48, $49, $50, $51, $52, $53, $54, $55, $56, $57, $58, $59, $60, $61, $62, $63, $64, $65, $66, $67, $68, $69, $70, $71, $72, $73, $74, $75, $76, $77)
       ON CONFLICT (id) DO UPDATE SET "updatedAt" = EXCLUDED."updatedAt"`,
      [
        doc.id,
        d.orderNumber || null,
        d.passengerUid || '',
        d.driverUid || '',
        d.routeJourneyNumber || '',
        d.passengerName || null,
        d.passengerPhotoUrl || null,
        d.originText || '',
        d.destText || '',
        d.originLat ?? null,
        d.originLng ?? null,
        d.destLat ?? null,
        d.destLng ?? null,
        d.passengerLat ?? null,
        d.passengerLng ?? null,
        d.passengerLocationText || null,
        d.status || 'pending_agreement',
        d.driverAgreed ?? false,
        d.passengerAgreed ?? false,
        d.driverCancelled ?? false,
        d.passengerCancelled ?? false,
        d.adminCancelled ?? false,
        ts(d.adminCancelledAt),
        d.adminCancelReason || null,
        d.orderType || 'travel',
        d.receiverUid || null,
        d.receiverName || null,
        d.receiverPhotoUrl || null,
        ts(d.receiverAgreedAt),
        d.receiverLat ?? null,
        d.receiverLng ?? null,
        d.receiverLocationText || null,
        ts(d.receiverScannedAt),
        d.jumlahKerabat ?? null,
        d.agreedPrice ?? null,
        ts(d.agreedPriceAt),
        ts(d.createdAt),
        ts(d.updatedAt),
        ts(d.completedAt),
        ts(d.lastMessageAt),
        d.lastMessageSenderUid || null,
        d.lastMessageText || null,
        ts(d.driverLastReadAt),
        d.chatHiddenByPassenger ?? false,
        d.chatHiddenByDriver ?? false,
        d.chatHiddenByReceiver ?? false,
        ts(d.passengerLastReadAt),
        ts(d.receiverLastReadAt),
        d.passengerBarcodePayload || null,
        d.driverBarcodePickupPayload || null,
        d.driverBarcodePayload || null,
        ts(d.passengerScannedPickupAt),
        d.destinationValidationLevel || null,
        ts(d.driverScannedAt),
        d.pickupLat ?? null,
        d.pickupLng ?? null,
        ts(d.passengerScannedAt),
        d.dropLat ?? null,
        d.dropLng ?? null,
        d.tripDistanceKm ?? null,
        d.ferryDistanceKm ?? null,
        d.tripFareRupiah ?? null,
        d.tripBarangFareRupiah ?? null,
        d.scheduleId || null,
        d.scheduledDate || null,
        ts(d.driverArrivedAtPickupAt),
        ts(d.passengerTrackDriverPaidAt),
        ts(d.passengerLacakBarangPaidAt),
        ts(d.receiverLacakBarangPaidAt),
        d.autoConfirmPickup ?? false,
        d.autoConfirmComplete ?? false,
      ]
    );
    count++;
  }
  console.log(`Migrated ${count} orders`);
}

async function main() {
  console.log('Starting migration...');
  await migrateUsers();
  await migrateOrders();
  await pool.end();
  console.log('Done.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
