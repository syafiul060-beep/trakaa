# Inventaris layanan global & listener (Tahap 1)

**Tujuan:** Memetakan semua init/listen yang berjalan **sebelum atau di luar** `PenumpangScreen` / `DriverScreen`, untuk antisipasi antrean Firestore dan kebijakan *satu peran aktif per sesi*.

**Tanggal audit:** 2026-03-29  
**Lingkup:** `lib/main.dart`, handler FCM terdaftar dari main, `_initInBackground`, `_setupAuthStateListener`. (Layar: `AuthFlowService.navigateToHome` sudah memisahkan root UI per role — tidak diulang di sini.)

---

## Kategori

| Kode | Arti |
|------|------|
| **Umum** | Wajar untuk semua pengguna login; tidak mengasumsikan satu role. |
| **Penumpang / penerima** | Stream atau logika khusus alur penumpang, pengirim, atau penerima lacak barang. |
| **Driver** | Khusus alur driver (contoh: rute aktif, kontribusi). |
| **Campuran** | Satu modul menyalurkan beberapa channel/tipe notifikasi untuk multi-role; init channel ≠ subscribe Firestore. |

---

## 1. `main()` — sebelum `runApp` (synchronous / blocking)

| Urutan | Layanan / pemanggilan | Kategori | Catatan |
|--------|------------------------|----------|---------|
| — | `GoogleMapsFlutterAndroid.initializeWithRenderer` + `warmup()` | Umum | UI maps; bukan Firestore. |
| — | `CarIconService.clearCache()` | Umum | Lokal. |
| — | `Firebase.initializeApp` | Umum | — |
| — | `registerFirebaseMessagingBackgroundHandler()` | Umum | Top-level handler; payload bisa order/chat untuk kedua role. |
| — | `ThemeService`, `MapStyleService`, `LocaleService`, `LiteModeService`, `NavigationSettingsService` | Umum | Preferensi lokal + Firestore app config lewat provider terpisah. |
| — | `VoiceNavigationService.instance.applySpeechRateFromSettings()` | Condong driver | Dipakai dominan navigasi driver; init hanya baca preferensi. |
| — | `FirebaseFirestore.settings` | Umum | Ukuran cache; tidak subscribe koleksi. |
| — | `TileLayerService.ensureInitialized()` | Umum | Tile/osm terpisah dari role. |
| — | `FcmService.init()` | **Campuran** | Listener foreground + token; navigasi dari payload harus tetap valid untuk driver & penumpang. Bukan subscribe orders di sini. |

---

## 2. `_setupAuthStateListener()` — `FirebaseAuth.instance.authStateChanges()`

| Kondisi | Layanan / aksi | Kategori | Catatan |
|---------|----------------|----------|---------|
| `user == null` | `PassengerProximityNotificationService.stop()` | Penumpang / penerima | Benar saat logout. |
| `user == null` | `ReceiverProximityNotificationService.stop()` | Penumpang / penerima | Benar saat logout. |
| `prevUser?.uid != user.uid` | *(bukan sumber start proximity — Tahap 3)* | — | `start` proximity hanya lewat `RoleBasedProximitySession.applyForFirestoreRole` di pintu home (§4, §7). |
| `prevUser?.uid != user?.uid` | `ExemptionService.clearNavPremiumExemptPhoneCache()` | Condong driver | Cache nomor exempt navigasi premium. |
| `prevUser != null && user == null` | `BiometricLockService.forceUnlock()` | Umum | — |
| Sama | `VoiceCallIncomingService.stop()` | Umum | Panggilan masuk — kedua role bisa relevan. |

**Tahap 3:** Race di atas dihilangkan: listener auth **tidak** mem-start proximity saat login; peran disinkronkan hanya saat role sudah diketahui di alur UI (splash/login `navigateToHome`, onboarding selesai, registrasi cabang batal-hapus).

---

## 3. `_initInBackground()` — setelah `runApp`

| Layanan | Kategori | Catatan |
|---------|----------|---------|
| `ConnectivityService.startListening()` | Umum | Jaringan. |
| `AdminContactConfigService.load()` | Umum | Prefetch global; coalesce in-flight (§8). Bukan lagi duplikat dari `authStateChanges`. |
| `RouteNotificationService.init()` | **Campuran** | Hanya registrasi plugin + **channel** Android (driver mendekati, lacak barang, jadwal, verifikasi, dll.). **Tidak** subscribe Firestore di sini. |

---

## 4. Lain (di luar `main.dart`, tetap relevan global)

| Lokasi | Perilaku | Kategori |
|--------|----------|----------|
| `AuthFlowService.navigateToHome` | `RoleBasedProximitySession.applyForFirestoreRole(role)`, lalu `FcmService.saveTokenForUser`, `VoiceCallIncomingService.start(uid)` | Penumpang/penerima + umum |
| `OnboardingScreen._onDone` | `applyForFirestoreRole` lalu root `AppUpdateWrapper` + home | Penumpang/penerima |
| `RegisterScreen._completeRegistration` (batal penghapusan akun) | `applyForFirestoreRole`, FCM/voice, lalu `AppUpdateWrapper` + home | Sama seperti login |
| `SplashScreenWrapper._requestNotificationInBackground` | Izin notifikasi | Umum |

---

## 5. Status backlog (Tahap 2–5)

| Prioritas | Item | Status |
|-----------|------|--------|
| **P1** | Gate proximity di auth (driver tidak subscribe penumpang/penerima) | **Selesai** — `RoleBasedProximitySession`, bukan `start()` buta di auth. |
| P2 | Satukan sesi role / satu pintu start proximity | **Selesai** — §4 + §7. |
| P3 | Kurangi `AdminContactConfigService.load` ganda | **Selesai** — prefetch di `_initInBackground` saja; coalesce in-flight di service (§8). |
| **Tahap 5** | Observabilitas lapangan + Firebase Performance | **Selesai** — §9; detail proses QA di [`FIELD_OBSERVABILITY.md`](FIELD_OBSERVABILITY.md). |

**Catatan:** `load()` eksplisit tetap dipakai di jalur SOS (fresh sebelum WA); widget kontak hanya stream + prefetch global.

---

## 6. Yang **sudah** OK (referensi cepat)

- **`AuthFlowService.navigateToHome`**: hanya membuka `PenumpangScreen` **atau** `DriverScreen`, bukan keduanya.
- **Proximity `stop` saat `user == null`**: sudah konsisten.

---

*Dokumen ini adalah keluaran resmi **Tahap 1 (inventaris)**.*

## 7. Implementasi Tahap 2–3 (ringkas)

- `lib/services/role_based_proximity_session.dart`: `applyForFirestoreRole(role)` mem-start/stop kedua layanan proximity; `applyForCurrentUserFromFirestore()` tetap ada untuk keperluan khusus (bukan dipanggil dari `main` setelah Tahap 3).
- `auth_flow_service.dart`: `applyForFirestoreRole(role)` di awal `navigateToHome`.
- `onboarding_screen.dart`: `applyForFirestoreRole(widget.role)` di `_onDone` sebelum navigasi home.
- `register_screen.dart`: cabang batal penghapusan akun memanggil `applyForFirestoreRole` lalu navigasi ke `AppUpdateWrapper` + `PenumpangScreen` / `DriverScreen` (selaras splash/login).
- `main.dart`: `authStateChanges` hanya **menghentikan** proximity saat `user == null`; tidak lagi menyinkronkan start pada pergantian `uid` (satu pintu di alur di atas).

## 8. Implementasi Tahap 4 (ringkas)

- `lib/services/admin_contact_config_service.dart`: `load()` menggabungkan panggilan paralel (satu `Future` in-flight).
- `main.dart`: `_setupAuthStateListener` tidak lagi memuat admin contact saat `user != null`; cukup `_initInBackground`, `await load()` di jalur SOS, dan `AdminContactWidget` memakai stream saja (tanpa `load()` di `initState`).

## 9. Implementasi Tahap 5 — observabilitas & Performance (ringkas)

**Tujuan:** konteks lapangan saat crash/ANR + metrik performa di Firebase, selaras Play Vitals.

| Area | Lokasi / perilaku |
|------|-------------------|
| **Crashlytics — breadcrumb & custom keys** | `lib/services/field_observability_service.dart`; dipanggil dari `driver_screen.dart` (`_scheduleFieldObservabilitySync`) dan `penumpang_screen.dart` (`_schedulePassengerFieldObservabilitySync`) pada tab, resume, dan perubahan navigasi. |
| **Trace startup** | `PerformanceTraceService.startStartupToInteractive` / `stopStartupToInteractive` (berhenti di login / home / onboarding / izin / maintenance / force-update). Atribut `version` & `build` dari `attachStartupAppVersion()`. |
| **Trace peta & order** | `passenger_map_ready`, `driver_map_ready`, `order_submit` di `performance_trace_service.dart`. |
| **Aktivasi Performance SDK** | `main.dart`: `FirebasePerformance.instance.setPerformanceCollectionEnabled(true)` setelah `runApp` (bersama pengumpulan Crashlytics). |
| **GA4 (analitik produk)** | Bukan init di `main`; dimensi kustom untuk admin: [`GA4_ADMIN_CUSTOM_DIMENSIONS.md`](GA4_ADMIN_CUSTOM_DIMENSIONS.md). |
| **Proses QA / Vitals** | Matriks perangkat, Android Vitals, ritual review mingguan: [`FIELD_OBSERVABILITY.md`](FIELD_OBSERVABILITY.md). |
