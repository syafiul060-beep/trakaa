# QA regresi — alur utama Traka

Untuk **QA minimal Tutup Tahap 1** (observabilitas saja), cukup [`QA_BASELINE_TAHAP1_CATATAN.md`](QA_BASELINE_TAHAP1_CATATAN.md) atau [`QA_BASELINE_TAHAP1_TEMPLATE.md`](QA_BASELINE_TAHAP1_TEMPLATE.md) — tidak wajib menyelesaikan seluruh matriks di bawah.

Dokumen ini mendukung **poin 1** (QA + data): skenario yang dijalankan sebelum rilis besar atau setelah perubahan status order / peta / API.

## Cara pakai

1. Isi **metadata** di bawah (tanggal, build, platform).
2. Jalankan skenario; centang **Lulus** atau catat **Gagal** + screenshot/log.
3. Simpan hasil (foto spreadsheet / issue) sebagai **data baseline** per versi.
4. Untuk **HP khas pasar Indonesia** (gesture vs tombol nav, variasi OEM): lihat [`QA_PERANGKAT_INDONESIA.md`](QA_PERANGKAT_INDONESIA.md).

### Metadata (salin per sesi)

| Field | Nilai |
|-------|--------|
| Tanggal | |
| Versi app (version+build) | |
| Platform | Android / iOS |
| API / Redis | on / off |
| Tester | |

---

## A. Penumpang — travel

| # | Skenario | Lulus |
|---|----------|-------|
| A1 | Login → beranda peta → isi tujuan → cari driver → marker tampil | [ ] |
| A1b | Pencarian **rute** tanpa hasil → snackbar → tap **Driver sekitar** → marker (mode sekitar) + banner penjelasan (bukan filter A→B) | [ ] |
| A2 | Tap driver → sheet detail → chat / arah pesan | [ ] |
| A3 | Kesepakatan: pending → agreed (dua pihak) | [ ] |
| A4 | **Beranda diblokir** hanya saat travel **`agreed` / `picked_up`** (bukan `pending_agreement`) | [ ] |
| A5 | Tombol **Buka Pesanan** dari overlay → tab Pesanan | [ ] |
| A6 | Lacak driver (bayar jika perlu) → peta + overlay mobil | [ ] |
| A7 | Selesai / batal → beranda **tidak** diblokir | [ ] |
| A8 | App ke background lalu resume → blokir overlay sinkron dengan status | [ ] |
| A9 | Tab **Pesan**: travel `pending` dengan **driver lain** tidak bisa dihapus jika sudah ada travel **agreed** (ikon kunci); kirim barang tetap bisa dihapus | [ ] |

**Catatan (A4/A5):** Overlay menampilkan baris eksplisit *Beranda diblokir karena travel sudah ada kesepakatan harga.* Firebase Analytics: `passenger_home_travel_block` — `action=shown` (saat blokir terdeteksi), `action=open_orders` (tombol Buka Pesanan).

## B. Penumpang — kirim barang

| # | Skenario | Lulus |
|---|----------|-------|
| B1 | Buat / terima order kirim barang → status relevan | [ ] |
| B2 | **Beranda tidak diblokir** karena kirim barang aktif (kecuali kebijakan berubah) | [ ] |
| B3 | Lacak barang → driver + pin pengirim/penerima | [ ] |

## C. Driver

| # | Skenario | Lulus |
|---|----------|-------|
| C1 | Siap kerja + rute → muncul di matching penumpang | [ ] |
| C2 | Terima / proses order travel | [ ] |
| C3 | Scan / selesai rute sesuai alur app | [ ] |
| C4 | Navigasi jalan (peta, suara, jemput→antar): [`QA_UJI_NAVIGASI_DRIVER.md`](QA_UJI_NAVIGASI_DRIVER.md) | [ ] |
| C5 | **Peta mode aktif:** geser peta → kamera diam; setelah GPS bergerak **~90 m+** dari titik saat geser → kamera **ikut lagi**; atau tap **Fokus** kapan saja | [ ] |

## D. Peta & ikon (ringkas)

Ikuti juga [`CHECKLIST_ICON_MOBIL_PETA_PENUMPANG.md`](CHECKLIST_ICON_MOBIL_PETA_PENUMPANG.md).

| # | Skenario | Lulus |
|---|----------|-------|
| D1 | Tap ikon driver → sheet (handle, tutup); driver terdekat = chip **Direkomendasikan** sama dengan sorotan biru di peta | [ ] |
| D2 | ETA driver→lokasi Anda: memuat lalu teks waktu; jika gagal → pesan + **Coba lagi** | [ ] |

## E. Barcode & konfirmasi otomatis (rules / OrderService / Functions)

| # | Skenario | Lulus |
|---|----------|-------|
| E1 | **Travel:** scan PICKUP lalu COMPLETE → order selesai; di Firestore `scan_audit_log` muncul `pickup` + `complete` | [ ] |
| E2 | **Travel:** biarkan auto penjemputan (15 menit / 1 km) → `auto_confirm_pickup` di `scan_audit_log`; kirim barang **tidak** boleh jalur ini | [ ] |
| E3 | **Travel:** selesai otomatis saat menjauh → `auto_confirm_complete` di `scan_audit_log` | [ ] |
| E4 | **Kirim barang:** pickup & selesai hanya lewat scan (pengirim / penerima); tidak ada `auto_confirm_*` untuk kirim barang | [ ] |
| E5 | **Firestore rules** baru: buat order, update agreed/picked_up — tidak `permission-denied` di jalur normal | [ ] |

## F. API (opsional)

| # | Skenario | Lulus |
|---|----------|-------|
| F1 | `GET /health` → `ok: true` bila Redis up | [ ] |
| F2 | `GET /api/match/drivers?lat=&lng=&destLat=&destLng=` → urutan masuk akal | [ ] |

## N. Notifikasi (Profil → Notifikasi)

| # | Skenario | Lulus |
|---|----------|-------|
| N1 | Profil penumpang & driver → **Notifikasi** → teks channel + push tampil; tombol **Buka pengaturan notifikasi** membuka layar sistem (Android / iOS 16+) | [ ] |
| N2 | Setelah izin dinonaktifkan di sistem, app tidak crash; pengguna bisa mengaktifkan lagi lewat tombol yang sama | [ ] |
| N3 | (Opsional) Firebase DebugView: saat proximity lokal tampil → event `local_proximity_notif_shown` + `flow` / `band` | [ ] |

---

## Templat catatan gagal

```
ID: A4
Versi: x.y.z+nn
Langkah: ...
Yang diharapkan: ...
Yang terjadi: ...
```

---

*Rujukan kebijakan status: [`KEBIJAKAN_BLOKIR_BERANDA_DAN_ORDER.md`](KEBIJAKAN_BLOKIR_BERANDA_DAN_ORDER.md)*  
*Perangkat uji Indonesia: [`QA_PERANGKAT_INDONESIA.md`](QA_PERANGKAT_INDONESIA.md)*
