# Peta areas bantuan teknis Traka (repo ↔ dokumen)

Dokumen ini mengikat **janji area bantuan** (arsitektur, fitur, stabilitas, keamanan, QA, strategi) ke **bukti konkret di codebase** dan **tindakan lanjutan** yang masuk akal. Dipakai sebagai indeks kerja untuk tim atau asisten AI di Cursor.

---

## 1. Arsitektur & alur data

### Satu sumber kebenaran (orders)

| Lapisan | Peran | Lokasi / catatan |
|--------|--------|------------------|
| **Firestore `orders/{id}`** | Sumber utama UI real-time (driver & penumpang) | `lib/services/order_service.dart`, streams di layar |
| **PostgreSQL (opsional)** | Dual-write saat hybrid + `DATABASE_URL` aktif | `traka-api/src/lib/order_create.js`, `insertOrderPostgres` |
| **API hybrid** | Create order dengan policy duplikat & verifikasi admin | `traka-api/src/routes/orders.js` — `assertPassengerNewOrderPolicyAllows`, `findDuplicatePendingFirestore` |

Konstanta status yang dipakai konsisten di klien: `OrderService.statusPendingAgreement`, `statusAgreed`, `statusPickedUp`, `statusCompleted`, `statusCancelled`, `statusPendingReceiver` (`order_service.dart`).

### Transisi status & “anti bentrok”

- **Aturan bisnis** (blokir peta penumpang, notifikasi, policy order baru) di-share lewat helper di `OrderService` (mis. `isTravelOrderBlockingPassengerHomeMap`, `passengerHomeMapBlockedReason`).
- **Firestore rules** (`firestore.rules` blok `orders`): integritas field inti **plus** **transisi `status`** terbatas untuk non-admin (`validOrderStatusTransition`). Lihat [`ORDER_STATUS_TRANSITIONS.md`](ORDER_STATUS_TRANSITIONS.md).
- **Implikasi:** client tidak bisa melompat ke `completed` dari `agreed` tanpa melewati `picked_up`. Admin tetap bisa memperbaiki dokumen manual.

### Jadwal vs order aktif

- **Jadwal:** `driver_schedules/{driverId}` + subkoleksi `schedule_items` — rules: baca semua user login, tulis driver pemilik atau admin.
- **Rute/lokasi aktif:** `driver_status/{driverId}` — tulis hanya driver sendiri.
- **Riwayat rute:** `route_sessions` — driver pemilik.

---

## 2. Fitur & UX (maps, jadwal, scan, notifikasi, offline)

| Area | Bukti di repo | Dokumen terkait |
|------|----------------|-----------------|
| Peta driver / navigasi | `lib/screens/driver_screen.dart`, layanan directions, premium nav | `DRIVER_NAVIGATION_BEHAVIOR.md` |
| Peta penumpang | `lib/screens/penumpang_screen.dart`, hybrid + realtime | `QA_HYBRID_REGRESI.md`, `AUDIT_DRIVER_STATUS_DAN_HYBRID.md` |
| Jadwal driver | `DriverJadwalRuteScreen`, `driver_schedules` | `QA_HYBRID_REGRESI.md`, indeks Firestore |
| Scan barcode & auto-konfirmasi | Field scan di `orders`, trigger Functions | `SCAN_AUDIT_LOG.md`, `functions/index.js` (onOrderUpdated scan + FCM) |
| Offline / cache rute | `OfflineNavRouteCacheService`, restore di driver | `OFFLINE_MAP.md`, Tahap 4 ringkas di QA |
| Notifikasi | FCM, `NotificationNavigationService` | `CEK_NOTIFIKASI_HP.md`, `CARA_CEK_CHAT_DAN_NOTIFIKASI.md` |

---

## 3. Stabilitas

| Item | Status di repo |
|------|----------------|
| Crashlytics fatal / non-fatal | `main.dart`, `app_logger.dart`, `navigation_diagnostics.dart`, `driver_hybrid_diagnostics.dart` |
| Breadcrumb konteks lapangan (tab + navigasi) | `field_observability_service.dart` + `driver_screen` / `penumpang_screen` | Lihat `FIELD_OBSERVABILITY.md` |
| Firebase Performance | `main.dart` — `setPerformanceCollectionEnabled(true)` |
| CI | `.github/workflows/traka_ci.yml` — analyze + `flutter test` + smoke build hybrid |

---

## 4. Keamanan & konsistensi

| Topik | Kondisi terkini (periksa deploy) | Rujukan |
|-------|----------------------------------|---------|
| **Storage chat** | Rules memakai `firestore.get` + `isOrderParticipant(orderId)` untuk `chat_audio` / `chat_images` / `chat_videos` | `storage.rules` — jika produksi sudah deploy ini, bagian “semua user bisa akses chat” di audit lama **sudah tidak berlaku** |
| **Firestore `counters`** | `allow write: if false` — hanya Admin SDK | `firestore.rules` (selaras saran audit untuk kunci tulis client) |
| **vehicle_brands** | `allow write: if isAdmin()` | `firestore.rules` |
| **Create order API** | `passengerUid` wajib sama token, policy duplikat, optional PG rollback | `traka-api` |
| **Idempotensi** | Partially: duplikat pending dicek; untuk aksi kritis lain pertimbangkan idempotency key di Function | Backlog |

**Audit nasional lengkap (termasuk regulasi, checklist):** `AUDIT_KESIAPAN_PRODUKSI_INDONESIA.md` — **sesuaikan checklist** dengan rules Storage/counters terbaru di repo sebelum rilis besar.

---

## 5. Dokumentasi & QA

| Dokumen | Isi singkat |
|---------|-------------|
| `QA_HYBRID_REGRESI.md` | Regresi hybrid + observabilitas `[DriverHybrid]` / `[Field]` |
| `AUDIT_DRIVER_STATUS_DAN_HYBRID.md` | Frekuensi tulis `driver_status` + dual-write API, rate limit, alur uji hybrid penuh |
| `FIELD_OBSERVABILITY.md` | Breadcrumb tab/navigasi + matriks perangkat + Android vitals |
| `BUILD_PLAY_STORE.md` | Build release, mapping Crashlytics |
| `CEK_STABILITAS_PRODUKSI.md` | Checklist stabilitas |
| `SCAN_AUDIT_LOG.md` | Forensik scan & auto-confirm |
| `AUDIT_SINKRON_APP_ADMIN.md` | Selaras admin panel vs app |

---

## 6. Diskusi strategi (tanpa kode)

- **MVP vs super-app:** Traka sudah punya travel + kirim barang + jadwal + chat + lacak; prioritas saat lonjakan user dari grup WA = **stabilitas + alur order** > fitur baru.
- **Definisi sukses terukur (contoh):** crash rate & ANR di bawah ambang Play, error rate `POST /api/orders`, waktu p95 load daftar order, keluhan “status tidak sama” mendekati nol.

---

## 7. Backlog prioritas (untuk iterasi berikutnya)

**P0 — sebelum/tepat setelah lonjakan traffic**

1. Pastikan **rules Firestore + Storage yang di repo** sudah **deploy** ke project Firebase produksi.
2. Pantau **kuota** Maps, Geocoding, Firestore read/write, Functions invocations.
3. **Phased rollout** Play Console + `min_version` / maintenance di `app_config` bila perlu.

**P1 — hardening data**

1. ~~Validasi **transisi `status` order**~~ — **Sudah:** `firestore.rules` (`validOrderStatusTransition`, `orderParticipantOrderUpdateValid`). Detail: [`ORDER_STATUS_TRANSITIONS.md`](ORDER_STATUS_TRANSITIONS.md).
2. ~~**Idempotensi** scan / complete / auto-konfirm~~ — **Sudah:** transaksi + no-op sukses; perbaikan **retry** `runTransaction` (reset flag `applied*` di awal callback) untuk cegah **ganda** `violation_records` / `outstandingViolation*` — [`ORDER_STATUS_TRANSITIONS.md`](ORDER_STATUS_TRANSITIONS.md) *Idempotensi*.

**P2 — produk**

1. Perdalam offline UX (sudah ada cache rute + precache OSM).
2. Uji beban ringan pada API hybrid (Railway) sesuai proyeksi grup.

---

## 8. Yang bisa dilakukan asisten AI di Cursor (checklist singkat)

- [ ] Telusuri alur tertentu (mis. scan → `picked_up`) dan laporkan file + risiko race.
- [ ] Usulkan patch rules / Function / API dengan diff terfokus.
- [ ] Tambah tes unit/widget pada service murni (tanpa Firebase live).
- [ ] Rapikan atau tambah dokumen QA/checklist (seperti file ini).
- [ ] Jalankan `dart analyze` / `flutter test` setelah perubahan.

**Di luar repo:** operasi WA, legal, SLA bisnis — tetap keputusan Anda; dukungan teknis lewat dokumen dan kode di atas.

---

*Terakhir diselaraskan dengan struktur repo Traka (Flutter app + `functions` + `traka-api`). Perbarui bagian “Kondisi terkini” jika project Firebase produksi berbeda dari branch ini.*
