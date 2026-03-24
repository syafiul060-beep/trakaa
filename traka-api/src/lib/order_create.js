/**
 * Logika pembuatan order selaras OrderService.createOrder (Flutter) + ORDER_CREATE_HYBRID.md
 */

const admin = require('firebase-admin');

const STATUS_PENDING_AGREEMENT = 'pending_agreement';
const STATUS_PENDING_RECEIVER = 'pending_receiver';
const ORDER_TRAVEL = 'travel';
const ORDER_KIRIM_BARANG = 'kirim_barang';
const ROUTE_SCHEDULED = 'scheduled';

function getFirestore() {
  if (!admin.apps?.length) return null;
  return admin.firestore();
}

/**
 * @returns {Promise<boolean>}
 */
async function isPassengerVerificationBlocking(db, passengerUid) {
  const doc = await db.collection('users').doc(passengerUid).get();
  if (!doc.exists) return false;
  const data = doc.data();
  if (data.adminVerificationPendingAt == null) return false;
  if (data.adminVerificationRestrictFeatures !== true) return false;
  if (data.adminVerificationUserSubmittedAt != null) return false;
  return true;
}

/**
 * @returns {Promise<string|null>} id order duplikat jika ada
 */
async function findDuplicatePendingFirestore(db, passengerUid, driverUid, orderType) {
  const snap = await db
    .collection('orders')
    .where('passengerUid', '==', passengerUid)
    .where('driverUid', '==', driverUid)
    .limit(50)
    .get();

  for (const doc of snap.docs) {
    const d = doc.data();
    const ot = d.orderType || ORDER_TRAVEL;
    const st = d.status || '';
    if (orderType === ORDER_TRAVEL) {
      if (ot === ORDER_TRAVEL && st === STATUS_PENDING_AGREEMENT) return doc.id;
    } else if (orderType === ORDER_KIRIM_BARANG) {
      if (
        ot === ORDER_KIRIM_BARANG &&
        (st === STATUS_PENDING_AGREEMENT || st === STATUS_PENDING_RECEIVER)
      ) {
        return doc.id;
      }
    }
  }
  return null;
}

function normalizeBody(body) {
  const passengerUid = typeof body.passengerUid === 'string' ? body.passengerUid.trim() : '';
  const driverUid = typeof body.driverUid === 'string' ? body.driverUid.trim() : '';
  const routeJourneyNumber =
    typeof body.routeJourneyNumber === 'string' ? body.routeJourneyNumber.trim() : '';
  const passengerName =
    typeof body.passengerName === 'string' ? body.passengerName.trim() : '';
  const passengerPhotoUrl =
    typeof body.passengerPhotoUrl === 'string' ? body.passengerPhotoUrl.trim() : '';
  const passengerAppLocale =
    typeof body.passengerAppLocale === 'string' ? body.passengerAppLocale.trim() : '';
  const originText = typeof body.originText === 'string' ? body.originText.trim() : '';
  const destText = typeof body.destText === 'string' ? body.destText.trim() : '';
  const orderTypeRaw = typeof body.orderType === 'string' ? body.orderType.trim() : ORDER_TRAVEL;
  const orderType =
    orderTypeRaw === ORDER_KIRIM_BARANG ? ORDER_KIRIM_BARANG : ORDER_TRAVEL;

  const scheduleId = typeof body.scheduleId === 'string' ? body.scheduleId.trim() : '';
  const scheduledDate = typeof body.scheduledDate === 'string' ? body.scheduledDate.trim() : '';
  const isScheduled = scheduleId.length > 0 && scheduledDate.length > 0;
  const effectiveRoute = isScheduled ? ROUTE_SCHEDULED : routeJourneyNumber;

  const receiverUid = typeof body.receiverUid === 'string' ? body.receiverUid.trim() : '';
  const receiverName = typeof body.receiverName === 'string' ? body.receiverName.trim() : '';
  const receiverPhotoUrl =
    typeof body.receiverPhotoUrl === 'string' ? body.receiverPhotoUrl.trim() : '';

  const isKirimBarangWithReceiver =
    orderType === ORDER_KIRIM_BARANG && receiverUid.length > 0;
  const status = isKirimBarangWithReceiver ? STATUS_PENDING_RECEIVER : STATUS_PENDING_AGREEMENT;

  const bypassTravel = body.bypassDuplicatePendingTravel === true;
  const bypassKirim = body.bypassDuplicatePendingKirimBarang === true;

  return {
    passengerUid,
    driverUid,
    routeJourneyNumber: effectiveRoute,
    passengerName,
    passengerPhotoUrl,
    passengerAppLocale,
    originText,
    destText,
    originLat: body.originLat != null ? Number(body.originLat) : null,
    originLng: body.originLng != null ? Number(body.originLng) : null,
    destLat: body.destLat != null ? Number(body.destLat) : null,
    destLng: body.destLng != null ? Number(body.destLng) : null,
    orderType,
    receiverUid: receiverUid || null,
    receiverName: receiverName || null,
    receiverPhotoUrl: receiverPhotoUrl || null,
    jumlahKerabat:
      body.jumlahKerabat != null && Number.isFinite(Number(body.jumlahKerabat))
        ? Math.trunc(Number(body.jumlahKerabat))
        : null,
    scheduleId: scheduleId || null,
    scheduledDate: scheduledDate || null,
    barangCategory:
      typeof body.barangCategory === 'string' && body.barangCategory.trim()
        ? body.barangCategory.trim()
        : null,
    barangNama:
      typeof body.barangNama === 'string' && body.barangNama.trim()
        ? body.barangNama.trim()
        : null,
    barangBeratKg:
      body.barangBeratKg != null && Number(body.barangBeratKg) > 0
        ? Number(body.barangBeratKg)
        : null,
    barangPanjangCm:
      body.barangPanjangCm != null && Number(body.barangPanjangCm) > 0
        ? Number(body.barangPanjangCm)
        : null,
    barangLebarCm:
      body.barangLebarCm != null && Number(body.barangLebarCm) > 0
        ? Number(body.barangLebarCm)
        : null,
    barangTinggiCm:
      body.barangTinggiCm != null && Number(body.barangTinggiCm) > 0
        ? Number(body.barangTinggiCm)
        : null,
    barangFotoUrl:
      typeof body.barangFotoUrl === 'string' && body.barangFotoUrl.trim()
        ? body.barangFotoUrl.trim()
        : null,
    lacakBarangIapFeeRupiah:
      body.lacakBarangIapFeeRupiah != null && Number.isFinite(Number(body.lacakBarangIapFeeRupiah))
        ? Math.trunc(Number(body.lacakBarangIapFeeRupiah))
        : null,
    status,
    isKirimBarangWithReceiver,
    bypassDuplicatePendingTravel: bypassTravel,
    bypassDuplicatePendingKirimBarang: bypassKirim,
  };
}

function validateNormalized(n) {
  if (!n.passengerUid) return { error: 'passengerUid required' };
  if (!n.driverUid) return { error: 'driverUid required' };
  if (!n.originText) return { error: 'originText required' };
  if (!n.destText) return { error: 'destText required' };
  return null;
}

/**
 * Objek untuk Firestore .set() — mirror field Flutter createOrder.
 */
function buildFirestorePayload(n, orderId) {
  const FieldValue = admin.firestore.FieldValue;
  const data = {
    orderNumber: null,
    passengerUid: n.passengerUid,
    driverUid: n.driverUid,
    routeJourneyNumber: n.routeJourneyNumber,
    passengerName: n.passengerName,
    passengerPhotoUrl: n.passengerPhotoUrl || '',
    originText: n.originText,
    destText: n.destText,
    originLat: n.originLat ?? null,
    originLng: n.originLng ?? null,
    destLat: n.destLat ?? null,
    destLng: n.destLng ?? null,
    passengerLat: null,
    passengerLng: null,
    passengerLocationText: null,
    driverAgreed: false,
    passengerAgreed: false,
    orderType: n.orderType,
    status: n.status,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  if (n.passengerAppLocale) data.passengerAppLocale = n.passengerAppLocale;
  if (n.isKirimBarangWithReceiver) {
    data.receiverUid = n.receiverUid;
    if (n.receiverName) data.receiverName = n.receiverName;
    if (n.receiverPhotoUrl) data.receiverPhotoUrl = n.receiverPhotoUrl;
  } else if (n.receiverUid) {
    data.receiverUid = n.receiverUid;
  }
  if (n.jumlahKerabat != null) data.jumlahKerabat = n.jumlahKerabat;
  if (n.scheduleId) data.scheduleId = n.scheduleId;
  if (n.scheduledDate) data.scheduledDate = n.scheduledDate;
  if (n.barangCategory) data.barangCategory = n.barangCategory;
  if (n.barangNama) data.barangNama = n.barangNama;
  if (n.barangBeratKg != null) data.barangBeratKg = n.barangBeratKg;
  if (n.barangPanjangCm != null) data.barangPanjangCm = n.barangPanjangCm;
  if (n.barangLebarCm != null) data.barangLebarCm = n.barangLebarCm;
  if (n.barangTinggiCm != null) data.barangTinggiCm = n.barangTinggiCm;
  if (n.barangFotoUrl) data.barangFotoUrl = n.barangFotoUrl;
  if (n.lacakBarangIapFeeRupiah != null) data.lacakBarangIapFeeRupiah = n.lacakBarangIapFeeRupiah;

  return { id: orderId, data };
}

/**
 * Sinkron ke PostgreSQL (opsional). Kolom ekstra butuh migration — lihat scripts/migration_orders_hybrid.sql
 */
async function insertOrderPostgres(pg, id, n) {
  const now = new Date();
  const sql = `
    INSERT INTO orders (
      id, "orderNumber", "passengerUid", "driverUid", "routeJourneyNumber",
      "passengerName", "passengerPhotoUrl", "passengerAppLocale",
      "originText", "destText",
      "originLat", "originLng", "destLat", "destLng",
      "passengerLat", "passengerLng", "passengerLocationText",
      status, "driverAgreed", "passengerAgreed",
      "orderType", "receiverUid", "receiverName", "receiverPhotoUrl",
      "jumlahKerabat", "scheduleId", "scheduledDate",
      "barangCategory", "barangNama", "barangBeratKg", "barangPanjangCm", "barangLebarCm", "barangTinggiCm",
      "barangFotoUrl", "lacakBarangIapFeeRupiah",
      "createdAt", "updatedAt"
    ) VALUES (
      $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
      $11, $12, $13, $14, $15, $16, $17, $18, $19, $20,
      $21, $22, $23, $24, $25, $26, $27, $28, $29, $30,
      $31, $32, $33, $34, $35, $36, $37
    )
  `;
  const values = [
    id,
    null,
    n.passengerUid,
    n.driverUid,
    n.routeJourneyNumber,
    n.passengerName || null,
    n.passengerPhotoUrl || null,
    n.passengerAppLocale || null,
    n.originText,
    n.destText,
    n.originLat,
    n.originLng,
    n.destLat,
    n.destLng,
    null,
    null,
    null,
    n.status,
    false,
    false,
    n.orderType,
    n.receiverUid,
    n.receiverName,
    n.receiverPhotoUrl,
    n.jumlahKerabat,
    n.scheduleId,
    n.scheduledDate,
    n.barangCategory,
    n.barangNama,
    n.barangBeratKg,
    n.barangPanjangCm,
    n.barangLebarCm,
    n.barangTinggiCm,
    n.barangFotoUrl,
    n.lacakBarangIapFeeRupiah,
    now,
    now,
  ];
  await pg.query(sql, values);
}

module.exports = {
  getFirestore,
  isPassengerVerificationBlocking,
  findDuplicatePendingFirestore,
  normalizeBody,
  validateNormalized,
  buildFirestorePayload,
  insertOrderPostgres,
  ORDER_TRAVEL,
  ORDER_KIRIM_BARANG,
  STATUS_PENDING_AGREEMENT,
  STATUS_PENDING_RECEIVER,
};
