# Audit Kesiapan Produksi – Traka untuk Seluruh Pengguna Indonesia

Dokumen ini menilai kesiapan aplikasi Traka untuk produksi skala nasional Indonesia, keamanan, database, dan saran perbaikan sebelum peluncuran.

---

## 1. Ringkasan Eksekutif

| Aspek | Status | Catatan |
|-------|--------|---------|
| **Kesiapan Produksi** | ⚠️ Hampir siap | Perlu perbaikan keamanan Storage & Firestore |
| **Keamanan Aplikasi** | ⚠️ Baik dengan catatan | App Check aktif, ada celah Storage |
| **Keamanan Database** | ⚠️ Baik dengan catatan | Firestore rules umumnya baik; counters & vehicle_brands perlu dibatasi |
| **Skalabilitas** | ✅ Cukup | Firebase/Firestore mendukung skala besar |

---

## 2. Yang Sudah Baik (Siap Produksi)

### 2.1 Keamanan

- **Firebase App Check** aktif (`ENFORCE_APP_CHECK = true`) – hanya app resmi yang bisa akses Firebase
- **Rate limiting** – verifikasi kode: max 3 per email per 15 menit
- **Device rate limit** – login dibatasi via Cloud Function (anti brute-force)
- **Firestore rules** – sebagian besar collection dibatasi per user (users, orders, driver_status, dll.)
- **Verification codes** – hanya Cloud Function yang akses; client tidak bisa baca/tulis langsung
- **contribution_payments, scan_audit_log** – hanya Cloud Function yang tulis; client tidak bisa manipulasi
- **Sensitive env** – GMAIL_*, GOOGLE_PLAY_SERVICE_ACCOUNT_KEY via environment variables, tidak di kode

### 2.2 Database

- **Struktur Firestore** – collection terpisah jelas (users, orders, driver_status, route_sessions, dll.)
- **Index** – ada panduan untuk index yang diperlukan
- **app_config** – maintenance & min_version bisa dibaca tanpa auth (untuk cek update paksa)

### 2.3 Aplikasi

- **L10n** – dukungan Bahasa Indonesia & Inggris
- **Error handling** – logError + Crashlytics untuk debugging produksi
- **Fake GPS detection** – proteksi lokasi palsu
- **Pembayaran** – verifikasi server-side via Google Play Developer API

---

## 3. Celah Keamanan yang Perlu Diperbaiki

### 3.1 🔴 KRITIS: Storage Rules – Chat Media

**Masalah:**  
`storage.rules` untuk `chat_audio`, `chat_images`, `chat_videos` mengizinkan:

```
allow read, write: if request.auth != null;
```

Artinya **semua user yang login** bisa membaca/menulis file chat **order mana pun** jika tahu `orderId`. Data suara, gambar, dan video chat bisa diakses oleh pihak yang tidak berhak.

**Saran:**  
Validasi bahwa user adalah peserta order (penumpang, driver, atau penerima) sebelum akses. Firestore tidak bisa dipanggil dari Storage rules, jadi opsi:

1. **Cloud Function** – upload/download lewat Cloud Function yang cek keanggotaan order di Firestore
2. **Custom token / signed URL** – generate URL dengan expiry, validasi di Function
3. **Struktur path** – gunakan path yang sulit ditebak (UUID panjang) + validasi di app; tetap ada risiko jika orderId bocor

**Rekomendasi:** Opsi 1 (Cloud Function) paling aman untuk produksi.

---

### 3.2 🟡 SEDANG: Firestore – Counters

**Masalah:**  
`counters` collection: `allow read, write: if request.auth != null;`

Setiap user login bisa menulis ke `counters` (termasuk `order_number`, `route_journey_number`). Risiko: manipulasi nomor pesanan, nomor rute.

**Saran:**  
- Pindahkan increment counter ke **Cloud Function** (transaction server-side)
- Atau: `allow write: if false;` dan pakai Admin SDK hanya dari Cloud Function
- Client memanggil callable function untuk generate nomor

---

### 3.3 🟡 SEDANG: Firestore – vehicle_brands

**Masalah:**  
`vehicle_brands`: `allow write: if request.auth != null;`

Semua user bisa mengubah data merek/tipe mobil.

**Saran:**  
`allow write: if isAdmin();` – hanya admin yang boleh edit.

---

### 3.4 🟢 RENDAH: API Key di firebase_options.dart

**Masalah:**  
API key Firebase ter-expose di kode (umum di Flutter). Bisa disalahgunakan jika key tidak dibatasi.

**Mitigasi yang ada:**  
- App Check membatasi request ke Firebase
- Dokumen SETUP_APP_CHECK merekomendasikan restrict API key di Google Cloud Console (package name, SHA)

**Saran:**  
Pastikan di Google Cloud Console:
- Application restrictions: Android/iOS package + SHA
- API restrictions: hanya API yang dipakai (Firebase, Maps, dll.)

---

## 4. Kesiapan Database

| Item | Status | Keterangan |
|------|--------|------------|
| Firestore rules | ⚠️ | Umumnya baik; counters & vehicle_brands perlu diperketat |
| Storage rules | 🔴 | Chat media perlu validasi peserta order |
| Index | ✅ | Ada panduan; deploy saat ada error "index required" |
| Backup | ⚠️ | Firestore punya point-in-time recovery (opsional, berbayar); pastikan aktif jika kritis |
| app_config/settings | ✅ | Wajib ada; script update tersedia |

---

## 5. Kepatuhan Regulasi Indonesia

| Regulasi | Status | Catatan |
|----------|--------|---------|
| **UU ITE** | ⚠️ | Konten user (chat, foto) – pastikan ada mekanisme laporan & takedown |
| **UU PDP** | ⚠️ | Data pribadi (nama, email, telepon, lokasi) – perlu kebijakan privasi & persetujuan |
| **Peraturan transportasi** | ⚠️ | Traka sebagai penghubung, bukan operator – pastikan ToS jelas |

**Saran:**  
- Pastikan **Privacy Policy** dan **Terms of Service** tersedia dan diakses user
- Pertimbangkan mekanisme **data export** dan **penghapusan akun** sesuai UU PDP

---

## 6. Skalabilitas untuk Seluruh Indonesia

| Aspek | Keterangan |
|-------|------------|
| **Firebase/Firestore** | Mendukung skala besar; auto-scaling |
| **Cloud Functions** | Cold start bisa lambat; pertimbangkan min instances jika traffic tinggi |
| **Geocoding** | Saat ini native + monitoring; 4_TAHAP_GEOCODING Tahap 2–4 untuk cakupan lebih baik |
| **Maps** | Google Maps; kuota perlu dipantau |

---

## 7. Checklist Sebelum Produksi

### Wajib

- [ ] **Perbaiki Storage rules** – chat media hanya untuk peserta order
- [ ] **Perketat counters** – hanya Cloud Function yang tulis
- [ ] **Perketat vehicle_brands** – hanya admin yang tulis
- [ ] **Pastikan env vars** – GOOGLE_PLAY_SERVICE_ACCOUNT_KEY, GMAIL_EMAIL, GMAIL_APP_PASSWORD
- [ ] **app_config/settings** – field tarif & fee terisi
- [ ] **Produk Play Console** – in-app products dibuat & service account di-invite
- [ ] **Restrict API key** – di Google Cloud Console

### Disarankan

- [ ] **Privacy Policy & ToS** – tersedia dan linked di app
- [ ] **Backup Firestore** – aktifkan jika data kritis
- [ ] **Monitoring** – Firebase Performance, Crashlytics, usage quota
- [ ] **Staging environment** – testing sebelum produksi

### Opsional

- [ ] **Certificate pinning** – untuk API kritis (docs/TAHAP_6_CERTIFICATE_PINNING_CI.md)
- [ ] **Geocoding Tahap 2–4** – fallback API, Places Autocomplete (4_TAHAP_GEOCODING.md)

---

## 8. Kesimpulan

**Apakah siap produksi untuk seluruh pengguna Indonesia?**

**Belum sepenuhnya.** Aplikasi punya fondasi keamanan yang baik (App Check, rate limit, Firestore rules umum), tetapi ada celah yang harus ditutup:

1. **Storage rules** – risiko kebocoran data chat (suara, gambar, video)
2. **counters** – risiko manipulasi nomor pesanan/rute
3. **vehicle_brands** – risiko perubahan data referensi oleh user biasa

Setelah ketiga hal di atas diperbaiki dan checklist wajib terpenuhi, aplikasi **dapat dianggap siap** untuk peluncuran bertahap (soft launch) dengan pemantauan ketat. Untuk skala penuh seluruh Indonesia, selesaikan juga item disarankan (Privacy Policy, backup, monitoring).

---

## 9. Referensi

- `firestore.rules` – aturan Firestore
- `storage.rules` – aturan Storage
- `docs/SETUP_APP_CHECK_DAN_ANTI_CLONING.md` – App Check
- `docs/CHECKLIST_SEMUA_PENGATURAN.md` – konfigurasi
- `docs/PERUBAHAN_KEAMANAN_DAN_PERBAIKAN.md` – riwayat keamanan
