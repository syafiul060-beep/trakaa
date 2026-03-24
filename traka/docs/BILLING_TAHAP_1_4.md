# Billing Google Play — Tahap 1–4 (operasional & teknis)

Dokumen ini menggabungkan **checklist operasional** (Tahap 1) dan **rujukan implementasi** Tahap 2–4 di codebase. Urutan kerja disarankan: **1 → 2 → 3 → 4**.

---

## Tahap 1 — Operasional (tanpa deploy kode)

1. **Play Console ↔ SKU ↔ harga**
   - Setiap ID produk (`traka_*`) harus punya **harga** di Console yang sama dengan **makna angka di ID** (mis. `traka_lacak_driver_5000` = Rp 5.000).
   - Tabel lengkap: [UPDATE_HARGA_GOOGLE_BILLING.md](./UPDATE_HARGA_GOOGLE_BILLING.md).
   - Setelah menambah SKU baru (mis. kontribusi hingga **200k**), buat produk di Console **sebelum** merilis app yang mereferensikan ID tersebut.

2. **Firestore `app_config/settings`**
   - `lacakDriverFeeRupiah`, tarif lacak barang per tier, dll. harus **konsisten** dengan SKU yang ada (minimal tidak memaksa app memilih produk yang belum dibuat di Console).

3. **Service account verifikasi (wajib production)**
   - Cloud Functions memverifikasi token via Android Publisher API.
   - Set environment: `GOOGLE_PLAY_SERVICE_ACCOUNT_KEY` (JSON string) atau `GOOGLE_PLAY_SERVICE_ACCOUNT_PATH` (path file JSON).
   - Tanpa ini, `verifyProductPurchase` gagal → pembayaran tidak pernah “lunas” di backend.
   - Rincian: [PANDUAN_SEDERHANA_SETUP_BILLING.md](./PANDUAN_SEDERHANA_SETUP_BILLING.md), [LANGKAH_DAFTAR_GOOGLE_BILLING.md](./LANGKAH_DAFTAR_GOOGLE_BILLING.md).

4. **Smoke test sebelum rilis**
   - Internal test track: satu alur Lacak Driver, Lacak Barang, Kontribusi driver, Pelanggaran (sesuai yang aktif).

---

## Tahap 2 — Validasi server (Cloud Functions)

- **Lacak driver:** `productId` harus sama dengan `traka_lacak_driver_{fee}` untuk `lacakDriverFeeRupiah` dari `app_config/settings`.
- **Kontribusi driver:** nominal SKU ≥ total kewajiban saat ini; total kewajiban tidak boleh melebihi batas pembayaran tunggal (selaras max SKU).
- **Lacak barang:** SKU harus cocok dengan tarif tier **atau** dengan `lacakBarangIapFeeRupiah` di dokumen order (jika ada).
- **Pelanggaran:** nominal SKU ≥ nominal pelanggaran pada record yang dibayar.

Implementasi: `functions/lib/billingValidation.js` + pemanggilan di `functions/index.js` pada callable `verify*`.

---

## Tahap 3 — Data & SKU

- Pesanan **kirim barang** menyimpan `lacakBarangIapFeeRupiah` saat `createOrder` (hitung tier + fee, sama seperti alur pembayaran).
- SKU kontribusi hingga **200k** (tier besar + 150k/200k) — lihat `contribution_driver_screen.dart` dan `MAX_DRIVER_DUES_SINGLE_PURCHASE_RUPIAH` di `functions/lib/billingValidation.js`.

---

## Tahap 4 — Klien

- Layar pembayaran lacak mengaktifkan `PaymentContextService` saat dibuka (konsisten dengan layar kontribusi/pelanggaran).
- Analytics opsional: event saat verifikasi server gagal (`AppAnalyticsService.logPaymentVerifyRejected`).

---

## Urutan deploy yang disarankan

1. Deploy **Cloud Functions** (Tahap 2) — atau bersamaan dengan app jika ada field baru order.
2. Rilis **app** yang menulis `lacakBarangIapFeeRupiah` + SKU baru.
3. Buat produk kontribusi baru di Play Console (mis. **150k / 200k**) **sebelum** rilis app yang mereferensikan ID tersebut.
