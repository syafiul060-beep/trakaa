# Alur Kirim Barang – Sinkronisasi

## Dua Jalur Masuk

### 1. Dari Cari Travel (penumpang_screen.dart)
```
Tap driver → Kirim Barang → KirimBarangPilihJenisSheet → KirimBarangLinkReceiverSheet
```
- Driver: `ActiveDriverRoute` (dari peta)
- Asal/tujuan: dari input penumpang

### 2. Dari Pesan Nanti / Jadwal (pesan_screen.dart)
```
Tap Kirim Barang → KirimBarangPilihJenisSheet → _KirimBarangLinkReceiverSheetJadwal
```
- Driver: dari jadwal (driverUid, scheduleId, scheduledDate)
- Asal/tujuan: dari rute jadwal

## Step Tautkan Penerima (sama di kedua jalur)

1. **Riwayat penerima** – pilih dari order kirim barang sebelumnya
2. **Kontak HP** – `showReceiverContactPicker` → hanya tampil kontak terdaftar Traka
3. **Manual** – ketik nomor → Cari → `OrderService.findUserByEmailOrPhone`

## Validasi (kedua sheet)

- Penerima ≠ pengirim
- **Validasi ulang** sebelum create order: cek `users/{uid}` masih ada
- Jika tidak ada: error "Penerima tidak ditemukan. Pilih ulang dari kontak."

## Picker Kontak (receiver_contact_picker.dart)

- **Hanya menampilkan** kontak yang terdaftar di Traka (seperti WhatsApp)
- Cek via Cloud Function `checkRegisteredContacts`
- Jika tidak ada kontak terdaftar: "Belum ada kontak yang terdaftar di Traka. Minta penerima mendaftar di Traka terlebih dahulu."

## Estimasi Biaya

- **KirimBarangLinkReceiverSheet** (dari Cari Travel): tampilkan "Estimasi Lacak Barang: Rp X" jika ada origin/dest koordinat
- Fallback: "Rp 10.000 - Rp 25.000"

## Lokasi Penerima (wajib)

- Saat penerima tap **Setuju**, dialog minta lokasi
- **Gunakan lokasi saya** → ambil GPS → simpan receiverLat, receiverLng, receiverLocationText
- Lokasi dipakai untuk validasi scan barcode saat barang sampai

## Notifikasi

- **Barang dijemput**: saat pengirim scan barcode pickup, penerima dapat notifikasi "Barang sudah dijemput. Driver telah menerima barang dari pengirim. Lacak perjalanan di aplikasi."

## Create Order

- `OrderService.createOrder` dengan `receiverUid`, `receiverName`, `receiverPhotoUrl`
- Status awal: `pending_receiver` (tunggu penerima setuju)
- Setelah setuju: `pending_agreement` → order muncul ke driver
