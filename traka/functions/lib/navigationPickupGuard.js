/**
 * Opsi A Tahap 4: rekonsiliasi server-side navigasi jemput vs driver_status.activeNavigatingToPickupOrderId.
 * Rules Firestore tidak melihat tulisan lain dalam batch/transaksi yang sama; trigger Admin SDK
 * membersihkan inkonsistensi dari klien jahat atau tulis sebagian.
 */

const admin = require("firebase-admin");

const COLLECTION_DRIVER_STATUS = "driver_status";
const COLLECTION_ORDERS = "orders";
const FIELD_ACTIVE_NAV = "activeNavigatingToPickupOrderId";

function hasNavigatingTimestamp(data) {
  return data?.driverNavigatingToPickupAt != null;
}

/**
 * Order kehilangan driverNavigatingToPickupAt tetapi driver_status masih menunjuk order ini.
 * @return {Promise<boolean>}
 */
async function reconcileDriverStatusWhenOrderClearsNav(before, after, orderId) {
  if (before?.driverNavigatingToPickupAt == null) return false;
  if (hasNavigatingTimestamp(after)) return false;

  const driverUid = after?.driverUid || "";
  if (!driverUid) return false;

  const dsRef = admin.firestore().collection(COLLECTION_DRIVER_STATUS).doc(driverUid);
  const dsSnap = await dsRef.get();
  if (!dsSnap.exists) return false;

  const active = dsSnap.data()?.[FIELD_ACTIVE_NAV];
  if (active !== orderId) return false;

  await dsRef.set(
      {
        [FIELD_ACTIVE_NAV]: admin.firestore.FieldValue.delete(),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
  );
  return true;
}

/**
 * Order punya flag navigasi jemput tetapi driver_status.active mengarah ke order lain.
 * @return {Promise<boolean>}
 */
async function reconcileOrderNavigatingToPickupIfStale(orderRef, after, orderId) {
  if (!hasNavigatingTimestamp(after)) return false;

  const driverUid = after?.driverUid || "";
  if (!driverUid) return false;

  const dsSnap = await admin.firestore().collection(COLLECTION_DRIVER_STATUS).doc(driverUid).get();
  if (!dsSnap.exists) return false;

  const active = dsSnap.data()?.[FIELD_ACTIVE_NAV];
  if (active == null || active === "") return false;

  if (active === orderId) return false;

  await orderRef.update({
    driverNavigatingToPickupAt: admin.firestore.FieldValue.delete(),
    passengerLiveLat: admin.firestore.FieldValue.delete(),
    passengerLiveLng: admin.firestore.FieldValue.delete(),
    passengerLiveUpdatedAt: admin.firestore.FieldValue.delete(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return true;
}

/**
 * driver_status punya pointer aktif: order harus ada, masih milik driver ini, dan masih navigasi jemput.
 * @return {Promise<boolean>}
 */
async function reconcileDriverStatusActivePointerIfStale(driverId, changeAfter) {
  if (!changeAfter.exists) return false;
  const after = changeAfter.data() || {};
  const active = after[FIELD_ACTIVE_NAV];
  if (active == null || active === "") return false;

  const orderRef = admin.firestore().collection(COLLECTION_ORDERS).doc(String(active));
  const orderSnap = await orderRef.get();

  let mustClear = false;
  if (!orderSnap.exists) {
    mustClear = true;
  } else {
    const od = orderSnap.data() || {};
    if (od.driverUid !== driverId) mustClear = true;
    else if (od.driverNavigatingToPickupAt == null) mustClear = true;
  }

  if (!mustClear) return false;

  await changeAfter.ref.set(
      {
        [FIELD_ACTIVE_NAV]: admin.firestore.FieldValue.delete(),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
  );
  return true;
}

/**
 * Pointer aktif driver_status berubah dari prev → lain: bersihkan flag navigasi di order prev (jika masih driver ini).
 * Menutup celah klien yang hanya mengubah driver_status tanpa men-clear order lama.
 * @param {{ before: FirebaseFirestore.DocumentSnapshot; after: FirebaseFirestore.DocumentSnapshot }} change
 * @param {string} driverId
 * @return {Promise<void>}
 */
async function reconcilePreviousOrderWhenDriverStatusPointerMoves(change, driverId) {
  const beforeActive = change.before.exists ?
    String(change.before.data()?.[FIELD_ACTIVE_NAV] || "") : "";
  const afterActive = change.after.exists ?
    String(change.after.data()?.[FIELD_ACTIVE_NAV] || "") : "";
  if (!beforeActive || beforeActive === afterActive) return;

  const orderRef = admin.firestore().collection(COLLECTION_ORDERS).doc(beforeActive);
  const snap = await orderRef.get();
  if (!snap.exists) return;
  const d = snap.data() || {};
  if (d.driverUid !== driverId) return;
  if (d.driverNavigatingToPickupAt == null) return;

  await orderRef.update({
    driverNavigatingToPickupAt: admin.firestore.FieldValue.delete(),
    passengerLiveLat: admin.firestore.FieldValue.delete(),
    passengerLiveLng: admin.firestore.FieldValue.delete(),
    passengerLiveUpdatedAt: admin.firestore.FieldValue.delete(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

module.exports = {
  reconcileDriverStatusWhenOrderClearsNav,
  reconcileOrderNavigatingToPickupIfStale,
  reconcileDriverStatusActivePointerIfStale,
  reconcilePreviousOrderWhenDriverStatusPointerMoves,
  FIELD_ACTIVE_NAV,
};
