# Alur penumpang & driver — perbaikan yang diterapkan (referensi)

Dokumen ini mengaitkan **enam tahap** perbaikan alur produk dengan implementasi di repo.

## Ringkasan implementasi (kode)

| Tahap | Isi | Yang dilakukan |
|-------|-----|----------------|
| **1 — Satu sumber status** | Beranda penumpang vs status order | `OrderService.isTravelOrderBlockingPassengerHomeMap` + `passengerOrdersContainBlockingTravel` — semua logika blokir travel di beranda memakai ini. |
| **2 — Transisi & error** | State segar setelah kembali dari background | `PenumpangScreen`: `AppLifecycleState.resumed` memanggil `_checkActiveTravelOrder()` agar overlay tidak “nempel” setelah order selesai di tab lain. |
| **3 — Kesepakatan → jalan** | Blokir beranda setelah sepakat | Blokir beranda **hanya** `agreed` / `picked_up`; **`pending_agreement`** tidak memblokir (penumpang bisa cari driver lain sampai harga disepakati). |
| **4 — Selesai & bersih** | Hilangkan blok setelah selesai | `completed` / `cancelled` eksplisit tidak memblokir (di helper). Stream pesanan tetap memicu refresh. |
| **5 — Batal & aturan** | Arah ke tindakan | Tombol **“Buka Pesanan”** pada overlay membuka tab Pesanan (index 3) untuk batalkan/selesaikan lewat alur yang ada. |
| **6 — Travel vs kirim barang** | Cakupan blokir | Blokir beranda **hanya `orderType` travel**. Kirim barang tidak memblokir beranda (tetap bisa cari travel dari peta kecuali kebijakan produk berubah). |

## API publik baru (`OrderService`)

- `isTravelOrderBlockingPassengerHomeMap(OrderModel)` — blokir beranda penumpang **hanya** jika travel `agreed` / `picked_up` (bukan `pending_agreement`).
- `passengerOrdersContainBlockingTravel(Iterable<OrderModel>)` — cek daftar.
- `isTravelOrderInProgressForNotifications(OrderModel)` — travel `agreed`/`picked_up` (untuk reuse notifikasi/UI lain jika perlu).
- `computeJarakKontribusiPreview(...)` → `JarakKontribusiPreview?` — data untuk teks chat pertama (jarak/kontribusi).

## Teks UI

- `activeTravelOrderMessage` / `activeTravelOrderHint` / `activeTravelOrderOpenOrders` di `app_localizations.dart` diselaraskan dengan perilaku baru.

## Pesan chat pertama: jarak & estimasi kontribusi

- **Beranda / koordinat lengkap**: `OrderService.computeJarakKontribusiPreview` menghitung jarak garis lurus, segmen laut (jika ada), dan estimasi kontribusi driver dengan aturan yang sama seperti dialog driver. Teks di chat dibentuk oleh `PassengerFirstChatMessage.formatJarakKontribusiLines` dan mengikuti bahasa UI (`AppLocalizations`).
- **Saat menghitung estimasi** (setelah order dibuat, ada koordinat atau geocode): dialog `runWithEstimateLoading` + teks `calculatingEstimate` (ID/EN).
- **Koordinat ada tetapi estimasi gagal** (mis. jarak sangat pendek): satu baris fallback `chatPreviewEstimateUnavailable`.
- **Pesan terjadwal** (tanpa koordinat di order): `JarakKontribusiScheduleEstimate.chatBlockFromAddressTexts` mencoba **geocode paralel** asal/tujuan lalu hitung kontribusi; **timeout** (`JarakKontribusiScheduleEstimate.computeTimeout`, 15 detik) → fallback `chatScheduledEstimateNote`. Event analytics: `chat_estimate_scheduled` (`outcome`: `numeric` \| `fallback_geocode` \| `unavailable_short` \| `empty_address` \| `timeout` \| `error`).
- Angka di chat adalah **perkiraan**; ongkos final tetap lewat kesepakatan di chat.

## Sisa / iterasi (belum diubah di kode)

- **Driver app**: aturan “boleh mulai rute baru” tetap di layar driver; bisa disatukan dengan helper serupa di PR berikutnya.
- **Notifikasi jarak** (`PassengerProximityNotificationService`): masih memakai filter status lama **semua tipe order** — sengaja tidak diubah agar kirim barang tidak regresi.
- **Kebijakan kirim barang memblokir beranda**: jika produk meminta, tambahkan cabang di helper dan update l10n.

## Rujukan

- [`KEBIJAKAN_ICON_MOBIL_DAN_OVERLAY.md`](KEBIJAKAN_ICON_MOBIL_DAN_OVERLAY.md) — ikon & peta.
- [`CHECKLIST_ICON_MOBIL_PETA_PENUMPANG.md`](CHECKLIST_ICON_MOBIL_PETA_PENUMPANG.md) — QA peta.
- [`QA_REGRESI_ALUR_UTAMA.md`](QA_REGRESI_ALUR_UTAMA.md) — skenario regresi manual.
- [`KEBIJAKAN_BLOKIR_BERANDA_DAN_ORDER.md`](KEBIJAKAN_BLOKIR_BERANDA_DAN_ORDER.md) — travel vs kirim barang.
- [`ROADMAP_INFRASTRUKTUR_SKALA.md`](ROADMAP_INFRASTRUKTUR_SKALA.md) — kapan naikkan infrastruktur.
- API: [`../traka-api/docs/MONITORING_PRODUCTION.md`](../traka-api/docs/MONITORING_PRODUCTION.md)
