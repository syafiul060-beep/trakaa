# Ringkasan perbaikan UI/UX, aksesibilitas & performa (Maret 2025)

Dokumen ini menjelaskan **sebelum vs sesudah** dan **efek** untuk pengguna, aksesibilitas, dan pengukuran performa.

---

## 1. Profil driver = pola profil penumpang

| Aspek | Sebelum | Sesudah |
|--------|---------|---------|
| AppBar | Judul hanya “Versi x.y.z” | **Profil** + subtitle **v…** (sama seperti penumpang) |
| Foto terkunci | Tap tidak ada feedback | Snackbar **“Foto profil dapat diubah setelah N hari…”** (l10n) |
| Teks loading | Hardcoded `Memuat...` | `loadingGeneric` (ID/EN) |

**Efek:** merek konsisten penumpang/driver; pengguna paham kenapa foto tidak bisa diganti.

---

## 2. Dialog & bottom sheet (tema terpusat)

| Aspek | Sebelum | Sesudah |
|--------|---------|---------|
| `DialogTheme` | Hanya bentuk + teks judul | Ditambah **`actionsPadding`** seragam + **`alignment`** |
| Sheet “Email & Telp” (profil penumpang) | Radius manual + `responsive` | **`TrakaUiHelpers.modalSheetShape(context)`** mengikuti `bottomSheetTheme` |

**File:** `lib/theme/traka_ui_helpers.dart` (bisa dipakai ulang di sheet lain).

**Efek:** jarak tombol dialog lebih konsisten; sheet mengikuti token `AppTheme` / tema Material.

---

## 3. Bottom navigation + Semantics

| Aspek | Sebelum | Sesudah |
|--------|---------|---------|
| Implementasi | Duplikasi besar di `penumpang_screen` & `driver_screen` | **`TrakaMainBottomNavigationBar`** satu widget |
| Aksesibilitas | Label default saja | **Semantics** per tab (termasuk **chat + jumlah belum dibaca**) |
| Haptic | Duplikat (layar + bar) | **Satu** `HapticFeedback.selectionClick()` di widget bar |
| Ikon Jadwal | Beda (wajar) | **`TrakaScheduleTabIcon`**: penumpang = kalender, driver = jam (`schedule`) |

**Efek:** TalkBack/VoiceOver lebih jelas; kode lebih mudah dirawat; getar tidak dobel.

---

## 4. Firebase Performance — trace bernama

| Trace | Kapan | Efek ke peta “live”? |
|--------|--------|----------------------|
| `startup_to_interactive` | Mulai sebelum `runApp`, berhenti di layar pertama (login / home / onboarding / update / maintenance / izin, dll.) | **Tidak** — hanya pengukuran |
| `passenger_map_ready` | Dari `onMapCreated` sampai setelah frame pertama peta penumpang | **Tidak** — tidak mengubah interval update marker |
| `order_submit` | Sekitar `OrderService.createOrder` di `pesan_screen` (travel + kirim barang) | **Tidak** |

**Efek:** di konsol Firebase Performance Anda bisa melihat durasi startup, siapnya peta, dan submit pesanan — **bukan** mengurangi realtime; frekuensi update peta **tidak** di-throttle dalam patch ini.

---

## 5. Konstanta peta penumpang

Hanya **komentar dokumentasi** di `AppConstants.passengerMapInterpolationIntervalMs` (nilai 80 ms **tetap**).

**Efek:** tim tahu trade-off UX vs CPU sebelum mengubah angka; perilaku app **sama** seperti sebelumnya.

---

## 6. Widget kosong (empty state)

**File:** `lib/widgets/traka_empty_state.dart` — pola ikon + judul + pesan + opsi tombol.

**Efek:** siap dipakai bertahap di layar yang masih layout manual; tidak mengganti semua empty state sekaligus agar diff tetap fokus.

---

## 7. Animasi transisi antar tab

**Tidak diubah** secara teknis: masih **`IndexedStack`** (state tab dipertahankan — penting untuk peta & form).

**Efek:** tidak ada risiko hilangnya state atau jank tambahan; transisi **halaman** (push route) tetap mengikuti `pageTransitionsTheme` yang sudah ada di `AppTheme`.

---

## 8. Tes regresi

Tidak mengganti isi `QA_REGRESI_ALUR_UTAMA.md` — **disarankan** jalankan checklist itu setelah build rilis.

---

## File utama yang berubah

- `lib/main.dart` — mulai trace startup  
- `lib/services/performance_trace_service.dart` — **baru**  
- `lib/widgets/traka_main_bottom_navigation_bar.dart` — **baru**  
- `lib/widgets/traka_empty_state.dart` — **baru**  
- `lib/theme/traka_ui_helpers.dart` — **baru**  
- `lib/theme/app_theme.dart` — dialog theme  
- `lib/services/user_shell_profile_stream.dart` — stream shell verifikasi (distinct fingerprint)  
- `lib/screens/penumpang_screen.dart`, `driver_screen.dart`, `pesan_screen.dart`  
- `lib/screens/profile_*`, `login_screen`, `onboarding`, `reverify_face`, `permission_required`, `force_update`, `maintenance`  
- `lib/l10n/app_localizations.dart` — `loadingGeneric`  
- `lib/config/app_constants.dart` — komentar interpolasi peta  

---

## 6. Responsif pasca-login: tab beranda & geser

| Aspek | Penyebab | Perbaikan |
|--------|----------|-----------|
| Tab lazy (1–4) | `IndexedStack` + `Set` “sudah dikunjungi” | **`_visitedTabIndices` hanya diisi dari `setState` / handler** (`_registerTabVisit`) — bukan di dalam `build` / `StreamBuilder`. Mutasi `Set` saat build memicu frame tambahan dan bisa membuat **geser / pindah tab terasa berat** setelah login atau saat profil Firestore sering update. |
| Decode marker mobil | `_loadCarIcons()` di `initState` langsung | **Panggil setelah frame pertama** (`addPostFrameCallback` + `unawaited`) pada **penumpang** agar transisi login → beranda tidak berebut CPU dengan decode bitmap di frame yang sama. |

**File:** `lib/services/user_shell_profile_stream.dart` (baru), `lib/screens/penumpang_screen.dart`, `lib/screens/driver_screen.dart`.

**Catatan (lanjutan):** shell beranda memakai **`user_shell_profile_stream.dart`** — stream `users/{uid}` hanya **meng-emit** saat **fingerprint field verifikasi** berubah (bukan tiap `lastSeen` / update lain), sehingga `IndexedStack` tidak me-rebuild penuh tanpa perlu.

**Driver — restore rute setelah app ditutup:** `_tryRestoreActiveRoute` dulu menunggu **Directions API** baru `setState` → status “aktif” terasa lambat. Sekarang **setState optimistik** (titik awal/akhir + nomor rute dari Firestore jika ada) **sebelum** `getAlternativeRoutes`, lalu **revert** jika alternatif kosong; polyline tetap diisi setelah Directions selesai.

**Lanjutan:** retry **Directions** sekali (delay 600 ms, tanpa traffic) jika hasil pertama kosong; **SnackBar** jika tetap gagal; banner **“Memuat rute di peta…”** saat `_routeRestoreAwaitingPolyline` (antara optimistik dan polyline siap).

**Penumpang — peta cari driver:** `setState` di **`_onDriverStatusUpdate` (stream tiap driver)** dihapus — pembaruan UI mengandalkan timer interpolasi saja (menghindari puluhan rebuild/detik). **`onCameraMoveStarted` / `onCameraIdle`** mengatur `_passengerMapUserGesturing` agar throttle interpolasi **lebih jarang (~220 ms)** saat user geser peta. **Marker driver:** `zIndexInt` (rekomendasi di atas), **`consumeTapEvents` di Android**, dan **buka sheet lewat `addPostFrameCallback`** agar tap tidak bentrok dengan rebuild frame yang sama.

**Driver — peta mode aktif (geser + tombol fokus):** interpolasi `setState` di-throttle **lebih jarang** (~220 ms) saat **tracking kamera mati** (user geser manual) agar rebuild tidak berebut dengan gesture. **Tombol fokus:** reset `_lastCameraTarget` + flag `snapFocus` agar animasi tidak di-skip oleh `distanceMeters < 5` setelah user geser peta; durasi fokus dipendek (~320 ms). **`_getCurrentLocation`:** `return` saat skip animasi diganti jadi `if (distance >= 5) { animate }` agar tidak keluar dari fungsi secara tidak sengaja.

**Auto-resume ikut kamera:** saat user geser peta, titik GPS disimpan; jika driver kemudian bergerak **≥ ~90 m** dari titik itu (mode aktif / navigasi order), tracking kamera **dinyalakan lagi** dan kamera di-snap ke mobil (tanpa harus tap Fokus). Perubahan kecil GPS saat parkir tidak memicu resume.

**Referensi produk (rute & matching):** perilaku **rute alternatif driver**, **re-route**, dan **filter penumpang cari driver aktif** dijelaskan di [`ROUTING_ALTERNATIF_DRIVER_DAN_MATCH_PENUMPANG.md`](ROUTING_ALTERNATIF_DRIVER_DAN_MATCH_PENUMPANG.md) (tabel ringkas + parameter operasional).

**Driver — banner keluar rute + tombol perbarui:** subtree dibungkus **`RepaintBoundary`** agar repaint banner tidak memicu repaint layer **GoogleMap**; **satu** `TrakaL10n.of` per build peta (`l10nMap`) untuk teks banner (bukan lookup berulang). Tidak ada timer tambahan; re-route manual tetap satu request Directions seperti alur otomatis.

**Notifikasi jarak ke penumpang:** proximity (1 km / 500 m) **tidak** tergantung driver tap “arahkan”. **`_shouldUpdateFirestore`:** tiga tier — lacak penuh (50 m / 5 s), **pickup proximity hemat** (300 m / 60 s) jika hanya agreed menunggu jemput, default 2 km / 15 menit. Konstanta: `DriverStatusService.shouldUpdateLocationForPickupProximity`. Lihat [`NOTIFIKASI_JARAK_PENUMPANG_DRIVER.md`](NOTIFIKASI_JARAK_PENUMPANG_DRIVER.md).

**Notifikasi — tahap 1–4:** Profil penumpang & driver → **Notifikasi** (`notification_settings_screen.dart`) + analytics `notification_settings_*`; judul lokal jarak memakai **“Driver mendekati”**; **`local_proximity_notif_shown`** (flow + band) saat notifikasi jarak tampil. Ringkasan di [`NOTIFIKASI_APLIKASI_TRAKA.md`](NOTIFIKASI_APLIKASI_TRAKA.md), QA bagian **N** di [`QA_REGRESI_ALUR_UTAMA.md`](QA_REGRESI_ALUR_UTAMA.md).

---

## Yang sengaja tidak dilakukan (ruang kerja berikut)

- Memecah `penumpang_screen` / `driver_screen` / `pesan_screen` menjadi banyak file (butuh refactor bertahap).  
- Mengganti semua string hardcoded di seluruh app ke l10n.  
- Menambahkan animasi fade/slide antar tab tanpa migrasi arsitektur tab.
