# Review & Saran: Database sampai Program Terakhir

Dokumen ini berisi hasil pengecekan dari database (schema, migrasi) sampai program aplikasi. **Implementasi selesai** (Feb 2025).

---

## 1. Database: schema.sql (PostgreSQL)

### 1.1 Field yang Kurang di Tabel `orders`

Bandingkan dengan `OrderModel` di Flutter dan data Firestore. Field berikut **ada di OrderModel/Firestore** tapi **belum ada di schema.sql**:

| Field | Tipe | Keterangan |
|-------|------|------------|
| `receiverLastReadAt` | TIMESTAMPTZ | Waktu penerima terakhir baca chat (badge unread kirim barang) |
| `driverBarcodePickupPayload` | TEXT | Payload barcode driver fase PICKUP (untuk scan penjemputan) |
| `passengerScannedPickupAt` | TIMESTAMPTZ | Waktu penumpang scan barcode PICKUP (konfirmasi jemput) |
| `destinationValidationLevel` | TEXT | Level validasi lokasi: 'desa' \| 'kecamatan' \| 'kabupaten' \| 'provinsi' |
| `ferryDistanceKm` | DOUBLE PRECISION | Jarak kapal laut (km) yang dikurangi dari tripDistanceKm |
| `tripBarangFareRupiah` | DOUBLE PRECISION | Kontribusi kirim barang (jarak efektif × tarif provinsi) |

**Saran:** Tambahkan semua field di atas ke `schema.sql` agar schema selaras dengan Firestore dan OrderModel.  
**Status:** ✅ Sudah ditambahkan.

---

## 2. Script Migrasi: migrate-firestore-to-pg.js

### 2.1 Field yang Belum Di-migrate

Script saat ini **tidak** memindahkan field berikut dari Firestore ke PostgreSQL:

- `receiverLastReadAt`
- `driverBarcodePickupPayload`
- `passengerScannedPickupAt`
- `destinationValidationLevel`
- `ferryDistanceKm`
- `tripBarangFareRupiah`

**Saran:** Setelah menambah kolom di schema.sql, update `migrate-firestore-to-pg.js` agar INSERT/UPDATE mencakup field-field tersebut.  
**Status:** ✅ Sudah di-update. Users: region, latitude, longitude. Orders: semua field baru.

---

## 3. Firestore Rules

- Rules untuk `orders` sudah mengizinkan update oleh `receiverUid` (penerima kirim barang).
- `receiverLastReadAt` akan ter-update normal lewat rules yang ada.
- **Tidak perlu perubahan** di Firestore rules untuk fitur badge unread receiver.

---

## 4. traka-api (Backend Node.js)

- Endpoint `GET /api/orders` dan `GET /api/orders/:id` memakai `SELECT * FROM orders`.
- Jika kolom ditambah di schema.sql, hasil query otomatis menyertakan kolom baru.
- **Saran:** Pastikan schema.sql sudah di-update dan dijalankan ulang (migration) sebelum deploy, agar API mengembalikan data lengkap.

---

## 5. Aplikasi Flutter (OrderModel, OrderService, Chat)

### 5.1 Yang Sudah Benar

- `OrderModel` punya `receiverLastReadAt`, `driverBarcodePickupPayload`, `passengerScannedPickupAt`, `destinationValidationLevel`, `ferryDistanceKm`, `tripBarangFareRupiah`.
- `OrderService.setReceiverLastReadAt()` sudah dipakai di `ChatRoomPenumpangScreen`.
- `ChatBadgeService` untuk optimistic update badge sudah dipakai di penumpang dan driver.
- Logika unread di `penumpang_screen.dart` dan `driver_screen.dart` sudah memakai `receiverLastReadAt` untuk penerima kirim barang.

### 5.2 Saran Tambahan (Opsional)

1. **chatHiddenByReceiver**  
   Saat ini hanya ada `chatHiddenByPassenger` dan `chatHiddenByDriver`. Jika penerima (receiver) kirim barang juga perlu opsi "sembunyikan chat", bisa ditambah field `chatHiddenByReceiver` di OrderModel, schema, dan migrate script.  
   **Status:** ✅ Sudah ditambahkan. OrderModel, schema, migrate, OrderService.hideChatForReceiver, streamOrdersForReceiver(includeHidden), ChatRoomPenumpangScreen.

2. **Index untuk query unread**  
   Jika nanti ada query khusus untuk unread (misalnya di API), pertimbangkan index pada `lastMessageAt`, `passengerLastReadAt`, `receiverLastReadAt`, `driverLastReadAt` jika volume order besar. Untuk saat ini, query dari Flutter ke Firestore/API masih wajar tanpa index tambahan.

---

## 6. Dokumen Lain

### 6.1 ANALISIS_PROFITABILITAS_HARGA.md

- Sudah lengkap dan konsisten.
- Saran di dokumen: perjelas di UI bahwa "Kontribusi Aplikasi" adalah referensi tarif, pembayaran via Google Play per kapasitas. Bisa dijadikan task terpisah untuk perbaikan copy/UI.

### 6.2 MIGRATION_HYBRID.md

- Panduan migrasi hybrid sudah jelas.
- Jika nanti orders pindah ke PostgreSQL, pastikan schema.sql dan migrate script sudah di-update sesuai poin 1 dan 2 di atas.

---

## 7. Ringkasan Prioritas

| Prioritas | Item | File | Keterangan |
|-----------|------|------|-------------|
| **Tinggi** | Tambah `receiverLastReadAt` | schema.sql, migrate-firestore-to-pg.js | ✅ Selesai |
| **Sedang** | Tambah field lain yang kurang | schema.sql, migrate-firestore-to-pg.js | ✅ Selesai |
| **Rendah** | chatHiddenByReceiver | OrderModel, schema, migrate, OrderService | ✅ Selesai |
| **Opsional** | Perjelas "Kontribusi Aplikasi" di UI | UI driver | Sesuai saran di ANALISIS_PROFITABILITAS_HARGA.md |

---

*Dokumen ini dibuat dari hasil pengecekan kode dan konfigurasi. Implementasi selesai Feb 2025.*
