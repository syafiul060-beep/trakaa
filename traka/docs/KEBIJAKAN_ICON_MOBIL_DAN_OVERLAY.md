# Kebijakan: ikon mobil & overlay (Traka)

Dokumen ini **mengunci perilaku** agar QA, desain, dan kode tidak saling salah paham. Revisi kebijakan = update dokumen ini + checklist terkait.

---

## 1. Dua konteks berbeda (wajib dipahami)

| Konteks | Di mana | Arti warna / aset |
|--------|---------|-------------------|
| **A. Peta penumpang (marker)** | Beranda cari driver, Cari Travel | **Hijau** = ada kursi; **merah** = penuh; **biru** = rekomendasi terdekat. Sumber: `PremiumPassengerCarIconSet` + `PassengerDriverMapCarIcon` (+ legacy `car_merah`/`car_hijau` jika premium gagal). |
| **B. Overlay “head unit” (bukan marker)** | Lacak Driver/Barang (`PassengerTrackMapWidget`), peta driver (`DriverCarOverlay`) | **Hijau** = mobil dianggap **bergerak** (update lokasi segar); **merah** = **berhenti**/diam. **Bukan** indikator kursi penuh. |

Jangan menyamakan arti merah di (A) dengan merah di (B) saat menjelaskan ke pengguna; di UI tidak perlu teks panjang—cukup konsistensi visual.

---

## 2. Satu gaya gambar (aset)

- **Utama:** `assets/images/traka_car_icons_premium/car_green.png` & `car_red.png` untuk overlay bergerak/diam.
- **Fallback:** `assets/images/car_hijau.png` & `car_merah.png` jika file premium tidak bisa dimuat.
- **Marker di peta:** diproses lewat `CarIconService` (transparansi + rotasi 180° sesuai `ASSET_ICON_MOBIL.md`). Overlay memakai **Image.asset** yang sama dengan orientasi bearing `(bearing + 180) % 360`.

`car_blue.png` dipakai di **marker** peta (rekomendasi / trip aktif lacak), **bukan** di overlay head unit.

---

## 3. Infrastruktur & iterasi

- Tambah **WebSocket / push massal** hanya setelah ada bukti bottleneck (latensi, skala) dari log atau feedback.
- Perubahan ikon besar: bump versi di `CarIconService` (`_premiumProcessingVersion` / `_processingVersion`) agar cache tidak bocor.

---

## 4. Rujukan

- `docs/CHECKLIST_ICON_MOBIL_PETA_PENUMPANG.md` — verifikasi sebelum rilis.
- `docs/ASSET_ICON_MOBIL.md` — orientasi aset.
- `traka-api/docs/REDIS_GEO_MATCHING.md` — matching backend.
