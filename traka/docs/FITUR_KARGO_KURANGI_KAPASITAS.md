# Fitur Kargo Mengurangi Kapasitas Penumpang

## Ringkasan

Order **kargo** (barang besar) mengurangi kapasitas penumpang yang ditampilkan. **Dokumen** tidak mengurangi.

## Logika

- **Dokumen**: 0 slot (tidak mengurangi kapasitas)
- **Kargo**: X slot per order (default 1, konfigurasi di app_config)
- **Sisa kursi** = maxPassengers - totalPenumpang - (kargoCount × kargoSlotPerOrder)

## Konfigurasi

`app_config/settings`:
- `kargoSlotPerOrder` (number): default 1. Bisa diubah ke 0.5, 2, dll.

## Perubahan

| Area | Perubahan |
|------|-----------|
| **driver_status.currentPassengerCount** | Sekarang = penumpang + slot kargo |
| **Cari driver (penumpang)** | Sisa kursi sudah kurangi kargo |
| **Pesan nanti (jadwal)** | Tampilan "Sisa X kursi" dengan kargo |
| **Data Order (stream)** | Update count saat order berubah |
| **Pindah jadwal** | Validasi kapasitas pakai slot terpakai |

## File

- `lib/services/app_config_service.dart` – getKargoSlotPerOrder()
- `lib/services/order_service.dart` – getScheduledBookingCounts (kargoCount), countUsedSlotsForRoute
- `lib/screens/driver_screen.dart` – _updateDriverStatusToFirestore
- `lib/screens/data_order_driver_screen.dart` – stream listener
- `lib/screens/pesan_screen.dart` – tampilan sisa kursi
- `lib/screens/driver_jadwal_rute_screen.dart` – validasi pindah jadwal
