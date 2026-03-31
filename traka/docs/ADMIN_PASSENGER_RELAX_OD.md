# Panduan internal: jarak OD Cari travel (penumpang)

Dokumen ini untuk **tim ops / support** yang mengatur ambang jarak asal–tujuan (OD) agar filter driver di Cari travel sesuai jarak perjalanan.

---

## Di mana mengatur

| Tempat | Langkah |
|--------|---------|
| **Admin web** | **Pengaturan** → kartu **Cari travel — jarak OD penumpang** → isi km per baris → **Simpan** |
| **Firestore** | Dokumen `app_config/settings` (field di bawah; nilai dalam **meter**) |

### Nama field di Firestore (meter)

- `passengerRelaxBeforePickupAntarProvinsiMeters` — lintas provinsi, **satu pulau**
- `passengerRelaxBeforePickupNasionalMeters` — **beda pulau**
- `passengerRelaxBeforePickupUnknownGeocodeMeters` — provinsi tidak terbaca dari geocode (fallback)

UI admin menampilkan **km**; saat simpan dikonversi ke meter.

---

## Apa dampaknya

- Jika jarak OD penumpang **≥ ambang** (untuk kategori rutenya), app boleh **melonggarkan** syarat «driver belum lewat titik jemput» — cocok untuk travel jauh.
- Jika OD **di bawah ambang**, perilaku lebih **ketat**.

**Penting:** untuk rute **dalam satu provinsi / antar kabupaten**, pengaturan ini **tidak dipakai** — tidak pernah dilonggarkan lewat field di atas.

| Kategori rute | Field yang dipakai |
|---------------|-------------------|
| Antar provinsi (satu pulau) | `…AntarProvinsiMeters` |
| Nasional (beda pulau) | `…NasionalMeters` |
| Provinsi tidak terbaca | `…UnknownGeocodeMeters` |

Jika field kosong, app memakai default **100 km** per kategori (kode: `AppConstants`).

---

## Setelah mengubah angka di admin

- Perubahan dibaca dari Firestore; di app penumpang ada **cache singkat** (sekitar **1 menit**).
- Supaya cepat terbarui tanpa menunggu: user bisa **buka ulang app** (dari background / recent apps) — cache OD di-reset saat app kembali aktif.

---

## Cek cepat (QA / laporan bug)

1. **OD pendek, satu provinsi** — harus tetap ketat; keluhan «terlalu longgar» di sini biasanya **bukan** karena tiga field OD ini.
2. **OD jauh, lintas provinsi satu pulau** — setelah naikkan ambang, daftar driver boleh lebih «longgar» (sesuai desain).
3. **Setelah ubah di admin** — verifikasi di perangkat penumpang setelah ±1 menit atau setelah buka ulang app.

---

## Keamanan

`app_config/settings`: aturan ada di `firestore.rules` — **baca** sesuai kebijakan produk; **tulis** hanya lewat akun admin / backend, bukan dari app penumpang biasa.
