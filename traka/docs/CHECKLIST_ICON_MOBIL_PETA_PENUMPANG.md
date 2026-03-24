# Checklist: ikon mobil & peta (penumpang / lacak / kirim barang)

**Kebijakan resmi (baca dulu):** [`KEBIJAKAN_ICON_MOBIL_DAN_OVERLAY.md`](KEBIJAKAN_ICON_MOBIL_DAN_OVERLAY.md) · **Regresi alur:** [`QA_REGRESI_ALUR_UTAMA.md`](QA_REGRESI_ALUR_UTAMA.md)

Gunakan daftar ini saat **audit UI** atau **PR** yang menyentuh marker, aset mobil, atau `GoogleMap` sisi penumpang/penerima. Centang `[x]` saat sudah diverifikasi di **perangkat nyata** (bukan hanya emulator).

**Legenda singkat produk (disarankan konsisten di dokumen & QA):**

| Warna / aset | Makna disarankan |
|--------------|------------------|
| **Hijau (premium)** | Ada kursi / tersedia (peta cari driver) |
| **Merah (premium)** | Kursi penuh (peta cari driver) |
| **Biru (premium)** | Rekomendasi terdekat **atau** trip aktif (lacak: agreed/picked_up) |
| **Legacy hijau/merah** | Fallback jika premium gagal load (gerak / diam di beberapa layar) |
| **Pin biru/oranye** | Titik penumpang / pengirim / penerima (bukan mobil) |

---

## A. Layar penumpang — peta utama & cari driver

| # | Lokasi | Yang dicek | OK |
|---|--------|------------|----|
| A1 | `lib/screens/penumpang_screen.dart` | Marker driver pakai **premium + `PassengerDriverMapCarIcon`**; rotasi pakai **smoothed bearing**; **glow** rekomendasi hanya jika ada kursi | [ ] |
| A2 | | Marker **lokasi Anda** (biru) & **tujuan** (merah) tetap jelas; tidak tertukar dengan mobil | [ ] |
| A3 | | Setelah **geser/zoom** peta, glow rekomendasi masih mengelilingi mobil biru (offset layar) | [ ] |
| A4 | `lib/screens/cari_travel_screen.dart` | Cluster = biru Traka; marker tunggal = **premium/legacy** + bearing ke tujuan rute; rekomendasi biru jika ada `passengerOriginLat/Lng` | [ ] |
| A5 | `pubspec.yaml` | Folder `assets/images/traka_car_icons_premium/` terdaftar | [ ] |
| A6 | `lib/services/car_icon_service.dart` | `loadPremiumPassengerCarIcons` + `clearCache()` ikut reset premium | [ ] |
| A7 | `docs/ASSET_ICON_MOBIL.md` | Orientasi mobil (depan = selatan) selaras dengan aset premium | [ ] |

---

## B. Lacak Driver & Lacak Barang (satu widget peta)

Keduanya memakai **`PassengerTrackMapWidget`**:

| # | Lokasi | Yang dicek | OK |
|---|--------|------------|----|
| B1 | `lib/screens/cek_lokasi_driver_screen.dart` | **Lacak Driver**: mobil driver + pin penumpang (foto / biru); copy di header file masih akurat (boleh update teks “car_hijau” → “premium” jika perlu) | [ ] |
| B2 | `lib/screens/cek_lokasi_barang_screen.dart` | **Lacak Barang**: mobil driver + pin penerima/pengirim; **kapal** (`enableFerryDetection`) tetap ikon kapal, bukan mobil | [ ] |
| B3 | `lib/widgets/passenger_track_map_widget.dart` | **Premium**: biru jika order `agreed`/`picked_up`, hijau sebelumnya; fallback hijau/merah gerak; rotasi **smoothed** (`_smoothedBearing`) | [ ] |
| B4 | | ETA/jarak/SOS tidak tertutup oleh zona aman ikon | [ ] |
| B5 | Alur dari `data_order_screen.dart` | Tombol **Lacak Driver** / **Lacak Barang** membuka layar di atas; setelah bayar (jika aktif), peta tampil normal | [ ] |

---

## C. Komponen / aset terkait (bukan selalu “mobil penumpang”)

| # | Lokasi | Yang dicek | OK |
|---|--------|------------|----|
| C1 | `lib/widgets/driver_map_overlays.dart` | **`CarOverlayWidget`:** premium hijau/merah + fallback legacy; arti hijau/merah = bergerak/berhenti (bukan kursi penuh). Selaras dengan `KEBIJAKAN_ICON_MOBIL_DAN_OVERLAY.md` | [ ] |
| C2 | `lib/services/driver_car_marker_service.dart` | Marker komposit driver (foto + mobil): dipakai di **app driver**; pastikan tidak membingungkan jika penumpang pernah melihat screenshot driver | [ ] |
| C3 | `lib/screens/data_order_driver_screen.dart` | **App driver** — pin oranye/ungu/biru untuk order; **bukan** scope penumpang, tapi warna jangan bentrok dengan legenda penumpang di dokumentasi QA | [ ] |
| C4 | `lib/screens/driver_screen.dart` | Peta driver: logika ikon sendiri; pastikan **tidak** mengubah file aset premium penumpang tanpa koordinasi | [ ] |

---

## D. Backend & performa (ikon tidak tergantung, tapi alur sama)

| # | Yang dicek | OK |
|---|------------|----|
| D1 | `GET /api/match/drivers` dengan `destLat`/`destLng` mengurutkan dengan `matchScore` saat keduanya valid | [ ] |
| D2 | `REDIS_PUBLISH_DRIVER_LOCATION=1` hanya dipakai jika ada consumer; hindari publish sia-sia | [ ] |
| D3 | Polling/stream lacak tidak memicu leak timer setelah `Navigator.pop` | [ ] |

---

## E. Keamanan sebelum commit / push

| # | Yang dicek | OK |
|---|------------|----|
| E1 | `docs/GITHUB_JANGAN_COMMIT_SECRETS.md` + `git grep` pola kunci | [ ] |
| E2 | Tidak ada `.env` / service account ter-commit | [ ] |

---

## F. Uji manual singkat (satu putaran)

1. **Penumpang** → isi tujuan → cari driver → pastikan hijau/merah/biru + glow (jika ada rekomendasi berkursi).  
2. **Cari Travel** → zoom sampai cluster pecah → ikon mobil konsisten.  
3. **Lacak Driver** (order agreed) → mobil biru, bergerak halus, rotasi masuk akal.  
4. **Lacak Barang** → sama + pin lawan pihak + tes rute ferry jika relevan.  
5. **Mode gelap peta** (`MapStyleService`) → ikon tidak “kotak hitam” (transparansi).  

---

*Terakhir diselaraskan dengan implementasi: premium loader, `PassengerDriverMapCarIcon`, `RecommendedDriverGlowOverlay`, matching `destLat`/`destLng`, pub/sub opsional lokasi driver.*
