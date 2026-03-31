/**
 * Gate kapasitas saat status order menjadi agreed — selaras OrderService.countUsedSlotsForRoute + getOrderLoad.
 * Dipanggil dari onPassengerAgreed sebelum FCM.
 */

const admin = require("firebase-admin");

const STATUS_AGREED = "agreed";
const STATUS_PICKED_UP = "picked_up";
const ORDER_TRAVEL = "travel";
const ORDER_KIRIM_BARANG = "kirim_barang";
const BARANG_DOKUMEN = "dokumen";
const BARANG_KARGO = "kargo";
const APP_SETTINGS = "app_config/settings";

/**
 * @param {FirebaseFirestore.Firestore} db
 * @returns {Promise<number>}
 */
async function getKargoSlotPerOrder(db) {
  try {
    const doc = await db.doc(APP_SETTINGS).get();
    const v = doc.data()?.kargoSlotPerOrder;
    if (typeof v === "number" && v >= 0) return v;
    if (typeof v === "string") {
      const n = parseFloat(v);
      if (!Number.isNaN(n) && n >= 0) return n;
    }
  } catch (_) {
    // abaikan
  }
  return 1.0;
}

/**
 * @param {Record<string, unknown>} d
 * @param {number} kargoSlot
 * @returns {number}
 */
function orderSlotLoad(d, kargoSlot) {
  const orderType = d.orderType || ORDER_TRAVEL;
  if (orderType === ORDER_KIRIM_BARANG) {
    const cat = d.barangCategory || "";
    if (cat === BARANG_DOKUMEN) return 0;
    if (cat === BARANG_KARGO || cat === "") {
      return Math.min(10, Math.max(1, Math.ceil(Number(kargoSlot) || 1)));
    }
    return 0;
  }
  const jk = Number(d.jumlahKerabat);
  if (!Number.isFinite(jk) || jk <= 0) return 1;
  return 1 + Math.trunc(jk);
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} driverUid
 * @returns {Promise<number>} 0 = tidak dibatasi / belum diisi
 */
async function getMaxPassengersForDriver(db, driverUid) {
  if (!driverUid) return 0;
  try {
    const snap = await db.collection("users").doc(driverUid).get();
    const jp = snap.data()?.vehicleJumlahPenumpang;
    if (typeof jp === "number" && jp > 0) return Math.trunc(jp);
    if (typeof jp === "string") {
      const n = parseInt(jp, 10);
      if (!Number.isNaN(n) && n > 0) return n;
    }
  } catch (_) {
    // abaikan
  }
  return 0;
}

/**
 * Total slot terpakai (agreed + picked_up) untuk driver + routeJourneyNumber.
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} driverUid
 * @param {string} routeJourneyNumber
 * @param {number} kargoSlot
 * @returns {Promise<number>}
 */
async function countUsedSlotsForDriverRoute(db, driverUid, routeJourneyNumber, kargoSlot) {
  if (!driverUid || !routeJourneyNumber) return 0;
  const snap = await db
    .collection("orders")
    .where("driverUid", "==", driverUid)
    .where("routeJourneyNumber", "==", routeJourneyNumber)
    .where("status", "in", [STATUS_AGREED, STATUS_PICKED_UP])
    .get();

  let used = 0;
  snap.forEach((doc) => {
    used += orderSlotLoad(doc.data(), kargoSlot);
  });
  return used;
}

/**
 * Setelah write: jika total slot > maxPassengers, kembalikan order ini ke pending (penumpang belum setuju penuh).
 * @param {admin.firestore.DocumentReference} orderRef
 * @param {Record<string, unknown>} afterData — data order setelah update
 * @returns {Promise<boolean>} true jika dilakukan revert
 */
async function revertIfCapacityExceeded(orderRef, afterData) {
  const db = admin.firestore();
  const driverUid = afterData.driverUid || "";
  const routeJn = afterData.routeJourneyNumber || "";
  const maxP = await getMaxPassengersForDriver(db, driverUid);
  if (!maxP || maxP <= 0) return false;

  const kargoSlot = await getKargoSlotPerOrder(db);
  const total = await countUsedSlotsForDriverRoute(db, driverUid, routeJn, kargoSlot);
  if (total <= maxP) return false;

  await orderRef.update({
    passengerAgreed: false,
    status: "pending_agreement",
    orderNumber: admin.firestore.FieldValue.delete(),
    driverBarcodePickupPayload: admin.firestore.FieldValue.delete(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return true;
}

module.exports = {
  orderSlotLoad,
  getKargoSlotPerOrder,
  getMaxPassengersForDriver,
  countUsedSlotsForDriverRoute,
  revertIfCapacityExceeded,
};
