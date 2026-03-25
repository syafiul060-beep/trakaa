/**
 * Bukti struk publik: token opak, TTL 6 hari, verifikasi via HTTPS (profil.html).
 * Tulis hanya dari Callable issuePublicReceiptProof (Admin SDK).
 */

const crypto = require("crypto");
const admin = require("firebase-admin");

const COLLECTION = "public_receipt_proofs";
const TOKEN_BYTES = 32;
const TTL_MS = 6 * 24 * 60 * 60 * 1000;

function generateToken() {
  return crypto.randomBytes(TOKEN_BYTES).toString("hex");
}

function isParticipant(uid, order) {
  if (!uid || !order) return false;
  if (order.passengerUid === uid) return true;
  const ru = order.receiverUid;
  if (ru && ru === uid) return true;
  return false;
}

/** Driver yang menjalankan order (untuk bukti PDF / verifikasi web, sama TTL & koleksi). */
function isDriver(uid, order) {
  if (!uid || !order) return false;
  return order.driverUid === uid;
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} orderId
 * @param {object} orderFields - field snapshot untuk verifikasi publik (tanpa UID).
 * @returns {Promise<{ token: string, reused: boolean }>}
 */
async function findOrCreateProof(db, orderId, orderFields) {
  const snap = await db
    .collection(COLLECTION)
    .where("orderId", "==", orderId)
    .limit(5)
    .get();

  const now = Date.now();
  for (const doc of snap.docs) {
    const exp = doc.data()?.expiresAt?.toMillis?.() || 0;
    if (exp > now) {
      return { token: doc.id, reused: true };
    }
  }

  const token = generateToken();
  const issuedAt = new Date();
  const expiresAt = new Date(issuedAt.getTime() + TTL_MS);

  await db.collection(COLLECTION).doc(token).set({
    orderId,
    issuedAt: admin.firestore.Timestamp.fromDate(issuedAt),
    expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
    ...orderFields,
  });

  return { token, reused: false };
}

function tsToMillis(t) {
  if (t == null) return null;
  if (typeof t.toMillis === "function") return t.toMillis();
  if (typeof t.seconds === "number") return t.seconds * 1000;
  if (typeof t._seconds === "number") return t._seconds * 1000;
  return null;
}

function sanitizeForPublic(d) {
  return {
    orderNumber: d.orderNumber ?? null,
    orderType: d.orderType ?? "travel",
    completedAt: tsToMillis(d.completedAt),
    issuedAt: tsToMillis(d.issuedAt),
    expiresAt: tsToMillis(d.expiresAt),
    originText: (d.originText || "").slice(0, 200),
    destText: (d.destText || "").slice(0, 200),
    agreedPriceRupiah:
      d.agreedPriceRupiah != null ? Number(d.agreedPriceRupiah) : null,
    tripFareRupiah: d.tripFareRupiah != null ? Number(d.tripFareRupiah) : null,
    tripBarangFareRupiah:
      d.tripBarangFareRupiah != null
        ? Number(d.tripBarangFareRupiah)
        : null,
    kind: d.kind || "passenger_order",
  };
}

module.exports = {
  COLLECTION,
  TTL_MS,
  generateToken,
  isParticipant,
  isDriver,
  findOrCreateProof,
  sanitizeForPublic,
};
