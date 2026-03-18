# Saran Kontribusi sampai Program Terakhir

Dokumen ini berisi saran perbaikan dan pengembangan sistem kontribusi dari kondisi saat ini sampai program terakhir.

---

## 1. Dokumentasi

| Item | Saran | Prioritas |
|------|-------|-----------|
| **CEK_KONTRIBUSI_DAN_PEMBAYARAN.md** | Update ke model per rute: ganti referensi `totalTravelContributionRupiah` dengan `route_sessions` (contributionRupiah, contributionPaidAt). | Sedang |
| **NOTIFIKASI_BAYAR_KONTRIBUSI_PELANGGARAN.md** | Pastikan trigger dan alur sesuai model per rute (onRouteSessionCreated, dll). | Sedang |
| **INDEX_DOKUMEN_KONTRIBUSI.md** | Ubah status CEK_KONTRIBUSI dan NOTIFIKASI dari ⚠️ ke ✅ setelah selesai update. | Rendah |

---

## 2. Fitur & UX

| Item | Saran | Prioritas |
|------|-------|-----------|
| **Kalkulator estimasi** | Tambah fitur "Cek estimasi kontribusi" di halaman profil: driver input jarak + jumlah penumpang + kategori rute → tampilkan estimasi Rp. | Tinggi |
| **Notifikasi lebih informatif** | Isi notifikasi FCM: "Bayar kontribusi Rp X (travel Rp Y + barang Rp Z + denda Rp W)" agar driver langsung tahu rinciannya. | Sedang |
| **Riwayat pembayaran** | Pastikan halaman riwayat pembayaran menampilkan detail per rute (asal–tujuan, tanggal, nominal). | Sedang |
| **Produk 5.000 & 10.000** | Pastikan produk `traka_driver_dues_5000` dan `traka_driver_dues_10000` sudah dibuat di Play Console (sesuai checklist RANCANGAN). | Tinggi |

---

## 3. Teknis & Data

| Item | Saran | Prioritas |
|------|-------|-----------|
| **Jarak per penumpang** | Jika masih pakai fallback rata-rata, pertimbangkan hitung jarak per penumpang (naik→turun) untuk perhitungan lebih akurat. | Sedang |
| **Validasi overpay** | Pastikan sisa pembayaran (overpay) tercatat dan digunakan untuk kewajiban berikutnya. | Rendah |
| **Sinkron Admin** | Pastikan web admin mengatur `maxKontribusiTravelPerRuteRupiah` dan tarif 90/110/140, serta hapus field legacy. | Sedang |

---

## 4. Pengujian & Deploy

| Item | Saran | Prioritas |
|------|-------|-----------|
| **Uji coba end-to-end** | Uji: selesai rute → kewajiban muncul → bayar via Google Play → verifikasi → status lunas. | Tinggi |
| **Deploy AAB** | Build dan upload AAB ke Play Console agar pengguna dapat versi terbaru (panduan tarif, produk 5k–50k). | Tinggi |

---

## 5. Ringkasan Prioritas

### Segera
- Produk 5k & 10k di Play Console
- Deploy AAB ke Play Store
- Uji coba end-to-end pembayaran

### Sedang
- Update dokumen CEK_KONTRIBUSI dan NOTIFIKASI ke model per rute
- Notifikasi FCM dengan rincian nominal
- Kalkulator estimasi kontribusi

### Opsional
- Jarak per penumpang (naik→turun) untuk perhitungan lebih akurat
- Validasi overpay

---

## 6. Referensi

- `INDEX_DOKUMEN_KONTRIBUSI.md` — Indeks dokumen kontribusi
- `RANCANGAN_KONTRIBUSI_OPTIMAL.md` — Rancangan model per rute
- `UPDATE_HARGA_GOOGLE_BILLING.md` — Produk Play Console
- `CEK_KONTRIBUSI_DAN_PEMBAYARAN.md` — Alur pembayaran
