# Konfigurasi Firestore untuk Kontribusi Optimal

Panduan update `app_config/settings` agar kontribusi memakai tarif baru (90/110/140) dan batas max per rute.

---

## 1. Via Firebase Console (Manual)

1. Buka [Firebase Console](https://console.firebase.google.com) → pilih project **syafiul-traka**
2. Menu **Firestore Database** → buka collection `app_config`
3. Klik dokumen **`settings`** (atau buat jika belum ada)
4. Tambah atau edit field berikut:

| Field | Tipe | Nilai |
|-------|------|-------|
| `minKontribusiTravelRupiah` | number | 5000 |
| `maxKontribusiTravelPerRuteRupiah` | number | 30000 |
| `tarifKontribusiTravelDalamProvinsiPerKm` | number | 90 |
| `tarifKontribusiTravelBedaProvinsiPerKm` | number | 110 |
| `tarifKontribusiTravelBedaPulauPerKm` | number | 140 |

5. Klik **Update**

---

## 2. Via Script (Opsional)

Jalankan dari folder `functions` (perlu `serviceAccountKey.json`):

```bash
cd d:\Traka\traka\functions
node scripts/update-app-config-contribution.js
```

**Catatan:** Jika belum punya `serviceAccountKey.json`, buat dari Firebase Console → Project Settings → Service Accounts → Generate new private key, simpan di `traka/functions/`.

---

## 3. Field yang Diupdate

| Field | Sebelum (default) | Sesudah |
|-------|-------------------|---------|
| `minKontribusiTravelRupiah` | 5000 | 5000 (tetap) |
| `maxKontribusiTravelPerRuteRupiah` | - | 30000 (baru) |
| `tarifKontribusiTravelDalamProvinsiPerKm` | 100 | 90 |
| `tarifKontribusiTravelBedaProvinsiPerKm` | 120 | 110 |
| `tarifKontribusiTravelBedaPulauPerKm` | 150 | 140 |

---

## 4. Verifikasi

Setelah update, buka app dan cek:

- **Detail Rute** → kontribusi per order tampil dengan tarif baru
- **Bayar Kontribusi** → dialog tarif menampilkan 90/110/140 Rp/km, max Rp 30.000

---

## 5. Catatan

- Field yang tidak diisi akan memakai **default di kode** (app_config_service.dart)
- Tidak perlu hapus field lain di `settings` (lacakBarang, violationFee, dll.)
