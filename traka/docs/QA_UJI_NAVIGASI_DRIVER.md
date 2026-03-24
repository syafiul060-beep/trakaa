# QA — navigasi driver (peta, suara, jemput → antar)

Panduan **uji manual di jalan** untuk membandingkan pengalaman Traka dengan aplikasi referensi (mis. **Grab Driver** / **Google Maps** navigasi). Isi metadata, lalu centang **Lulus** atau catat penyimpangan.

**Kapan dijalankan:** sebelum rilis besar, setelah ubah `driver_screen`, Directions, atau suara navigasi.

---

## Metadata (salin per sesi)

| Field | Nilai |
|-------|-------|
| Tanggal | |
| Versi app (`pubspec` version+build) | |
| Perangkat & Android | |
| Tester | |
| Rute uji (singkat) | mis. A → B perkotaan, ada belokan |

---

## Persiapan

1. **Volume** ponsel tidak mute; Bluetooth mati dulu agar jelas suara dari speaker HP.
2. Di overlay navigasi driver, pastikan ikon **suara tidak mute** (speaker aktif). Default app: **suara navigasi menyala** untuk pengguna baru; yang pernah mematikan tetap mengikuti preferensi tersimpan.
3. **GPS** akurasi tinggi / izin lokasi “selalu” atau “saat dipakai” sesuai kebutuhan.
4. **Perbandingan Grab (opsional):** buka Grab Driver atau Google Maps dengan **rute yang sama** (titik jemput ≈ titik mulai Traka) — tidak perlu order sungguhan, cukup **preview rute** untuk membandingkan instruksi dan arah umum.

---

## 1. Mulai kerja → masuk mode navigasi

| # | Yang dicek | Lulus |
|---|------------|-------|
| 1.1 | Setelah mulai kerja / navigasi ke order, peta **mengikuti** posisi mobil (bukan statis di dunia) | [ ] |
| 1.2 | **Intro** kamera (zoom ke mobil) terasa halus, tidak loncat aneh | [ ] |
| 1.3 | Garis rute terbaca; beda warna **sudah lewat** vs **belum** (jika terlihat di tema peta) | [ ] |

---

## 2. Diam vs bergerak (tanpa ubah kode — rasakan saja)

| # | Yang dicek | Lulus |
|---|------------|-------|
| 2.1 | **Berhenti** (parkir / antre): peta **tidak** goyang berlebihan; mobil tetap masuk akal | [ ] |
| 2.2 | **Jalan pelan** vs **cepat**: zoom/tilt terasa **lebih dekat/miring** saat cepat (chase cam) | [ ] |
| 2.3 | **Belokan tajam**: rotasi peta tidak membuat mual (animasi tidak terlalu kasar) | [ ] |

---

## 3. Suara turn-by-turn

| # | Yang dicek | Lulus |
|---|------------|-------|
| 3.1 | Sebelum belokan, ada **peringatan jarak** + arah (kiri/kanan/lurus) dalam Bahasa Indonesia | [ ] |
| 3.2 | Saat **ganti langkah**, ada getar ringan / instruksi baru (bukan diam total) | [ ] |
| 3.3 | **Mute** dari overlay: suara berhenti; **unmute**: suara kembali | [ ] |
| 3.4 | Banding Grab/Maps (opsional): urutan instruksi **tidak** tabrakan berat (mis. tidak meminta belok saat sudah melewati simpang) | [ ] |

---

## 4. Fase penjemputan → pengantaran

| # | Yang dicek | Lulus |
|---|------------|-------|
| 4.1 | **Menuju penumpang:** overlay hijau / teks “menuju penumpang”, ETA/jarak masuk akal | [ ] |
| 4.2 | Setelah **scan / konfirmasi penjemputan** sesuai alur order, rute **otomatis** ke **tujuan** (bukan tetap ke titik jemput) | [ ] |
| 4.3 | **Menuju tujuan:** overlay/oranye beda dari fase jemput; rute mengarah ke drop-off | [ ] |
| 4.4 | Tombol **fokus ke mobil** (jika ada): mengembalikan follow mode setelah geser peta manual | [ ] |

---

## 5. Selesai bekerja vs tujuan rute utama

**Aturan produk:** sampai di titik tujuan rute di peta **bukan** berarti boleh **Selesai bekerja**. Selama masih ada travel atau kirim barang yang dianggap **aktif** (belum selesai di sistem), driver harus menyelesaikan pesanan dulu. Auto-akhiri kerja di tujuan rute (setelah lama di radius tujuan) **tidak** dijalankan jika masih ada order aktif.

| # | Yang dicek | Lulus |
|---|------------|-------|
| 5.1 | Dengan order aktif, tap **Selesai bekerja** → SnackBar penolakan; tombol abu sesuai (tooltip jelas) | [ ] |
| 5.2 | GPS di dekat tujuan rute utama + order aktif → SnackBar pengingat (throttle ~10 menit), kerja **tidak** terputus otomatis oleh timer tujuan | [ ] |
| 5.3 | Setelah **semua** order terkait selesai, **Selesai bekerja** normal (dialog konfirmasi) | [ ] |

---

## 6. Catatan banding Grab (subjektif)

| Aspek | Traka (harapan) | Grab / Maps (referensi) | Catatan Anda |
|-------|-----------------|---------------------------|--------------|
| Ikuti mobil | Stabil | Sangat halus | |
| Suara | Jelas, ID | Sangat matang | |
| Simpang kompleks | Polyline + step | Lane / UI kaya | |

---

## Templat gagal

```
Tanggal:
Versi:
Langkah: (mis. 4.2 setelah scan)
Yang diharapkan:
Yang terjadi:
Screenshot / log:
```

---

*Regresi ringkas driver juga di [`QA_REGRESI_ALUR_UTAMA.md`](QA_REGRESI_ALUR_UTAMA.md).*
