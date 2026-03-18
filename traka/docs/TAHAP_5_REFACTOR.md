# Tahap 5: Refactor driver_screen & penumpang_screen

## Ringkasan

Widget overlay yang sebelumnya inline di `driver_screen.dart` dan `penumpang_screen.dart` diekstrak ke file terpisah untuk mengurangi ukuran file dan meningkatkan maintainability.

## File Baru

### lib/widgets/driver_map_overlays.dart

- **DriverRouteTapHint** – Petunjuk tap untuk pilih rute alternatif
- **DriverScheduledReminder** – Pengingat penumpang terjadwal
- **DriverWorkToggleButton** – Tombol Siap Kerja / Selesai Bekerja
- **DriverStartRouteButton** – Tombol "Mulai Rute ini"

### lib/widgets/penumpang_map_overlays.dart

- **PenumpangPesanNantiButton** – Tombol "Pesan nanti" (quick action ke Jadwal)
- **PenumpangSearchBar** – Bar pencarian (tap untuk buka form)
- **PenumpangSearchFailedBanner** – Banner gagal cari driver dengan tombol Coba lagi

## Manfaat

- **driver_screen.dart**: Berkurang ~200 baris (overlay diekstrak)
- **penumpang_screen.dart**: Berkurang ~130 baris (overlay diekstrak)
- Widget overlay dapat di-reuse atau di-test terpisah
- Kode lebih modular dan mudah dibaca

## ChatMessageContent (Refactor Tahap 5 Audit)

Widget pesan chat diekstrak ke `lib/widgets/chat_message_content.dart` – dipakai di chat_room_penumpang_screen dan chat_driver_screen. Kurangi ~400 baris duplikat. Lihat `docs/REFACTOR_7_TAHAP.md` Tahap 5.

## Catatan

File utama masih besar (~4400 baris driver, ~3500 baris penumpang) karena logic kompleks (markers, polylines, state management). Refactor lebih lanjut dapat dilakukan bertahap untuk:
- `_buildMarkers()` → helper class terpisah
- `_buildPolylines()` → helper class terpisah
- Bottom sheet form → widget terpisah
