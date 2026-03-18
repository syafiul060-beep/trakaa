# Update Versi Google Play (Tanpa Kehilangan Progress Pengujian Tertutup)

Panduan untuk mengupdate versi aplikasi di Google Play Console tanpa kehilangan penguji dan progress pengujian tertutup.

**Versi saat ini (pubspec.yaml):** 1.0.6+7

---

## ⚠️ 12 Penguji Jangan Sampai Hilang

**Yang HARUS dihindari:**
- ❌ Jangan buat track pengujian baru
- ❌ Jangan hapus daftar penguji
- ❌ Jangan ganti/keluar dari track yang sama dengan 1.0.5

**Yang AMAN dilakukan:**
- ✅ Buat rilis baru di track **yang sama** (Alpha/Pengujian tertutup)
- ✅ Upload AAB baru saja – daftar penguji tetap otomatis
- ✅ 12 penguji tetap terdaftar, hanya dapat update versi baru

---

## Yang TIDAK Hilang Saat Update

- **12 penguji** – tetap di daftar penguji
- **Progress 14 hari** – tetap berjalan (track yang sama)
- **Daftar email penguji** – tidak berubah

Yang berubah hanya **versi aplikasi** di track tersebut.

---

## Langkah 1: Build AAB

Jalankan di terminal dari folder `traka`:

```bash
flutter build appbundle --release --build-name=1.0.6 --build-number=7
```

File AAB akan tersedia di: `build/app/outputs/bundle/release/app-release.aab`

> **Catatan:** Pastikan `build-name` dan `build-number` di atas sesuai dengan `pubspec.yaml` (format: `versionName+versionCode`). Untuk versi berikutnya, naikkan versionCode (misalnya 1.0.7+8).

---

## Langkah 2: Upload ke Google Play Console

1. Buka [Google Play Console](https://play.google.com/console/) → pilih **Traka**
2. Menu kiri: **Uji dan rilis** → **Pengujian** → **Pengujian tertutup**
3. Pilih track **yang sama** dengan versi 1.0.5 (misalnya Alpha) – **bukan buat track baru**
4. Klik **Buat rilis baru** (Create new release) – ini menambah rilis di track yang sama, 12 penguji tetap
5. **Unggah** file `app-release.aab`
6. Isi **Catatan rilis** (Release notes), contoh:

   ```
   Versi 1.0.6:
   - Opsi panggilan telepon biasa di chat
   - Notifikasi pembayaran untuk Lacak Driver & Kontribusi
   - Riwayat pembayaran kontribusi driver
   - Perbaikan keamanan dan error handling
   ```

7. Klik **Simpan** → **Tinjau rilis** → **Mulai rollout ke Pengujian tertutup - Alpha**

---

## Langkah 3: Verifikasi Penguji

1. Di halaman **Pengujian tertutup - Alpha**, buka tab **Penguji**
2. Pastikan daftar penguji tidak berubah
3. **Jangan** hapus atau ganti daftar penguji

---

## Yang Terjadi Setelah Rilis

| Aspek              | Status                                      |
|--------------------|---------------------------------------------|
| Daftar penguji     | Tetap sama                                  |
| Progress 14 hari   | Tetap berjalan (tidak direset)              |
| Versi di track     | Berubah (misalnya 1.0.5 → 1.0.6)            |
| Penguji            | Mendapat update via Play Store otomatis     |

---

## Catatan Penting

1. **Jangan buat track baru** – gunakan track **Alpha** yang sudah ada
2. **Jangan hapus rilis lama** – cukup tambah rilis baru; rilis lama akan digantikan otomatis
3. **versionCode harus naik** – setiap rilis baru harus punya versionCode lebih besar dari sebelumnya
4. **Progress 14 hari** – Google menghitung dari track, bukan dari versi. Selama track sama, progress tetap berjalan

---

## Cek Progress Setelah Update

1. Buka **Dasbor** di Play Console
2. Lihat bagian **"Menjalankan pengujian tertutup dengan minimal 12 penguji, selama minimal 14 hari"**
3. Angka hari seharusnya tetap bertambah (2 → 3 → 4 … sampai 14)

---

## Referensi Versi

Lihat [CHANGELOG.md](../CHANGELOG.md) untuk daftar perubahan tiap versi.
