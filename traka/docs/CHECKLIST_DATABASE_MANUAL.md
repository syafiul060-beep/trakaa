# Checklist Perubahan Database Manual

Dokumen ini berisi langkah-langkah **manual** yang perlu Anda lakukan di database setelah perubahan kode hari ini. Sesuaikan dengan skenario Anda (hanya Firestore, atau Firestore + PostgreSQL hybrid).

---

## Skenario A: Hanya Pakai Firestore (Default)

Jika aplikasi **tidak** memakai traka-api / PostgreSQL (`TRAKA_USE_HYBRID` = false atau tidak di-set):

### 1. Firestore — Tidak Perlu Perubahan Schema

Firestore **schemaless**. Field baru (`receiverLastReadAt`, `chatHiddenByReceiver`, dll.) akan **otomatis muncul** saat aplikasi menulis data. **Tidak ada migrasi manual.**

### 2. Firestore Rules — Cek & Deploy

**Cek:** Apakah `firestore.rules` di project sudah lengkap?

- Buka `traka/firestore.rules`
- Bandingkan dengan `traka/docs/FIRESTORE_RULES_LENGKAP.txt`
- Pastikan ada rules untuk:
  - `contribution_payments` (jika pakai pembayaran kontribusi driver)
  - `verification_code_attempts` (jika pakai Cloud Function verifikasi email)

**Deploy rules:**
```bash
cd traka
firebase deploy --only firestore:rules
```

### 3. Firestore Indexes — Cek & Deploy

**Cek:** Apakah semua index sudah ada?

- Buka Firebase Console → Firestore → **Indexes**
- Pastikan index dari `firestore.indexes.json` status **Enabled**
- Jika muncul error **"The query requires an index"** saat pakai fitur penerima (receiver), buka link di error untuk buat index, atau tambahkan ke `firestore.indexes.json`:

```json
{
  "collectionGroup": "orders",
  "queryScope": "COLLECTION",
  "fields": [
    {"fieldPath": "receiverUid", "order": "ASCENDING"},
    {"fieldPath": "status", "order": "ASCENDING"}
  ]
}
```

**Deploy indexes:**
```bash
cd traka
firebase deploy --only firestore:indexes
```

### 4. Admin User (Opsional)

Jika belum ada admin:

- Firebase Console → Firestore → Collection `users`
- Pilih dokumen user yang akan jadi admin
- Tambah field: `role` = `"admin"` (string)

---

## Skenario B: Pakai traka-api + PostgreSQL (Hybrid)

Jika aplikasi memakai **traka-api** dengan PostgreSQL (Supabase):

### 1. PostgreSQL — Pilih Salah Satu

#### Opsi B1: Database Baru (Belum Pernah Jalankan schema.sql)

1. Buka **Supabase Dashboard** → project Anda → **SQL Editor**
2. Buka file `traka-api/scripts/schema.sql`
3. Copy seluruh isi, paste ke SQL Editor
4. Klik **Run**

#### Opsi B2: Database Sudah Ada (Tabel users & orders Sudah Ada)

1. Buka **Supabase Dashboard** → **SQL Editor**
2. Buka file `traka-api/scripts/migrate-add-order-fields.sql`
3. Copy seluruh isi, paste ke SQL Editor
4. Klik **Run**

Script ini menambah kolom:
- **users:** `region`, `latitude`, `longitude`
- **orders:** `chatHiddenByReceiver`, `receiverLastReadAt`, `driverBarcodePickupPayload`, `passengerScannedPickupAt`, `destinationValidationLevel`, `ferryDistanceKm`, `tripBarangFareRupiah`
- **Index:** `idx_orders_receiver`

### 2. Migrasi Data Firestore → PostgreSQL (Opsional)

Jika ingin **memindahkan** data dari Firestore ke PostgreSQL:

1. Pastikan `.env` di `traka-api/` berisi:
   - `DATABASE_URL` (connection string Supabase)
   - `FIREBASE_SERVICE_ACCOUNT_PATH` (path ke file JSON service account)

2. Jalankan:
   ```bash
   cd traka-api
   node scripts/migrate-firestore-to-pg.js
   ```

3. Cek tabel `users` dan `orders` di Supabase Table Editor

---

## Ringkasan Cepat

| Skenario | Yang Perlu Dilakukan |
|----------|------------------------|
| **Hanya Firestore** | 1) Deploy rules & indexes jika belum. 2) Cek admin user. **Tidak perlu** migrasi schema. |
| **Firestore + PostgreSQL (DB baru)** | Jalankan `schema.sql` di Supabase SQL Editor |
| **Firestore + PostgreSQL (DB lama)** | Jalankan `migrate-add-order-fields.sql` di Supabase SQL Editor |
| **Pindah data ke PostgreSQL** | Jalankan `node scripts/migrate-firestore-to-pg.js` |

---

## Verifikasi

### Firestore
- Login sebagai penumpang → buka chat order kirim barang sebagai penerima → badge unread hilang setelah dibaca
- Login sebagai penerima → buka chat → tombol "Hapus chat" (jika order dibatalkan) berfungsi

### PostgreSQL (jika pakai)
- Supabase → Table Editor → `orders` → pastikan kolom `receiverLastReadAt`, `chatHiddenByReceiver`, dll. ada
- API `GET /api/orders/:id` mengembalikan data lengkap

---

*Dokumen ini dibuat berdasarkan perubahan kode Feb 2025.*
