# Siklus GPS & pelacakan Traka (referensi internal)

Dokumen ringkas untuk **engineering / support**: kapan lokasi ditulis ke Firestore, kapan berhenti, dan event analytics terkait.

## Driver (`driver_status`)

| Kondisi | Pembaruan titik ke Firestore |
|--------|------------------------------|
| Siap Kerja (`_isDriverWorking`) atau navigasi jemput (`_navigatingToOrderId`) | Ya, dengan throttle di `_applyDriverGpsPosition` |
| Tidak aktif + app **foreground** | Polling lokasi jarang untuk peta; **tidak** menulis pelacakan |
| Tidak aktif + app **background** (minimize / layar mati) | **Tidak** ada timer polling GPS |

Tombol selesai kerja memicu `removeDriverStatus` / update tidak aktif.

## Penumpang / pengirim / penerima

| Peran | Kapan push lokasi |
|-------|-------------------|
| Pengirim / penumpang | `agreed`, belum konfirmasi jemput; travel & kirim barang (gate jadwal + `driver_status` jika terjadwal) |
| Penerima (kirim barang) | `picked_up`, belum scan terima, belum selesai |

Stream: `LocationService.orderParticipantLocationSharingStream` (foreground service Android bila sistem mewajibkan). Dibatalkan jika tidak ada order eligible (`PassengerProximityNotificationService`).

## Firebase Analytics (custom)

| Event | Parameter | Kapan |
|-------|-----------|--------|
| `lacak_help_open` | `audience` | User membuka bottom sheet penjelasan (`lacakDriverMap`, `lacakBarangMap`, `profilePenumpang`, `profileDriver`) |
| `driver_tracking_stopped` | `reason` (`end_work`, `became_inactive`), `in_background` (opsional) | Transisi pelacakan driver mati |
| `passenger_share_stopped` | `reason` (`no_eligible_orders`, `logout`) | Stream share penumpang/penerima berhenti |
| `lacak_stale_banner_shown` | `flow`, `reason` | Sudah ada; banner peta lacak data tidak segar |

**Admin — laporan GA4 (Explorations):** daftarkan parameter di atas sebagai **Custom dimension** (satu kali di konsol GA4). Panduan: [`GA4_ADMIN_CUSTOM_DIMENSIONS.md`](./GA4_ADMIN_CUSTOM_DIMENSIONS.md).

## Retensi data lokasi (rekomendasi opsional)

Field sensitif yang bisa dibersihkan setelah order selesai (mis. Cloud Function terjadwal atau aturan TTL):

- `passengerLiveLat` / `passengerLiveLng` / `passengerLiveUpdatedAt`
- `receiverLiveLat` / `receiverLiveLng` / `receiverLiveUpdatedAt`

`passengerLat` / `receiverLat` sering dipakai riwayat; kebijakan penghapusan harus selaras produk & hukum.

## OEM / perangkat

Beberapa merek (hemat baterai agresif) dapat membekukan app di latar belakang walau sudah Siap Kerja — dokumentasikan di tiket dukungan dengan merek/model.
