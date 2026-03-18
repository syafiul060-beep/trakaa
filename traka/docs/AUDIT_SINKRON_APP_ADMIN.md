# Audit Sinkronisasi: Aplikasi Traka & Web Admin

Dokumen ini memeriksa apakah data dan konfigurasi antara aplikasi Flutter (traka) dan web admin (traka-admin) sudah tersinkron dengan baik.

---

## 1. Ringkasan Status

| Area | Status | Keterangan |
|------|--------|------------|
| **app_config/settings** | ✅ Tersinkron | Admin tulis, app baca – semua field selaras |
| **app_config/admin_contact** | ✅ Tersinkron | Admin tulis, app baca – email, WhatsApp, Instagram |
| **app_config/maintenance** | ✅ Tersinkron | Admin tulis, app baca saat startup |
| **app_config/min_version** | ✅ Tersinkron | Admin tulis, app cek untuk force update |
| **app_config/contribution_exempt_drivers** | ✅ Tersinkron | Admin tulis, Cloud Function & app baca |
| **admin_chats** | ✅ Tersinkron | App & admin baca/tulis – live chat |
| **driver_status** | ⚠️ Hybrid | Firestore atau API – admin harus set VITE_TRAKA_USE_HYBRID |
| **orders** | ✅ Tersinkron | App tulis, admin baca – termasuk kirim_barang |
| **Broadcast** | ✅ Tersinkron | Admin → Cloud Function → FCM topic traka_broadcast |

---

## 2. Detail Per Area

### 2.1 app_config/settings

**Admin Settings** menulis ke `app_config/settings`:
- tarifPerKm, violationFeeRupiah, lacakDriverFeeRupiah
- lacakBarangDalamProvinsiRupiah, lacakBarangBedaProvinsiRupiah, lacakBarangLebihDari1ProvinsiRupiah
- contributionPriceRupiah (legacy)
- minKontribusiTravelRupiah, tarifKontribusiTravelDalamProvinsiPerKm, tarifKontribusiTravelBedaProvinsiPerKm, tarifKontribusiTravelBedaPulauPerKm
- tarifBarangDalamProvinsiPerKm, tarifBarangBedaProvinsiPerKm, tarifBarangLebihDari1ProvinsiPerKm
- tarifBarangDokumenDalamProvinsiPerKm, tarifBarangDokumenBedaProvinsiPerKm, tarifBarangDokumenLebihDari1ProvinsiPerKm

**App** membaca via:
- `AppConfigService` (lacak driver/barang, tarif barang, contribution)
- `OrderService._getTarifPerKm`, `_getViolationFeeRupiah`
- `AppConfigProvider` (tarifPerKm)
- `ViolationService`

**Status**: ✅ Semua field yang admin tulis dibaca oleh app.

---

### 2.2 app_config/admin_contact

**Admin Settings** menulis ke `app_config/admin_contact`:
- adminEmail, adminWhatsApp, adminInstagram

**App** membaca via `AdminContactConfigService`:
- adminEmail, adminWhatsApp, adminInstagram
- Ditampilkan di `AdminContactWidget` (profil driver/penumpang)

**Status**: ✅ Tersinkron. Format WhatsApp dinormalisasi (62 prefix) di kedua sisi.

---

### 2.3 app_config/maintenance & min_version

**Admin Settings** menulis ke:
- `app_config/maintenance` (enabled, message)
- `app_config/min_version` (minVersion)

**App** membaca via:
- `MaintenanceService.check()` – saat startup (sebelum login)
- `AppUpdateService.isUpdateRequired()` – cek versi minimum

**Status**: ✅ Tersinkron. Firestore rules mengizinkan baca maintenance/min_version tanpa auth (untuk startup).

---

### 2.4 app_config/contribution_exempt_drivers

**Admin Settings** menulis `driverUids: [...]` ke `app_config/contribution_exempt_drivers`.

**App & Cloud Functions**:
- Cloud Function `verifyLacakBarangPayment` dll. baca exempt
- Admin Drivers page menampilkan badge "Bebas" untuk driver di daftar

**Status**: ✅ Tersinkron.

---

### 2.5 admin_chats (Live Chat)

**Struktur**: `admin_chats/{userId}` + subcollection `messages`.

**App** (`AdminChatService`):
- User kirim pesan → tulis ke `admin_chats/{userId}/messages`
- Update `admin_chats/{userId}` (lastMessage, lastMessageAt, displayName)
- Stream messages untuk tampilan chat

**Admin** (`Chat.jsx`):
- List chat dari `admin_chats` (orderBy lastMessageAt)
- Stream messages per user
- Admin kirim pesan (senderType: 'admin')
- Set status `connected` saat admin pilih chat
- Tutup chat → status `closed`, pesan bot

**Status**: ✅ Tersinkron. App dan admin memakai struktur yang sama.

---

### 2.6 driver_status (Hybrid)

**Mode Firestore** (default):
- App driver tulis ke `driver_status/{driverId}`
- Admin baca dari Firestore (Drivers, Dashboard, Users)

**Mode Hybrid** (`TRAKA_USE_HYBRID=true`):
- App driver tulis ke API (Redis)
- Firestore `driver_status` tidak di-update
- Admin **harus** set `VITE_TRAKA_API_BASE_URL` dan `VITE_TRAKA_USE_HYBRID=true` di `.env`
- Tanpa ini, halaman Drivers/Dashboard/Users akan kosong (driver_status dari Firestore kosong)

**Status**: ⚠️ Perlu konfigurasi. Jika hybrid aktif di app, admin harus set env yang sama.

---

### 2.7 orders

**App** menulis order (travel & kirim_barang) ke Firestore `orders`.

**Admin**:
- `Orders.jsx` – list order, filter, search, kolom "Kirim Barang" / "Travel"
- `OrderDetail.jsx` – detail order, **termasuk** detail barang (barangCategory, barangNama, berat, dimensi, penerima)

**Status**: ✅ Tersinkron. OrderDetail sudah diperbarui untuk kirim_barang (sesuai REVIEW_KIRIM_BARANG_DAN_DATABASE.md).

---

### 2.8 Broadcast Notifikasi

**Admin** (`Broadcast.jsx`): Memanggil Cloud Function `broadcastNotification` dengan title & body.

**Cloud Function**: Mengirim FCM ke topic `traka_broadcast`.

**App** (`FcmService`): Subscribe ke topic `traka_broadcast` saat init.

**Status**: ✅ Tersinkron.

---

## 3. Checklist Konfigurasi Admin

- [ ] **Firebase**: `.env` dengan config Firebase (API key, project ID, dll.)
- [ ] **User admin**: Tambah `role: "admin"` di `users/{uid}`
- [ ] **app_config/settings**: Minimal `tarifPerKm: 70` (bisa dibuat dari Settings)
- [ ] **app_config/admin_contact**: Bisa dikosongkan (default di kode)
- [ ] **Hybrid mode**: Jika app pakai `TRAKA_USE_HYBRID=true`, set di admin `.env`:
  - `VITE_TRAKA_API_BASE_URL=https://...`
  - `VITE_TRAKA_USE_HYBRID=true`

---

## 4. Potensi Masalah & Rekomendasi

| Item | Risiko | Rekomendasi | Status |
|------|--------|-------------|--------|
| Admin hybrid tidak dikonfigurasi | Drivers/Dashboard kosong saat hybrid aktif | Dokumentasikan di README admin; tambah banner jika `isApiEnabled` tapi API error | - |
| admin_contact stream | App load sekali, tidak real-time | Pakai `AdminContactConfigService.stream()` di widget untuk update tanpa restart | ✅ Ditambahkan |
| Orders CSV export | Kolom "Jenis" lebih mudah dibaca | Tambah kolom `jenis` (Travel/Kirim Barang) di export | ✅ Ditambahkan |

---

## 5. Kesimpulan

**Sinkronisasi secara keseluruhan sudah baik.** Semua data utama (settings, kontak admin, maintenance, chat, orders, broadcast) selaras antara app dan admin.

**Satu hal kritis**: Jika memakai **hybrid mode** (driver_status dari API), pastikan traka-admin dikonfigurasi dengan `VITE_TRAKA_API_BASE_URL` dan `VITE_TRAKA_USE_HYBRID=true`. Tanpa ini, halaman Drivers, Dashboard (driver aktif), dan lokasi driver di Users akan kosong/salah.
