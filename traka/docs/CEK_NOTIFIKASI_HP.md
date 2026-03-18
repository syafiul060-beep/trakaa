# Cek Notifikasi ke HP

Panduan memastikan notifikasi push berfungsi di aplikasi Traka.

## Alur Notifikasi

1. **FcmService.init()** – dipanggil saat app start (`_initInBackground`)
   - Minta izin notifikasi (Firebase)
   - Setup background handler
   - Setup local notifications

2. **saveTokenForUser(uid)** – dipanggil setelah login berhasil
   - Simpan `fcmToken` ke Firestore `users/{uid}`
   - Subscribe ke topic `traka_broadcast`

3. **Cloud Functions** – kirim FCM ke `fcmToken` saat event:
   - Chat baru → `onChatMessageCreated`
   - Order baru → `onOrderCreated`
   - Kesepakatan → `onPassengerAgreed`
   - Pembatalan → `onOrderCancellationUpdate`
   - Bayar kontribusi/pelanggaran → `sendPaymentReminderFcm`

## Cek Notifikasi Berfungsi

### 1. Izin notifikasi
- Buka **Pengaturan** HP → **Aplikasi** → **Traka** → **Notifikasi**
- Pastikan notifikasi **diaktifkan**

### 2. Token FCM tersimpan
- Buka Firestore Console → `users/{uid}`
- Pastikan ada field `fcmToken` (string panjang)
- Jika kosong: logout lalu login lagi, atau reinstall app

### 3. Channel Android
- App membuat channel `traka_chat` dan `traka_payment_channel` saat init
- Pastikan `RouteNotificationService.init()` berjalan (dipanggil di `_initInBackground`)

### 4. Test notifikasi
- Kirim pesan chat dari akun lain ke order yang sama
- Atau gunakan **Broadcast Notifikasi** di Admin (jika ada)

### 5. Notifikasi tidak muncul saat layar mati

**Gejala:** Notifikasi baru muncul setelah layar dinyalakan/dibuka, tidak saat layar masih mati.

**Penyebab:** Android Doze mode dan penghemat baterai OEM (Xiaomi, Samsung, Oppo, Vivo, dll.) menunda atau memblokir notifikasi saat layar mati.

**Solusi untuk pengguna:**
1. **Pengaturan → Aplikasi → Traka → Baterai**
   - Pilih **Tidak dibatasi** / **Unrestricted** / **Don't optimize**
   - Atau: **Izinkan aktivitas di latar belakang**
2. **Pengaturan → Aplikasi → Traka → Notifikasi**
   - Pastikan notifikasi **diaktifkan**
   - Aktifkan **Tampilkan di layar kunci** (jika ada)
3. **Xiaomi/MIUI:** Pengaturan → Aplikasi → Traka → Otonomi baterai → **Tanpa batasan**
4. **Samsung (termasuk A30, A50, dll.):**
   - Pengaturan → Aplikasi → Traka → **Baterai** → **Tidak dibatasi**
   - Jika ada **"Aplikasi tidur"** / **Sleeping apps**: pastikan Traka TIDAK ada di daftar (hapus jika ada)
   - Device Care → Baterai → Penggunaan baterai aplikasi → Traka → **Tidak dibatasi**
5. **Oppo/Realme/ColorOS:** Pengaturan → Baterai → Penghemat baterai aplikasi → Traka → **Izinkan di latar belakang**

**Perbaikan di kode (sudah diterapkan):**
- FCM: `visibility: "public"` dan `priority: "max"` agar notifikasi tampil di lockscreen
- Channel: `Importance.max` dan `NotificationVisibility.public` untuk notifikasi lokal

## Perbaikan: Notifikasi Palsu "Pesan baru"

**Masalah:** Penumpang kadang dapat notifikasi "Pesan baru" / "ada pesan baru", tapi saat diklik chat kosong.

**Penyebab:** Cloud Function mengirim notifikasi untuk pesan dengan konten kosong atau tipe tidak dikenal.

**Perbaikan:** `onChatMessageCreated` sekarang **tidak mengirim FCM** jika:
- `notificationText` kosong
- `notificationText` = "Pesan baru" (fallback untuk konten tidak bermakna)

Order tetap di-update (`lastMessageAt`, dll) untuk badge, tapi notifikasi push tidak dikirim.

## Deploy

Setelah perubahan di `functions/index.js`:

```bash
cd traka/functions
firebase deploy --only functions:onChatMessageCreated
```
