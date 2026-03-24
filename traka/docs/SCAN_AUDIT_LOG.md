# Scan Audit Log

## Deskripsi

Collection `scan_audit_log` mencatat setiap scan barcode untuk investigasi dan monitoring jangka panjang. Dibuat otomatis oleh Cloud Function `onOrderUpdatedScan` saat order di-update dengan field scan.

## Struktur Dokumen

Setiap dokumen berisi:

| Field | Tipe | Keterangan |
|-------|------|------------|
| `orderId` | string | ID order |
| `scanType` | string | `pickup` \| `complete` \| `receiver` \| `driver_pickup` \| `auto_confirm_pickup` \| `auto_confirm_complete` |
| `scannedBy` | string | `passenger` \| `receiver` \| `driver` \| `system` |
| `passengerUid` | string? | UID penumpang (jika ada) |
| `driverUid` | string? | UID driver |
| `receiverUid` | string? | UID penerima (untuk kirim barang) |
| `pickupLat` | number? | Latitude titik jemput |
| `pickupLng` | number? | Longitude titik jemput |
| `dropLat` | number? | Latitude titik turun (complete/receiver) |
| `dropLng` | number? | Longitude titik turun |
| `tripDistanceKm` | number? | Jarak perjalanan (km) |
| `tripFareRupiah` | number? | Tarif perjalanan (travel) |
| `tripBarangFareRupiah` | number? | Tarif kirim barang |
| `driverViolationFee` | number? | Denda driver (auto_confirm_pickup, travel) |
| `passengerViolationFee` | number? | Denda penumpang (auto_confirm_complete, travel) |
| `orderType` | string | `travel` \| `kirim_barang` |
| `status` | string | Status order setelah scan |
| `timestamp` | Timestamp | Waktu scan |

## Jenis Scan

| scanType | scannedBy | Trigger |
|----------|------------|---------|
| `pickup` | passenger | passengerScannedPickupAt di-set |
| `complete` | passenger | passengerScannedAt di-set (travel selesai) |
| `receiver` | receiver | receiverScannedAt di-set (kirim barang diterima) |
| `driver_pickup` | driver | driverScannedAt di-set (legacy) |
| `auto_confirm_pickup` | system | `autoConfirmPickup` baru true (travel, penjemputan tanpa scan) |
| `auto_confirm_complete` | system | `autoConfirmComplete` baru true (travel, selesai tanpa scan / menjauh) |

## Keamanan

- **Tulis**: Hanya Cloud Function (Admin SDK). Client tidak bisa menulis.
- **Baca**: Hanya admin (role `admin` di users).

## Penggunaan

- **Investigasi**: Cek pola scan mencurigakan (jarak sangat pendek, lokasi tidak wajar).
- **Monitoring**: Query untuk analisis volume scan per hari/minggu.
- **Forensik**: Lacak siapa scan kapan untuk order tertentu.
