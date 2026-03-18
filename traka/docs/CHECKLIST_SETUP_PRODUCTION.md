# Checklist Setup Production Traka

Panduan singkat untuk memastikan aplikasi siap production.

---

## 1. Codemagic CI/CD

- [ ] **Connect repo** – Codemagic → Add application → pilih repo Traka
- [ ] **Code signing iOS** – Upload Distribution certificate (.p12) dan Provisioning Profile (Ad-hoc + App Store)
- [ ] **Code signing Android** – Upload keystore (jika belum, Codemagic bisa generate)
- [ ] **Environment variables** – Set MAPS_API_KEY, FIREBASE_* jika diperlukan
- [ ] **Jalankan workflow** – `traka-test` untuk cek tes otomatis tiap push

---

## 2. Produk IAP (Google Play Console)

Pastikan produk berikut ada dan aktif:

| Product ID | Harga | Tipe |
|------------|-------|------|
| `traka_contribution_once` | Rp 7.500 | Managed |
| `traka_lacak_driver` | Rp 3.000 | Consumable |
| `traka_lacak_barang_10000` | Rp 10.000 | Consumable |
| `traka_lacak_barang_15000` | Rp 15.000 | Consumable |
| `traka_lacak_barang_25000` | Rp 25.000 | Consumable |
| `traka_violation_fee_5k` | Rp 5.000 | Consumable |

Detail: `docs/LANGKAH_DAFTAR_GOOGLE_BILLING.md`

---

## 3. Environment Variables (Build)

Saat build Flutter:

```bash
flutter build apk --release \
  --dart-define=MAPS_API_KEY=xxx
```

Untuk hybrid + certificate pinning:

```bash
--dart-define=TRAKA_USE_HYBRID=true \
--dart-define=TRAKA_API_BASE_URL=https://... \
--dart-define=TRAKA_API_CERT_SHA256=AA:BB:...
```

---

## 4. Web Admin

- [ ] Deploy ke `traka-admin.web.app` (`npm run deploy` di folder traka-admin)
- [ ] Tambah domain ke Firebase Auth → Authorized domains
- [ ] Set user dengan `role: "admin"` di Firestore
- [ ] Jika hybrid: set `VITE_TRAKA_API_BASE_URL` dan `VITE_TRAKA_USE_HYBRID=true` di .env

---

## 5. Firebase

- [ ] Deploy Firestore rules: `firebase deploy --only firestore`
- [ ] Deploy Cloud Functions: `firebase deploy --only functions`
- [ ] Pastikan `app_config/settings` ada (minimal `tarifPerKm: 70`)

---

## 6. Verifikasi Cepat

- [ ] `flutter test` → 48 tests passed
- [ ] `flutter analyze` → no issues
- [ ] Build APK berhasil
- [ ] Login & flow order berjalan di device
