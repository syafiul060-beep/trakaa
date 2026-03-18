# Review: Kirim Barang (Update) & Database

Dokumen ini memeriksa integrasi fitur kirim barang yang telah diperbarui dan memberikan saran terkait database.

---

## 1. Cek Integrasi (Apakah Sudah Tersinkron)

### ✅ Sudah tersinkron

| Komponen | Status | Keterangan |
|----------|--------|------------|
| **OrderModel** | ✓ | Field: barangCategory, barangNama, barangBeratKg, barangPanjangCm, barangLebarCm, barangTinggiCm |
| **OrderService.createOrder** | ✓ | Menerima dan menyimpan semua field barang ke Firestore |
| **OrderService.getRecentReceivers** | ✓ | Riwayat penerima dari order kirim_barang |
| **OrderService.findUserByEmailOrPhone** | ✓ | Cari penerima by email/telp |
| **penumpang_screen** | ✓ | Flow: pilih jenis → form kargo (jika kargo) → tautkan penerima → create order |
| **pesan_screen** | ✓ | Flow sama untuk Pesan nanti (jadwal) |
| **kirim_barang_pilih_jenis_sheet** | ✓ | Widget pilih Dokumen/Kargo + form kargo |
| **receiver_contact_picker** | ✓ | Pilih penerima dari kontak HP |
| **cek_lokasi_barang_screen** | ✓ | Panel: jenis barang, detail, biaya pengirim/penerima |
| **chat_room_penumpang_screen** | ✓ | Ikon dokumen/kargo, label orderTypeDisplayLabel |
| **Cloud Functions** | ✓ | migrateKirimBarangCategory, verifyLacakBarangPayment, onOrderUpdatedScan |
| **Firestore indexes** | ✓ | orderType + passengerUid + createdAt (untuk getRecentReceivers) |
| **Firestore rules** | ✓ | receiverUid sudah di-handle untuk akses penerima |

### ⚠️ Belum diperbarui (minor)

| Komponen | Status | Saran |
|----------|--------|-------|
| **traka-admin OrderDetail** | Belum | Tampilkan barangCategory, barangNama, berat, dimensi untuk order kirim_barang |
| **traka-admin Orders list** | Belum | Bisa tambah kolom "Jenis" (Dokumen/Kargo) untuk kirim_barang |
| **FIRESTORE_RIWAYAT_DAN_PESANAN.md** | Belum | Tambah dokumentasi field barang di orders |
| **CHECKLIST_DATABASE_MANUAL** | Belum | Tambah field barang jika ada migrasi PostgreSQL |

---

## 2. Saran Database (Firestore)

### 2.1 Field orders untuk kirim barang (sudah ada)

| Field | Tipe | Wajib | Keterangan |
|-------|------|-------|------------|
| `orderType` | string | Ya | `kirim_barang` |
| `receiverUid` | string | Ya | UID penerima |
| `receiverName` | string | Ya | Nama penerima |
| `receiverPhotoUrl` | string | Opsional | Foto penerima |
| `receiverLat`, `receiverLng` | number | Opsional | Lokasi penerima |
| `receiverAgreedAt` | timestamp | Opsional | Waktu penerima setuju |
| `receiverScannedAt` | timestamp | Opsional | Waktu penerima scan (barang diterima) |
| `barangCategory` | string | Opsional* | `dokumen` \| `kargo` |
| `barangNama` | string | Opsional | Nama/jenis barang (kargo) |
| `barangBeratKg` | number | Opsional | Berat (kg) |
| `barangPanjangCm` | number | Opsional | Panjang (cm) |
| `barangLebarCm` | number | Opsional | Lebar (cm) |
| `barangTinggiCm` | number | Opsional | Tinggi (cm) |
| `passengerLacakBarangPaidAt` | timestamp | Opsional | Pengirim bayar Lacak Barang |
| `receiverLacakBarangPaidAt` | timestamp | Opsional | Penerima bayar Lacak Barang |
| `tripBarangFareRupiah` | number | Opsional | Kontribusi driver kirim barang |

\* Order lama bisa null; kode fallback ke "Kargo".

### 2.2 Index yang diperlukan

| Index | Query | Status |
|-------|-------|--------|
| orderType + passengerUid + createdAt | getRecentReceivers | ✓ Ada |
| orderType + receiverUid + receiverLacakBarangPaidAt | Lacak Barang (penerima) | ✓ Ada |
| orderType + passengerUid + passengerLacakBarangPaidAt | Lacak Barang (pengirim) | ✓ Ada |

### 2.3 Saran tambahan Firestore

1. **Tidak perlu index baru** untuk barangCategory – query saat ini tidak filter by kategori.
2. **Analitik nanti**: Jika ingin report "berapa order dokumen vs kargo", bisa query `orderType == 'kirim_barang'` lalu aggregate di client/Cloud Function.
3. **Firestore schema-less** – field baru otomatis diterima, tidak perlu migrasi manual.

---

## 3. Saran Database (PostgreSQL / traka-api)

Jika memakai **traka-api** dengan PostgreSQL (Supabase):

1. **Tambah kolom di tabel `orders`** (jika belum):
   - `barang_category` (varchar, nullable)
   - `barang_nama` (varchar, nullable)
   - `barang_berat_kg` (decimal, nullable)
   - `barang_panjang_cm` (decimal, nullable)
   - `barang_lebar_cm` (decimal, nullable)
   - `barang_tinggi_cm` (decimal, nullable)

2. **Script migrasi**: Buat `migrate-add-barang-fields.sql` jika ada sync Firestore → PostgreSQL.

3. **API**: Pastikan endpoint order detail mengembalikan field barang.

---

## 4. Checklist Sebelum Production

- [ ] Deploy Firestore indexes: `firebase deploy --only firestore:indexes`
- [ ] Jalankan migrasi `migrateKirimBarangCategory` sekali (untuk order lama)
- [ ] (Opsional) Update traka-admin OrderDetail untuk tampilkan detail barang
- [ ] (Jika pakai PostgreSQL) Tambah kolom barang di tabel orders
- [ ] Update dokumentasi FIRESTORE_RIWAYAT_DAN_PESANAN.md dengan field barang

---

## 5. Ringkasan

**Integrasi**: Fitur kirim barang (Dokumen/Kargo, riwayat penerima, detail barang) **sudah tersinkron** di app Flutter, Cloud Functions, dan Firestore.

**Database**: Firestore tidak perlu perubahan schema. Field baru otomatis tersimpan. Jika pakai PostgreSQL, tambah kolom barang.

**Admin**: OrderDetail di traka-admin bisa diperkaya dengan tampilan detail barang untuk order kirim_barang.
