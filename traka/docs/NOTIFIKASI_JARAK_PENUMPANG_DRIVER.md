# Notifikasi jarak driver → penumpang (tanpa tap “arahkan”)

## Ringkasan

| Pertanyaan | Jawaban |
|------------|---------|
| Apakah penumpang dapat notifikasi “driver mendekati” jika driver **tidak** tap arahkan ke lokasi penumpang? | **Ya.** Logika notifikasi **tidak** membaca `driverNavigatingToPickupAt` atau mode navigasi di HP driver. |
| Dari mana jarak dihitung? | Jarak lurus GPS driver (`driver_status` / stream API) ke titik jemput order (`originLat` / `originLng`). |
| Apa yang *dulu* hanya jalan setelah tap “arahkan”? | **Kirim lokasi live penumpang** ke Firestore setiap ~5 detik (`PassengerProximityNotificationService._startPassengerLocationStream`) — hanya saat `driverNavigatingToPickupAt != null`. Itu untuk peta driver, **bukan** untuk notifikasi jarak ke penumpang. |

## Threshold notifikasi (app penumpang)

File: `lib/services/passenger_proximity_notification_service.dart`

- **1 km** dan **500 m** (threshold 5 km sengaja dihapus untuk kurangi spam).
- Satu kali per threshold per order (disimpan di `_proximityNotified`).

## Agar notifikasi tepat waktu: update lokasi driver

Notifikasi memicu saat **stream** posisi driver melewati ambang. Jika posisi driver jarang di-push ke `driver_status`, penumpang bisa **melewat** loncatan 1 km / 500 m (mis. satu update loncat dari 3 km → 400 m).

**Perbaikan (Maret 2025):** tiga tier di `driver_screen` → `_shouldUpdateFirestore`:

| Kondisi | Throttle | Keterangan |
|--------|----------|------------|
| Navigasi ke order / penumpang sudah di mobil / kirim barang aktif | **50 m** atau **5 detik** | `shouldUpdateLocationForLiveTracking` — lacak penuh |
| Hanya **agreed menunggu jemput** (belum tap arahkan) | **300 m** atau **60 detik** | `shouldUpdateLocationForPickupProximity` — **hemat write**, tetap cukup untuk ambang 1 km / 500 m |
| Sisanya (rute kerja tanpa order jemput aktif) | **2 km** atau **15 menit** | `shouldUpdateLocation` |

## Saran operasional

- **CS:** jika penumpang tidak pernah dapat notifikasi jarak, cek: app penumpang dibuka pernah (`PassengerProximityNotificationService.start`), order status agreed + ada origin, driver **siap kerja** dan lokasi tidak mock.
- **Produk:** copy notifikasi ada di `RouteNotificationService` / channel `traka_route` (lihat `route_notification_service.dart`).
