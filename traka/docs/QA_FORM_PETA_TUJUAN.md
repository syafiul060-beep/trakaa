# QA singkat — form tujuan & «Pilih di peta»

Checklist manual (ID).

## Beranda penumpang / form Cari Travel (sheet)

1. **Field tujuan kosong** → ketuk «Pilih di peta» → peta mulai di **lokasi Anda** (atau fallback jika GPS belum ada).
2. **Field tujuan berisi teks** (tanpa memilih saran) → ketuk «Pilih di peta» → muncul dialog **«Mencari lokasi dari alamat…»** singkat (jika perlu geokode) → peta di titik hasil geokode atau fallback ke lokasi Anda.
3. **Pilih saran autocomplete** → ketuk «Pilih di peta» → peta di **koordinat saran** (tanpa dialog jika koordinat sudah ada).
4. **Setelah memilih titik di peta dan konfirmasi** → teks field tujuan terisi **alamat dari reverse geocode**; tombol Cari / alur berikutnya memakai titik itu.

## Form rute driver (sheet biru)

Skenario sama seperti penumpang: kosong → lokasi Anda; terisi → geokode atau koordinat; konfirmasi peta → field + validasi filter provinsi/pulau (jika ada).

## Jadwal rute & Pesan (Cari Jadwal)

- **Titik awal di peta** / **titik akhir di peta**: teks kosong → kamera mengikuti **GPS**; teks terisi → geokode + dialog tunggu bila perlu; konsisten dengan logika `initialTargetForDestinationMapPicker`.

## Pratinjau Kirim Barang (Data Order driver)

- Marker **pengirim** memakai pin **awal**; **penerima** memakai pin **akhir** (fallback marker warna jika aset gagal).

## Aset

- Di **`pubspec.yaml`** wajib ada baris **`assets/images/pin/`** (bukan hanya `assets/images/`).
- `awal.png` & `ahir.png` di folder itu (lihat `lib/config/traka_pin_assets.dart`); PNG sangat besar bisa gagal decode → fallback pin Google.

## Aksesibilitas (screen reader)

- Tombol «Pilih di peta» di sheet driver/penumpang: **label** dari teks tombol, **hint** dari `pickOnMapTooltip` (Tooltip tidak menggandakan pengumuman ke semantics).
