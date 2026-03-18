# Kategori Rute Travel

Kategori rute untuk informasi penumpang (bukan untuk tarif aplikasi). Pembayaran penumpang langsung ke driver.

## Kategori

| Kategori | Kondisi | Estimasi Durasi |
|----------|---------|-----------------|
| **Dalam Kota** | Sama kabupaten/kota, sama provinsi | ~1–3 jam |
| **Antar Kabupaten** | Beda kabupaten, sama provinsi | ~2–6 jam |
| **Antar Provinsi** | Beda provinsi, 1 pulau | ~4–12 jam |
| **Nasional** | Beda pulau | ~1–3 hari |

## Tampilan

- **Penumpang (Cari Travel)**: Badge kategori + estimasi durasi di sheet detail driver
- **Penumpang (Peta)**: Badge kategori + estimasi durasi di bottom sheet profil driver

## Warna Badge

- Dalam Kota: hijau
- Antar Kabupaten: teal
- Antar Provinsi: biru
- Nasional: oranye

## Service

`RouteCategoryService.getRouteCategory()` – geocoding origin & dest untuk ambil provinsi/kabupaten, lalu tentukan kategori.
