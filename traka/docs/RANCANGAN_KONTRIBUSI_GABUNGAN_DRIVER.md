# Rancangan: Pembayaran Gabungan Driver (Kontribusi + Pelanggaran)

## Ringkasan

Driver membayar **sekali** untuk:
1. **Kontribusi** (travel + kirim barang jika diterapkan)
2. **Pelanggaran** (denda tidak scan barcode, jika ada)

---

## Situasi Saat Ini

| Item | Siapa bayar | Alur |
|------|-------------|------|
| Kontribusi travel | Driver | Per 1× kapasitas mobil via `traka_contribution_once` |
| Kontribusi kirim barang | - | Belum ada |
| Pelanggaran penumpang | Penumpang | Via `ViolationPayScreen` → `traka_violation_fee_5k` |
| Pelanggaran driver | - | Dicatat di `violation_records` (type: driver) tapi **belum** ada `outstandingViolationFee` di users |

**Catatan:** Saat ini pelanggaran driver tidak menambah `outstandingViolationFee` di `users`. Hanya penumpang yang punya outstanding dan bayar via ViolationPayScreen.

---

## Rancangan Baru

### 1. Pelanggaran Driver → outstandingViolationFee

Saat driver dapat pelanggaran (tidak scan), update `users/{driverUid}`:
- `outstandingViolationFee` += violationFeeRupiah
- `outstandingViolationCount` += 1

(Sama seperti penumpang.)

### 2. Kontribusi Kirim Barang (Driver)

- **Per km** (bukan per order): `jarak_efektif × tarifBarangPerKm` (tier provinsi 15/35/50 Rp/km)
- Counter: `totalBarangContributionRupiah` (akumulasi dari setiap order kirim_barang selesai)
- Yang belum dibayar: `totalBarangContributionRupiah - contributionBarangPaidUpToRupiah`
- Config: `app_config/settings` → `tarifBarangDalamProvinsiPerKm`, `tarifBarangBedaProvinsiPerKm`, `tarifBarangLebihDari1ProvinsiPerKm`

### 3. Pembayaran Gabungan (Sekali Bayar, Tidak Berulang)

**Prinsip:** Driver bayar **sekali** saat layar kontribusi muncul. Semua kewajiban (travel + kirim barang + pelanggaran) dibayar bersamaan agar driver tidak berulang-ulang bayar.

**Layar:** `ContributionDriverScreen`

**Kapan layar muncul (driver wajib bayar):**
- Kontribusi travel: `totalPenumpangServed >= contributionPaidUpToCount + capacity` **ATAU**
- Kontribusi kirim barang: `totalBarangContributionRupiah > contributionBarangPaidUpToRupiah` **ATAU**
- Pelanggaran: `outstandingViolationFee > 0`

**Rincian yang ditampilkan:**
```
Kontribusi travel      : Rp 7.500   (1× kapasitas) [jika ada]
Kontribusi kirim barang: Rp 12.000   (jarak × tarif per km, tier provinsi) [jika ada]
Denda pelanggaran      : Rp 5.000   [jika ada]
────────────────────────────────────
Total                  : Rp 24.500
```

**Alur pembayaran:**
1. Hitung total = kontribusi travel + unpaidBarangRupiah + outstandingViolationFee
2. Pilih produk IAP yang sesuai total
3. Driver bayar **sekali**
4. Cloud Function `verifyContributionPayment`:
   - Update `contributionPaidUpToCount` = totalPenumpangServed
   - Update `contributionBarangPaidUpToRupiah` = totalBarangContributionRupiah
   - Update `outstandingViolationFee` = 0, `outstandingViolationCount` = 0
   - Tandai violation_records (type: driver) sebagai paid

**Hasil:** Driver tidak perlu bayar berulang—satu pembayaran membersihkan semua kewajiban.

### 4. Produk IAP untuk Pembayaran Gabungan

Google Play membutuhkan harga tetap per produk. Opsi:

**Opsi A: Produk per nominal**
- `traka_driver_dues_7500` (kontribusi saja)
- `traka_driver_dues_12500` (kontribusi + 1 violation)
- `traka_driver_dues_17500` (kontribusi + 2 violations)
- `traka_driver_dues_20000`
- dst.

**Opsi B: Tetap pakai produk terpisah, tapi UX gabung**
- Kontribusi: `traka_contribution_once` (Rp 7.500)
- Violation: `traka_violation_fee_5k` (Rp 5.000)
- Di layar: tampilkan total, driver bisa bayar 2× berturut-turut (kontribusi dulu, lalu violation) dalam satu flow
- Atau: satu tombol "Bayar Rp 12.500" yang trigger 2 pembelian (jika Play Billing mendukung)

**Opsi C (Disarankan): Produk combined untuk nominal umum**
- Buat produk: `traka_driver_dues_{amount}` untuk amount: 7500, 12500, 15000, 17500, 20000, 25000
- Saat total dihitung, pilih produk terdekat (bulatkan ke atas)
- Contoh: total Rp 13.000 → pakai `traka_driver_dues_15000`, "kelebihan" Rp 2.000 bisa dianggap toleransi atau credit

---

## File yang Perlu Diubah

| File | Perubahan |
|------|-----------|
| `order_service.dart` | Tambah increment `outstandingViolationFee` + `outstandingViolationCount` untuk driver saat violation |
| `order_service.dart` / Cloud Function | Increment `totalBarangContributionRupiah` (tripBarangFareRupiah) saat order kirim_barang completed |
| `driver_contribution_service.dart` | Status kontribusi kirim barang (Rupiah), outstanding violation |
| `contribution_driver_screen.dart` | Tampilkan rincian gabungan, hitung total, pilih produk IAP |
| `functions/index.js` | `verifyContributionPayment` |
| `app_config/settings` | `tarifBarangDalamProvinsiPerKm`, `tarifBarangBedaProvinsiPerKm`, `tarifBarangLebihDari1ProvinsiPerKm` |
| `users` collection | `totalBarangContributionRupiah`, `contributionBarangPaidUpToRupiah` |

---

## Keputusan

- **Kontribusi kirim barang:** Per km (jarak × tarif tier 15/35/50 Rp/km), bukan per order tetap
- **Pembayaran:** Gabung dalam satu kali bayar saat layar kontribusi muncul—driver tidak berulang-ulang bayar

---

## Pertanyaan Tersisa

1. **Produk IAP:** Opsi A (produk per nominal) atau Opsi C (produk combined untuk nominal umum)?
2. **Penumpang:** Tetap bayar violation terpisah via ViolationPayScreen.

---

---

## Status: ✅ Implementasi Selesai

**Produk IAP yang perlu dibuat di Play Console (selain `traka_contribution_once`):**
- `traka_driver_dues_12500` (Rp 12.500)
- `traka_driver_dues_15000` (Rp 15.000)
- `traka_driver_dues_17500` (Rp 17.500)
- `traka_driver_dues_20000` (Rp 20.000)
- `traka_driver_dues_25000` (Rp 25.000)
- `traka_driver_dues_30000` (Rp 30.000)

**Config di Admin Settings:**
- `contributionPriceRupiah` (default 7500)
- `tarifBarangDalamProvinsiPerKm` (default 15)
- `tarifBarangBedaProvinsiPerKm` (default 35)
- `tarifBarangLebihDari1ProvinsiPerKm` (default 50)
