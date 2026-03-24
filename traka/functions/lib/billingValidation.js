/**
 * Parser & konfigurasi nominal billing (Google Play SKU) untuk validasi server.
 * Harus selaras dengan app: LacakBarangService, lacak_driver_payment_screen, contribution_driver_screen.
 */

async function getSettingsData(db) {
  const snap = await db.collection("app_config").doc("settings").get();
  return snap.exists ? snap.data() : {};
}

function parseIntSetting(v, fallback) {
  if (v == null) return fallback;
  const n = typeof v === "number" ? v : parseInt(String(v), 10);
  return !isNaN(n) && n > 0 ? n : fallback;
}

async function getLacakDriverFeeRupiah(db) {
  const d = await getSettingsData(db);
  const raw = d?.lacakDriverFeeRupiah;
  let n = 3000;
  if (raw != null) {
    const x = typeof raw === "number" ? raw : parseInt(String(raw), 10);
    if (!isNaN(x) && x > 0) n = x < 3000 ? 3000 : x;
  }
  return n;
}

function expectedLacakDriverProductId(feeRupiah) {
  return `traka_lacak_driver_${feeRupiah}`;
}

/** traka_lacak_barang_10k | traka_lacak_barang_25000 */
function parseLacakBarangAmountRupiah(productId) {
  if (!productId || typeof productId !== "string") return null;
  const mK = productId.match(/^traka_lacak_barang_(\d+)k$/i);
  if (mK) return parseInt(mK[1], 10) * 1000;
  const mN = productId.match(/^traka_lacak_barang_(\d+)$/);
  if (mN) return parseInt(mN[1], 10);
  return null;
}

async function getLacakBarangTierFeesRupiah(db) {
  const d = await getSettingsData(db);
  const t1 = parseIntSetting(d?.lacakBarangDalamProvinsiRupiah, 10000);
  const t2 = parseIntSetting(d?.lacakBarangBedaProvinsiRupiah, 15000);
  const t3 = parseIntSetting(d?.lacakBarangLebihDari1ProvinsiRupiah, 25000);
  return [t1, t2, t3];
}

function parseDriverDuesAmountRupiah(productId) {
  const m = (productId || "").match(/traka_driver_dues_(\d+)/);
  return m ? parseInt(m[1], 10) : null;
}

/** traka_violation_fee_5k | traka_violation_fee_5000 */
function parseViolationFeeAmountRupiah(productId) {
  if (!productId || typeof productId !== "string") return null;
  const mk = productId.match(/^traka_violation_fee_(\d+)k$/i);
  if (mk) return parseInt(mk[1], 10) * 1000;
  const mn = productId.match(/^traka_violation_fee_(\d+)$/);
  if (mn) return parseInt(mn[1], 10);
  return null;
}

/** SKU kontribusi tertinggi (selaras contribution_driver_screen kDriverDuesAmounts). */
const MAX_DRIVER_DUES_SINGLE_PURCHASE_RUPIAH = 200000;

module.exports = {
  getLacakDriverFeeRupiah,
  expectedLacakDriverProductId,
  parseLacakBarangAmountRupiah,
  getLacakBarangTierFeesRupiah,
  parseDriverDuesAmountRupiah,
  parseViolationFeeAmountRupiah,
  MAX_DRIVER_DUES_SINGLE_PURCHASE_RUPIAH,
};
