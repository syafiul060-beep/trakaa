# Play Console Warnings & Perbaikan

Dokumen ini mencatat peringatan dari Google Play Console dan langkah perbaikan yang telah/telah direncanakan.

---

## 1. SafetyNet Deprecation (play-services-safetynet)

**Peringatan:** SafetyNet Attestation API dan SafetyNet reCAPTCHA API telah digantikan oleh Play Integrity API dan reCAPTCHA.

**Status:** ✅ Diperbaiki (versi 1.0.9)

**Langkah yang dilakukan:**
- Firebase App Check sudah menggunakan `AndroidProvider.playIntegrity` (lihat `main.dart`)
- Menambahkan `exclude` untuk `play-services-safetynet` di `android/app/build.gradle.kts` agar dependency lama tidak ikut terbundle

**Catatan:** Firebase Auth untuk phone verification sudah menggunakan Play Integrity secara default. Jika muncul error saat kirim OTP, cek konfigurasi Firebase Console (App Check, Play Integrity).

---

## 2. Layar Penuh / Edge-to-Edge (Android 15, SDK 35)

**Peringatan:** Mulai Android 15, aplikasi yang menargetkan SDK 35 akan menampilkan tata letak layar penuh secara default. Aplikasi harus menangani inset dengan benar.

**Status:** 📋 Dijadwalkan untuk rilis mendatang

**Langkah yang direncanakan:**
- Tambahkan `enableEdgeToEdge()` di `MainActivity` (Kotlin) atau `EdgeToEdge.enable()` (Java)
- Pastikan UI menangani system insets (status bar, navigation bar) dengan benar
- Testing di perangkat Android 15+

**Referensi:** [Android Edge-to-Edge](https://developer.android.com/develop/ui/views/layout/edge-to-edge)

---

## 3. Izin Foto & Video (READ_MEDIA_IMAGES, READ_MEDIA_VIDEO)

**Status:** ✅ Diperbaiki (versi 1.0.7+)

**Langkah yang dilakukan:**
- Menghapus `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO` dari manifest dengan `tools:node="remove"`
- Menggunakan system photo picker (image_picker) untuk pemilihan foto/video

---

## Riwayat Rilis

| Versi   | Perbaikan |
|---------|-----------|
| 1.0.7   | Izin foto/video (hapus READ_MEDIA_*) |
| 1.0.8   | Rilis produksi |
| 1.0.9   | Exclude play-services-safetynet |
