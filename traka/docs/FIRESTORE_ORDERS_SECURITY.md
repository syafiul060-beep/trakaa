# Keamanan Firestore: koleksi `orders`

## Ringkasan audit (2025-03)

| Area | Sebelum | Sesudah |
|------|---------|---------|
| Update order | Peserta (driver/penumpang/penerima) bisa mengubah **sembarang field** | Tetap peserta yang sama; **passengerUid, driverUid, receiverUid, orderType** tidak boleh diubah; **kirim_barang** tidak boleh `autoConfirmPickup` / `autoConfirmComplete` = true |
| Create order | Semua user login | Hanya jika **passengerUid == uid** pembuat; kirim barang tidak boleh bawa flag auto-konfirmasi palsu |

**Admin** (`users/{uid}.role == admin`) dapat **update** tanpa cek `orderUpdateIntegrity` — untuk koreksi manual / support.

## Yang masih mengandalkan aplikasi (bukan rules)

- Validasi **jarak** (radius berdekatan, menjauh), transisi **status**, dan isi **violation** tetap di `OrderService` / klien.
- Aturan Firestore **tidak** mengganti Cloud Function untuk logika bisnis penuh; ini lapisan **anti-tamper** terhadap field identitas dan flag auto-konfirmasi.

## Saran lanjutan (hardening)

1. **Cloud Functions (callable)** — opsional untuk transisi status penuh di server; saat ini aturan Firestore + `OrderService` + trigger di bawah sudah mengurangi risiko utama.
2. **`scan_audit_log`** — **sudah aktif:** trigger `onOrderUpdatedScan` menulis log untuk scan barcode **dan** untuk **`auto_confirm_pickup` / `auto_confirm_complete`** (travel, tanpa scan). Lihat [`SCAN_AUDIT_LOG.md`](SCAN_AUDIT_LOG.md).
3. **Uji regresi** — setelah deploy rules/functions: lihat bagian **E** (barcode & auto) di [`QA_REGRESI_ALUR_UTAMA.md`](QA_REGRESI_ALUR_UTAMA.md).

## Deploy rules & functions

Dari folder `traka` (tempat `firebase.json`):

```bash
firebase deploy --only firestore:rules
firebase deploy --only functions:onOrderUpdatedScan
```

Atau sekaligus: `firebase deploy --only firestore:rules,functions` (hati-hati durasi & kuota).

Setelah mengubah **`onOrderUpdatedScan`** (audit auto-konfirmasi), wajib deploy functions agar `scan_audit_log` mencatat `auto_confirm_*`.

## Rujukan kode

- Helper rules: `firestore.rules` — `orderUpdateIntegrity`, `kirimBarangNoAutoConfirmFlags`, `validNewOrderNoKirimAutoConfirm`.
- Logika bisnis: `lib/services/order_service.dart` — `driverConfirmPickupNoScan`, `completeOrderWhenFarApart`, `passengerConfirmArrivalNoScan`.
