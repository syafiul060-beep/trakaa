/**
 * Jika slot jadwal dihapus padahal masih ada order aktif pada scheduleId itu,
 * dokumen di-subkoleksi dipulihkan (server-side safety net).
 */

const admin = require("firebase-admin");

const ACTIVE_STATUSES = new Set([
  "pending_agreement",
  "agreed",
  "picked_up",
  "pending_receiver",
]);

function toLegacyScheduleId(sid) {
  if (!sid || typeof sid !== "string") return "";
  const idx = sid.indexOf("_h");
  if (idx > 0) return sid.substring(0, idx);
  return sid;
}

function legacyIdFromSlot(data, driverUid) {
  const dateTs = data.date;
  const depTs = data.departureTime;
  if (!dateTs || !depTs || typeof dateTs.toDate !== "function" || typeof depTs.toDate !== "function") {
    return "";
  }
  const dep = depTs.toDate();
  const d = dateTs.toDate();
  const ymd = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  const depMs = dep.getTime();
  return `${driverUid}_${ymd}_${depMs}`;
}

async function hasBlockingOrderForScheduleIds(scheduleIds) {
  const ids = [...new Set(scheduleIds.filter((x) => x && typeof x === "string"))];
  for (const sid of ids) {
    const snap = await admin.firestore().collection("orders")
      .where("scheduleId", "==", sid)
      .limit(40)
      .get();
    for (const d of snap.docs) {
      const s = d.data()?.status;
      if (s && ACTIVE_STATUSES.has(s)) return true;
    }
  }
  return false;
}

/**
 * @param {FirebaseFirestore.DocumentSnapshot} snap
 * @param {string} driverId
 */
async function restoreIfScheduleHasActiveOrders(snap, driverId) {
  const data = snap.data();
  if (!data) return;
  const storedId = (data.scheduleId && String(data.scheduleId).trim()) || "";
  const legFromStored = toLegacyScheduleId(storedId);
  const legComputed = legacyIdFromSlot(data, driverId);
  const candidates = [storedId, legFromStored, legComputed].filter(Boolean);
  const block = await hasBlockingOrderForScheduleIds(candidates);
  if (!block) return;
  const itemId = snap.id;
  const ref = admin.firestore()
    .collection("driver_schedules")
    .doc(driverId)
    .collection("schedule_items")
    .doc(itemId);
  await ref.set(data);
  console.warn("scheduleItemDeleteGuard: restored slot (active orders)", driverId, itemId, candidates);
}

module.exports = { restoreIfScheduleHasActiveOrders };
