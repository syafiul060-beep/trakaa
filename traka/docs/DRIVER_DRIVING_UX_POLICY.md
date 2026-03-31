# Kebijakan UX driver — prioritas saat mengemudi

Tujuan: aman dipakai sambil jalan; minim lapisan suara dan minim layar penuh yang mengalihkan perhatian dari jalan.

Implementasi terkait: `lib/services/driver_driving_ux_service.dart`, `lib/services/fcm_service.dart`, `lib/services/notification_navigation_service.dart`, `lib/screens/driver_screen.dart`.

## Kapan “konteks perhatian tinggi”

Aktif jika **salah satu**:

- Driver sedang **navigasi ke jemput/antar** (`navigatingToOrder`), atau
- **Banner turn-by-turn** (TBT) navigasi premium tampil (ada langkah rute + chrome TBT).

`DriverDrivingUxService.syncDriverMapState` di-set dari layar driver; saat app **paused**, konteks direset agar notifikasi di background tetap bisa memakai suara channel bawaan.

## Dialog penuh vs banner / non-blocking

| Situasi | Yang diutamakan | Catatan |
|--------|------------------|--------|
| Konteks perhatian tinggi | **Banner**, **chip**, **snack ringkas**, atau **bottom sheet setengah** | Hindari `AlertDialog` / route fullscreen untuk chat & pesanan rutin. |
| Chat / pesanan baru (in-app) | **SnackBar mengambang** dengan aksi “Buka …” | Saat konteks tinggi: **jangan** tampilkan snack (ganggu TBT). |
| Verifikasi admin / gate legal | Dialog tetap boleh | Jarang, kritis. |
| Panggilan suara (`voice_call`) | **Tetap interuptif** (prioritas keselamatan komunikasi) | Tidak dialihkan ke tab saja. |
| Setelan / premium / konfirmasi berhenti kerja | Dialog boleh di luar konteks navigasi aktif | Sebaiknya saat berhenti atau tab non-peta. |

*Dialog yang sudah ada di alur lama tidak dihapus massal; kebijakan ini mengarahkan perilaku **notifikasi** dan **hint in-app** saat mengemudi.*

## Alur notifikasi → tab (driver)

- **Biasa (bukan konteks tinggi):** tap notifikasi chat/order → buka **ruang chat** / alur existing (`ChatDriverScreen` push).
- **Konteks tinggi:** tap notifikasi **chat** → pindah ke **tab Chat** lalu **buka room** untuk `orderId` di payload (satu kali); **order / order_agreed** → **tab Pesanan** — **tanpa** push chat di atas peta navigasi.

## Suara: TTS navigasi vs notifikasi

- Saat konteks tinggi + app **foreground**: notifikasi lokal chat/pesanan dibuat **tanpa suara dan tanpa getar** (`playSound: false`, `enableVibration: false` di Android; `presentSound: false` di iOS) agar tidak bertabrakan dengan **TTS arahan**.
- TTS **tidak** di-stop jika notifikasi tenang (panduan tetap jalan).
- Jika notifikasi **tidak** tenang (driver tidak dalam konteks tinggi), TTS di-**stop** sebelum menampilkan notifikasi bersuara agar tidak dua sumber bersamaan.

## Voice call & admin

- Tetap memakai saluran / prioritas existing (bisa bersuara).
- `admin_verification` tetap membuka tab Profil lewat callback terdaftar.
