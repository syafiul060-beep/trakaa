/**
 * Jendela jadwal driver: 7 hari kalender inklusif (hari ini + 6) menurut Asia/Jakarta.
 * Selaras dengan DriverScheduleService (Flutter). Slot di luar jendela dihapus kecuali masih
 * punya order aktif (scheduleId cocok).
 *
 * deployRevision: 2026-03-25 — paksa upload Functions jika CLI skip "unchanged".
 */

const admin = require("firebase-admin");

const ACTIVE_STATUSES = [
  "pending_agreement",
  "agreed",
  "picked_up",
  "pending_receiver",
];

function formatWibYmd(date) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Jakarta",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

function wibTodayYmd() {
  return formatWibYmd(new Date());
}

function wibLastInclusiveYmd() {
  const today = wibTodayYmd();
  const noon = new Date(`${today}T12:00:00+07:00`);
  const last = new Date(noon.getTime() + 6 * 24 * 60 * 60 * 1000);
  return formatWibYmd(last);
}

/** @param {FirebaseFirestore.Timestamp} ts */
function timestampToWibYmd(ts) {
  if (!ts || typeof ts.toDate !== "function") return null;
  return formatWibYmd(ts.toDate());
}

function isYmdInBookingWindow(ymd) {
  if (!ymd) return false;
  const first = wibTodayYmd();
  const last = wibLastInclusiveYmd();
  return ymd >= first && ymd <= last;
}

function toLegacyScheduleId(sid) {
  if (!sid || typeof sid !== "string") return "";
  const idx = sid.indexOf("_h");
  if (idx > 0) return sid.substring(0, idx);
  return sid;
}

/** Legacy id tanpa hash (sama konsep ScheduleIdUtil di Flutter). */
function legacyIdFromSlot(map, driverUid) {
  const dateTs = map.date;
  const depTs = map.departureTime;
  if (!dateTs || !depTs || typeof dateTs.toDate !== "function" || typeof depTs.toDate !== "function") {
    return "";
  }
  const ymd = timestampToWibYmd(dateTs);
  if (!ymd) return "";
  const depMillis = depTs.toDate().getTime();
  return `${driverUid}_${ymd}_${depMillis}`;
}

/** @param {Set<string>} activeIds */
function slotMatchesActiveIds(map, driverUid, activeIds) {
  if (!activeIds || activeIds.size === 0) return false;
  const stored = map.scheduleId;
  if (stored && typeof stored === "string") {
    const legStored = toLegacyScheduleId(stored);
    for (const aid of activeIds) {
      if (!aid || typeof aid !== "string") continue;
      if (aid === stored || aid === legStored) return true;
      const legA = toLegacyScheduleId(aid);
      if (legA === legStored || legA === stored) return true;
      if (legA === toLegacyScheduleId(legStored)) return true;
    }
  }
  const legacy = legacyIdFromSlot(map, driverUid);
  if (!legacy) return false;
  for (const aid of activeIds) {
    if (!aid || typeof aid !== "string") continue;
    if (aid === legacy || toLegacyScheduleId(aid) === legacy) return true;
  }
  return false;
}

/** @param {Set<string>} activeIds */
function shouldKeepSlot(map, driverUid, activeIds) {
  if (!map || typeof map !== "object") return false;
  const dateTs = map.date;
  if (!dateTs || typeof dateTs.toDate !== "function") return true;
  const ymd = timestampToWibYmd(dateTs);
  if (!ymd) return true;
  if (isYmdInBookingWindow(ymd)) return true;
  return slotMatchesActiveIds(map, driverUid, activeIds);
}

async function fetchActiveScheduleIdsForDriver(driverUid) {
  const snap = await admin.firestore().collection("orders")
    .where("driverUid", "==", driverUid)
    .where("status", "in", ACTIVE_STATUSES)
    .get();
  const out = new Set();
  for (const doc of snap.docs) {
    const sid = doc.data()?.scheduleId;
    if (sid && typeof sid === "string") out.add(sid);
  }
  return out;
}

/**
 * Kembalikan array baru jika perlu penyaringan; null jika tidak ada perubahan.
 * Gagal query order: kembalikan null (fail-open, hindari hapus jadwal yang masih ber-order).
 * @param {string} driverUid
 * @param {object[]} schedules
 * @returns {Promise<object[]|null>}
 */
async function sanitizeDriverSchedulesIfNeeded(driverUid, schedules) {
  if (!Array.isArray(schedules)) return null;

  let activeIds;
  try {
    activeIds = await fetchActiveScheduleIdsForDriver(driverUid);
  } catch (e) {
    console.error(
      "sanitizeDriverSchedulesIfNeeded: orders query failed",
      driverUid,
      e.message || e,
    );
    return null;
  }

  const kept = schedules.filter((s) => shouldKeepSlot(s, driverUid, activeIds));
  if (kept.length === schedules.length) return null;
  return kept;
}

module.exports = {
  sanitizeDriverSchedulesIfNeeded,
  shouldKeepSlot,
  fetchActiveScheduleIdsForDriver,
  wibTodayYmd,
  wibLastInclusiveYmd,
  isYmdInBookingWindow,
  timestampToWibYmd,
};
