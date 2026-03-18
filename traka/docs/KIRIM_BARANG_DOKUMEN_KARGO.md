# Kirim Barang: Dokumen & Kargo

Fitur kirim barang kini memiliki kategori **Dokumen** dan **Kargo** dengan detail barang untuk kargo.

## Flow

1. Penumpang tap **Kirim Barang**
2. **Pilih jenis**: Dokumen / Kargo
3. Jika **Kargo**: isi nama barang, berat (0,1–100 kg), panjang, lebar, tinggi (cm). Maks: 300 cm per sisi, total P+L+T ≤ 400 cm
4. **Tautkan penerima** (email/telp)
5. Buat order → buka chat

## Field di Firestore (`orders`)

| Field | Tipe | Keterangan |
|-------|------|------------|
| `barangCategory` | string | `dokumen` \| `kargo` |
| `barangNama` | string | Nama/jenis barang (kargo) |
| `barangBeratKg` | number | Berat (kg) |
| `barangPanjangCm` | number | Panjang (cm) |
| `barangLebarCm` | number | Lebar (cm) |
| `barangTinggiCm` | number | Tinggi (cm), opsional |

## Chat otomatis

Pesan otomatis ke driver mencakup:
- Jenis: Dokumen / Kargo
- Detail barang (untuk kargo): nama, berat, dimensi
- Penerima, dari, tujuan

## Lacak Barang (CekLokasiBarangScreen)

Panel bawah menampilkan:
- **Jenis barang**: Dokumen / Kargo (dengan ikon)
- **Detail barang** (kargo): nama, berat, dimensi
- **Biaya Lacak Barang**: Pengirim Rp X (sudah/belum), Penerima Rp Y (sudah/belum)
- Lokasi driver, sisa jarak, ETA

## Ikon

- **Dokumen**: `Icons.mail_outline`
- **Kargo**: `Icons.inventory_2_outlined`

## Riwayat penerima

Pengirim bisa pilih penerima dari **riwayat** (order kirim barang sebelumnya) tanpa ketik ulang. Daftar muncul di atas form input, horizontal scroll, max 10 penerima unik terurut terbaru.

- Data dari `OrderService.getRecentReceivers(passengerUid)`
- Index Firestore: `passengerUid` + `orderType` + `createdAt` (desc)
- Deploy index: `firebase deploy --only firestore:indexes`

## Order lama (tanpa barangCategory)

Order kirim barang yang dibuat sebelum fitur ini **diperbarui** dengan saran berikut:

### 1. Tampilan (fallback di kode)
- Order tanpa `barangCategory` diperlakukan sebagai **Kargo**
- Label: "Kirim Barang (Kargo)", ikon kotak
- Berlaku sebelum migrasi dijalankan

### 2. Migrasi Firestore
Jalankan Cloud Function **`migrateKirimBarangCategory`** sekali untuk mengisi `barangCategory: 'kargo'` pada order lama:

1. Deploy functions: `firebase deploy --only functions`
2. Buka Firebase Console → Functions
3. Panggil `migrateKirimBarangCategory` (via REST/Postman atau buat tombol di admin)
4. Atau dari Flutter (user harus login):
   ```dart
   final result = await FirebaseFunctions.instance
       .httpsCallable('migrateKirimBarangCategory')
       .call();
   // result.data = { success: true, updated: N }
   ```

Setelah migrasi, semua order kirim barang lama akan punya `barangCategory: 'kargo'` di Firestore.

---

## Saran: Foto Barang & Bukti Penerima

### Foto barang (opsional, fase berikutnya)

- **Pengirim upload foto** saat buat order (kargo): membantu driver/receiver tahu tampilan barang.
- Simpan URL di `barangFotoUrl` (Firebase Storage).
- Bisa ditampilkan di chat dan layar Lacak Barang.

### Foto bukti penerima (opsional, fase berikutnya)

- **Penerima upload foto** saat scan barcode terima barang: bukti barang diterima.
- Perlu field `receiverProofPhotoUrl` dan flow upload setelah scan.
- Lebih kompleks; bisa dipertimbangkan untuk fase 2.
