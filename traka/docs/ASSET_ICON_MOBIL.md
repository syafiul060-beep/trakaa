# Spesifikasi Asset Icon Mobil (car_merah.png, car_hijau.png)

**Overview 4 tahap:** Lihat `docs/4_TAHAP_ICON_MOBIL.md`

## Orientasi
- **Mobil harus menghadap ke bawah** (depan mobil = arah selatan di gambar)
- Rotasi di kode: `rotation = (bearing + 180) % 360`
- Jika mengganti asset, pastikan orientasi sama agar rotasi benar

## Tumpang tindih Tahap 1 & 4
- **Tahap 1** (bearing smoothing) memakai `rotation = (bearing + 180) % 360` dengan asumsi mobil menghadap ke bawah
- **Tahap 4** (custom icon): saat ganti asset, wajib pastikan orientasi sama (depan mobil = selatan)
- Jika icon menghadap salah arah → rotasi asset 180° di editor, lalu verifikasi di app

## Resolusi
- **Base size:** 50–80 px (tergantung layar)
- **Decode:** 144–384 px untuk retina (2x–3x)
- **Format:** PNG dengan transparansi

### Variant untuk layar retina (wajib agar tidak pecah)
Icon 96×96 px tampak pecah di layar 2x/3x. Gunakan asset variant:

| Folder | Ukuran | Untuk |
|--------|--------|-------|
| `assets/images/` | 96×96 px | 1x (fallback) |
| `assets/images/2.0x/` | 192×192 px | Layar 2x |
| `assets/images/3.0x/` | 288×288 px | Layar 3x |

Flutter otomatis memilih variant sesuai devicePixelRatio. Tanpa 2.0x/3.0x, icon akan tampak pecah di HP modern.

**Cara buat variant:** Idealnya buat dari vector/SVG lalu export ke 192×192 dan 288×288. Atau scale up di editor (Figma, GIMP) dengan algoritma "nearest neighbor" untuk gaya pixel-art, atau "bicubic" untuk halus—simpan ke folder 2.0x dan 3.0x.

## File
- `assets/images/car_merah.png` – driver diam / tidak bergerak
- `assets/images/car_hijau.png` – driver bergerak
- `assets/images/traka_car_icons_premium/car_green.png`, `car_red.png`, `car_blue.png` – map penumpang (tersedia / penuh / rekomendasi atau trip aktif di lacak). **Depan mobil = bawah gambar** (sama legacy: selatan di PNG); **tanpa** putar 180° di pipeline decode. Rotasi marker: `(bearing + 180) % 360` lewat `CarIconService.markerRotationDegrees` dengan `PremiumPassengerCarIconSet.assetFrontFacesNorth == false`. Loader: `CarIconService.loadPremiumPassengerCarIcons`. **Latar putih:** di app dipotong dengan *flood fill dari tepi gambar* (bukan chromakey global) agar **atap putih** di dalam siluet tidak ikut transparan; pilar/atap sebaiknya tidak semuanya `#FFFFFF` menyatu dengan latar (sedikit beda RGB atau transparansi asli di PNG juga membantu).
- `assets/images/2.0x/car_merah.png`, `car_hijau.png` – 192×192 px
- `assets/images/3.0x/car_merah.png`, `car_hijau.png` – 288×288 px

## Service
- `lib/services/car_icon_service.dart` – Load terpusat untuk layar penumpang (cari driver, Lacak Driver, Lacak Barang)
- Fallback: `BitmapDescriptor.fromAssetImage` jika `package:image` gagal decode

## Gaya (Tahap 4)
- Top-down view, minimalis ala Grab/Uber/InDrive
- Warna solid: merah (#E53935), hijau (#43A047)
- Lihat `docs/TAHAP_4_CUSTOM_ICON_MOBIL.md` untuk panduan lengkap

## Penggunaan (khusus penumpang)
- Penumpang screen (cari driver aktif): icon mobil, isMoving dari stream real-time, rotasi dari bearing
- Cari Travel: icon mobil (car_merah/car_hijau), rotasi driver→tujuan
- Lacak Driver, Lacak Barang: icon mobil (sudah punya rotation di passenger_track_map_widget)
- Satu sumber isMoving: state.lastUpdated dari stream (bukan snapshot)
- Threshold isMoving: 8 detik (AppConstants.penumpangIsMovingThresholdSeconds)
- Rotasi: asset depan = selatan, Marker.rotation = (bearing + 180) % 360, flat: true
