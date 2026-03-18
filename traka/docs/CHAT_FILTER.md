# Filter Chat – Mencegah Pengguna Diarahkan ke Luar Traka

Filter mencegah pengguna membagikan kontak/link untuk transaksi atau komunikasi di luar aplikasi.

## Yang Diblokir

| Kategori | Contoh |
|----------|--------|
| Nomor HP | 08xx, +62, 62xx |
| WhatsApp | wa.me, whatsapp.com, chat.whatsapp.com |
| Platform lain | Telegram, Line, bit.ly, Instagram, TikTok, Facebook |
| Rekening | norek, rekening, no rek + digit |
| Kata kunci | "transfer ke", "hubungi saya", "luar aplikasi", "bayar manual" |
| Email | user@domain.com |

## Implementasi

- **Client** (`ChatFilterService`): Validasi sebelum kirim. Jika diblokir, pesan tidak terkirim dan pengguna melihat SnackBar merah.
- **Server** (`chatFilter.js` + `onChatMessageCreated`): Backup. Jika pesan lolos client (mis. APK dimodifikasi), pesan dihapus oleh Cloud Function.

## Pesan yang Tidak Difilter

- Pesan audio, gambar, video (kecuali OCR pada gambar mendeteksi teks terlarang)
- Barcode, voice_call_status
- Pesan sistem

## Deploy

Setelah ubah `chatFilter.js` atau `index.js`:

```bash
cd traka/functions
npm run deploy
```
