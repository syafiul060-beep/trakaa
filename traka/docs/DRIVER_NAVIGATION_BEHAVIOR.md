# Perilaku navigasi driver (internal)

Ringkasan untuk QA dan pengembangan: bagaimana peta, TBT, Directions, hemat data, dan telemetri berinteraksi di layar driver.

## Mode kamera dan orientasi

- **Heading-up / ikut bearing**: kamera mengikuti bearing kendaraan (disaring / lookahead pada polyline) saat pelacakan aktif.
- **North-up**: pengguna dapat memutar peta; tombol fokus mengembalikan ikut rute.
- **Gaya Google Maps — geser manual**: begitu pengguna menggeser peta (`onCameraMoveStarted`), `_cameraTrackingEnabled = false` dan **tidak** ada auto-resume saat mobil jalan jauh; hanya **tombol pusatkan / fokus** yang mengaktifkan ikut lagi.
- Padding peta (termasuk bawah) menempatkan ikon di zona bawah dengan margin dari tepi layar, selaras banner TBT dan kontrol.

## Turn-by-turn (TBT)

- Teks utama instruksi selaras dengan **TTS** (`InstructionFormatter`).
- **Jarak besar** ke manuver memakai proyeksi jarak sepanjang polyline ke akhir langkah aktif bila tersedia; jika belum ada (GPS belum “nempel” atau proyeksi gagal), banner menampilkan **instruksi penuh** plus **baris bantuan** (ikuti garis biru + suara).
- Baris “Lalu: …” memakai jarak ke langkah berikutnya bila tersedia.

## Re-route

- Saat rute disesuaikan otomatis, banner hijau singkat (“Rute disesuaikan…”) dan **haptik sedang** memberi umpan balik.
- Tombol “Ikuti rute” (jika ada) mengembalikan kamera ke mode ikut.
- **Simpangan** diukur ke segmen polyline **maju** (`RouteUtils.distanceToPolylineForwardFrom`) agar jalan paralel lama tidak menahan deteksi keluar rute.
- **Batas meter** awal auto reroute: default 42 m; jika **navigasi premium aktif** (premium nyala + sedang kerja atau navigasi ke order), ambang efektif sedikit **lebih ketat** (offset dari config, clamp minimum ~22 m) dan debounce jarak antar-fetch sedikit lebih pendek — agar garis biru lebih cepat mengikuti jalan setelah menyimpang. Bisa di-override admin lewat Firestore (lihat **Konfigurasi Firestore (admin)** di bawah).

### Konfigurasi Firestore (admin)

| Kunci / path | Tipe | Nilai | Dampak |
|--------------|------|-------|--------|
| `app_config` dokumen `settings`, field `driverNavAutoRerouteMinDeviationM` | number | 20–90 (meter) | Jarak menyamping minimum sebelum auto re-route. Lebih kecil = lebih sensitif. Cache klien ~15 menit (`AppConfigService.clearDriverNavRerouteConfigCache()` setelah ubah jika perlu tes cepat). |

## Ikon panah & kamera (gaya Maps)

- Saat menyimpang cukup jauh atau heading HP beda jelas dari tangen rute, panah memakai **course** (heading / displacement), bukan dipaksa ikut belokan polyline (**mode non-premium / fallback** menggabungkan tangen rute dan course; lihat `_navIconPreferCourseBearing` di `driver_screen.dart`).
- **Jangan** memperbarui `_lastCameraBearing` saat skip `animateCamera` — peta harus ikut berputar (heading-up), bukan hanya marker.

### Navigasi premium: panah vs garis biru

- **Premium aktif** (`_premiumNavQualityActive`: tombol premium nyala + driver sedang kerja atau navigasi ke order) dan ada proyeksi rute valid: **rotasi panah mengikuti course / heading perangkat** (mirip Google Maps), bukan tangen polyline. Garis biru berperan sebagai **panduan jalur + pemicu reroute** saat menyimpang, bukan sebagai “poros” rotasi ikon — mengurangi efek panah “berputar mengikuti garis” saat lokasi sudah di jalan lain.
- Heading dipercaya pada kecepatan sedikit lebih rendah daripada mode standar (`_bearingMinSpeedMpsPremium`), supaya orientasi HP lebih cepat dipakai di jalan pelan.
- **Tanpa premium** perilaku di atas tidak dipaksa penuh; tetap berlaku aturan simpangan / selisih derajat ke tangen rute seperti sebelumnya.

## Tampilan peta

- **Gaya = default Google Maps SDK** (roadmap / satelit lewat kontrol tipe peta): tanpa JSON styling, tanpa Cloud Map ID. Tema aplikasi (terang/gelap) hanya mempengaruhi UI Flutter, bukan skin peta.

## Hemat data navigasi

- Preferensi di profil driver (`NavigationSettingsService`).
- Saat aktif: layer traffic Directions dibatasi, pemakaian kuota/jaringan dikurangi (lihat `directions_service` / pemanggilan di `driver_screen`).
- **Indikator ikon** di kolom kanan peta (tooltip menjelaskan dampak) hanya saat **navigasi aktif** (kerja atau navigasi ke penumpang/tujuan).

## Tombol selesai kerja

- Ikon **stop** di kolom kanan, di bawah info rute; area tap minimum **48×48** dp, tampilan visual tetap ~36 dp.
- Tooltip menjelaskan jika masih ada order aktif (terkunci).

## Build hybrid (`TRAKA_USE_HYBRID`)

- Hanya mengubah backend/API lewat `--dart-define`; **layar peta driver dan lacak penumpang tetap Flutter** (`driver_screen`, `PassengerTrackMapWidget`). Perilaku kamera, padding, dan interpolasi tidak berbeda dari build non-hybrid kecuali ada fork terpisah di masa depan.

## Analytics & Crashlytics

- `map_focus_recenter`: tap «fokus ke mobil» — parameter `source`: `driver` | `passenger_track`.
- `driver_nav_premium_ui`: premium aktif/nonaktif — `enabled`, `source` (`map_tap` \| `prepay_success` \| `exempt` \| `persist_restore`).
- `driver_nav_reroute`: polyline dihitung ulang — `trigger`, `scope` (`main` \| `to_passenger` \| `to_destination`), `premium_quality`, `success`, opsional `deviation_bucket` (rute utama).
- `driver_nav_route_deviation_sample`: sampel throttle simpangan ke polyline — `deviation_bucket`, `premium_quality`, `nav_context` (lihat [`GA4_ADMIN_CUSTOM_DIMENSIONS.md`](GA4_ADMIN_CUSTOM_DIMENSIONS.md)).
- `driver_nav_route_fetch` (Analytics): scope, sukses, latensi, error key, stale cache.
- **Crashlytics non-fatal** (throttle ~10 menit per kombinasi scope+error): kegagalan fetch Directions yang relevan untuk tren infrastruktur; diabaikan untuk kasus produk seperti `zero_routes` / `no_polyline` (lihat `navigation_diagnostics.dart`).

## Suara

- Jarak dekat memicu TTS; mute dari kartu TBT.
