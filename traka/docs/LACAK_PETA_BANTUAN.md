# Bantuan ringkas: Lacak Driver & Lacak Kirim Barang (peta)

Dokumen ini untuk QA dan pengguna internal: apa yang perlu GPS + data, dan apa yang tampil di peta.

## Lacak Driver (penumpang travel)

- **Ikon**: pin oranye = lokasi Anda sesuai pesanan (bukan titik biru GPS perangkat); mobil = posisi driver.
- **Kamera**: otomatis membingkai Anda dan driver (zoom mengikuti jarak).
- **Data & API**: lokasi driver lewat Firestore; garis rute biru via Directions API; teks alamat driver boleh tertunda saat **hemat data** (lihat bawah).
- **Lokasi tidak segar**: pastikan driver membuka aplikasi, izin lokasi aktif, dan jaringan stabil. Tombol **Muat ulang** di peta memaksa refresh snapshot driver.

## Lacak Kirim Barang

- **Ikon**: lolipop **kuning** = pengirim, **hijau** = penerima, **mobil** = driver (sama di app driver untuk konsistensi).
- **Dua fase**:
  1. **Penjemputan** (belum `picked_up`): rute + jarak/ETA ke pengirim; kamera mengikut driver dan titik pengirim.
  2. **Perjalanan** (sudah `picked_up`): rute + ETA ke penerima; kamera mengikut driver dan titik penerima.
- Status diperbarui dari Firestore; saat barang dijemput, aplikasi menampilkan snackbar dan memperbarui peta.
- **Data**: sama seperti Lacak Driver + opsi deteksi kapal (Lacak Barang) bila diaktifkan.

## Hemat data (koneksi seluler tanpa Wi‑Fi)

Jika perangkat hanya terdeteksi **data seluler** (tanpa Wi‑Fi/ethernet), peta lacak:

- Lebih jarang meminta **Directions** ulang (jarak/langkah waktu antar refetch lebih besar).
- Membatasi frekuensi **geocoding** alamat dari koordinat driver (teks lokasi driver bisa jalan lebih lambat).

Wi‑Fi atau ethernet → perilaku refetch normal.

## Analytics (Firebase)

Event konsolidasi: `lacak_open`, `lacak_stale_banner_shown`, `lacak_phase_switch_barang` (transisi fase kirim barang).

## Lokasi driver saat HP minimize / kunci / tutup aplikasi

- **Minimize & layar kunci (disarankan):** driver tetap **Siap Kerja** atau navigasi order; di **Android** stream GPS memakai **foreground service** dengan notifikasi persisten *«Traka — navigasi aktif»* — proses tidak boleh di-«swipe kill» dari panel notifikasi jika ingin Lacak tetap jalan. Di **iOS** perlu izin lokasi **Always**; indikator lokasi biru dapat tampil saat update di background.
- **Tutup paksa / swipe app dari daftar recent:** sistem dapat menghentikan proses — **tidak ada** jaminan lokasi live; penumpang hanya melihat titik terakhir sampai driver membuka app lagi (batasan OS, bukan bug semata).
- **GPS / layanan lokasi dimatikan:** tidak ada fix baru; server menahan koordinat lama — tampilkan pesan stagne / minta driver hidupkan GPS dan buka Traka.
- **OEM (Xiaomi/Oppo/Vivo):** matikan pembatasan baterai untuk Traka (*Unrestricted* / izin latar) agar notifikasi navigasi tidak diputus.
