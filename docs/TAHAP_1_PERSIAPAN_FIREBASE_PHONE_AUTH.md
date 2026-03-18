# Tahap 1: Persiapan Firebase untuk Phone Auth (Gojek/Grab Style)

Checklist untuk mempersiapkan Firebase agar **Phone + OTP** bisa dipakai sebagai metode utama daftar dan login.

---

## Ringkasan Tahap 1

| # | Langkah | Status | Keterangan |
|---|---------|--------|------------|
| 1.1 | Aktifkan Phone Sign-In | ☐ | Firebase Console |
| 1.2 | Upgrade ke Blaze Plan | ☐ | Untuk quota SMS |
| 1.3 | Tambah SHA-1 & SHA-256 (Android) | ☐ | Wajib untuk OTP production |
| 1.4 | Download ulang google-services.json | ☐ | Setelah tambah SHA |
| 1.5 | Aktifkan Play Integrity API | ☐ | Google Cloud Console |
| 1.6 | Nomor uji (opsional) | ☐ | Untuk development tanpa SMS |
| 1.7 | Konfigurasi iOS (jika pakai) | ☐ | APNs, Info.plist |

---

## 1.1 Aktifkan Phone Sign-In

1. Buka [Firebase Console](https://console.firebase.google.com/) → pilih project **Traka**
2. Menu kiri: **Authentication** → tab **Sign-in method**
3. Klik **Phone** → nyalakan **Enable** → **Save**

> Jika sudah aktif (karena login OTP profil), lewati langkah ini.

---

## 1.2 Upgrade ke Blaze Plan (Pay-as-you-go)

Phone Auth mengirim SMS. Quota gratis terbatas; untuk production perlu Blaze.

1. Firebase Console → **Project settings** (ikon roda) → **Usage and billing**
2. Klik **Modify plan** atau **Upgrade**
3. Pilih **Blaze** → set **budget alert** (misalnya $10/bulan) agar tidak kaget
4. Selesaikan pembayaran (kartu kredit/debit)

> Tanpa Blaze, OTP bisa berhenti setelah quota gratis habis.

---

## 1.3 Tambah SHA-1 & SHA-256 (Android)

Tanpa ini, error seperti *"missing app identifier"* atau *"Play Integrity"* sering muncul.

### Ambil SHA dari terminal

```powershell
cd d:\Traka\traka\android
.\gradlew.bat signingReport
```

> Di Windows pakai `gradlew.bat`; di Mac/Linux pakai `./gradlew`.

### Atau via Android Studio

1. Buka project di **Android Studio**
2. **Gradle** (panel kanan) → **traka** → **app** → **Tasks** → **android**
3. Double-click **signingReport**
4. Lihat output di **Run** panel

### Salin nilai

- **SHA-1** (debug dan release)
- **SHA-256** (debug dan release)

### Tambah ke Firebase

1. Firebase Console → **Project settings** (ikon roda)
2. Tab **General** → gulir ke **Your apps**
3. Pilih aplikasi **Android** (package: `com.example.traka` atau sesuai)
4. Klik **Add fingerprint**
5. Tempel **SHA-1** → **Save**
6. Klik **Add fingerprint** lagi → tempel **SHA-256** → **Save**

---

## 1.4 Download Ulang google-services.json

Setelah menambah SHA, file `google-services.json` harus diunduh ulang.

1. Firebase Console → **Project settings** → **General**
2. Di **Your apps** → kartu **Android** → **Download google-services.json**
3. Ganti file di: `d:\Traka\traka\android\app\google-services.json`
4. Jalankan: `flutter clean` lalu `flutter pub get`

---

## 1.5 Aktifkan Play Integrity API

1. Buka [Google Cloud Console](https://console.cloud.google.com/)
2. Pilih project yang **sama** dengan Firebase (biasanya auto-linked)
3. **APIs & Services** → **Library**
4. Cari **Google Play Integrity API** → **Enable**

---

## 1.6 Nomor Uji (Opsional – Development)

Untuk development tanpa mengonsumsi SMS sungguhan:

1. Firebase Console → **Authentication** → **Sign-in method** → **Phone**
2. Gulir ke **Phone numbers for testing**
3. **Add phone number**: misalnya `+6281234567890` dengan kode `123456`
4. Simpan

> Login/daftar dengan nomor itu akan dapat kode `123456` tanpa kirim SMS.

---

## 1.7 Konfigurasi iOS (Jika Pakai iPhone)

Jika deploy ke iOS:

1. **Firebase Console** → **Project settings** → **Your apps** → **Add app** → **iOS**
2. Isi **Bundle ID** (dari `ios/Runner.xcodeproj` atau `Info.plist`)
3. Download **GoogleService-Info.plist** → taruh di `ios/Runner/`
4. **APNs**: upload key/certificate di Firebase Console (untuk notifikasi; OTP bisa jalan tanpa ini di simulator)

---

## Verifikasi

Setelah semua selesai:

1. **Uji di HP Android asli** (bukan emulator):
   - Buka app → Login → pilih "Login dengan No. Telepon"
   - Masukkan nomor (atau nomor uji) → Kirim kode
   - Pastikan OTP terkirim atau auto-verify

2. Jika gagal, cek:
   - SHA sudah ditambah dan `google-services.json` sudah diunduh ulang
   - Play Integrity API sudah diaktifkan
   - Uji di perangkat fisik, bukan emulator

---

## Referensi

- [FIREBASE_OTP_LANGKAH.md](./FIREBASE_OTP_LANGKAH.md) – panduan OTP lebih detail
- [FIREBASE_DAN_SETUP.md](./FIREBASE_DAN_SETUP.md) – setup Firebase umum

---

## Status Tahap 1

Centang setelah selesai:

- [ ] 1.1 Phone Sign-In enabled
- [ ] 1.2 Blaze plan (jika production)
- [ ] 1.3 SHA-1 & SHA-256 ditambah
- [ ] 1.4 google-services.json diunduh ulang
- [ ] 1.5 Play Integrity API enabled
- [ ] 1.6 Nomor uji (opsional)
- [ ] 1.7 iOS (jika perlu)
- [ ] Verifikasi: OTP berhasil di HP asli

**Tahap 1 selesai** → lanjut ke [Tahap 2: Cloud Functions](TAHAP_2_CLOUD_FUNCTIONS_PHONE_AUTH.md)
