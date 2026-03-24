# QA — perangkat khas pasar Indonesia

Dokumen ini membantu **uji manual** pada HP yang umum dipakai pengguna di Indonesia: **Android** kelas menengah ke atas (Samsung Galaxy A, Xiaomi/Redmi, Oppo, Vivo, Realme, Infinix, dll.) dan **iPhone** yang masih dipakai sehari-hari. Bukan daftar wajib merek—fokusnya **variasi sistem** yang mempengaruhi inset keyboard, home indicator / bilah bawah, dan tinggi “safe area”.

## Mengapa perlu variasi perangkat

| Faktor | Dampak ke UI |
|--------|----------------|
| **Navigasi gesture vs tombol (3 tombol)** | Tinggi area bawah layar berbeda; setelah keyboard ditutup, inset bisa berubah. Layar auth (`login` / `daftar`) pernah menunjukkan **strip kosong di bawah** bila layout tidak memaksa isi memenuhi viewport (`Stack` + `Positioned.fill` + `resizeToAvoidBottomInset`). |
| **Skin OEM (One UI, MIUI, ColorOS, Funtouch)** | Perilaku window inset kadang sedikit beda dari Android “stock”; regresi UI lebih aman dicek di minimal dua merek berbeda. |
| **Layar notch / punch-hole** | `SafeArea` tetap relevan; uji juga rotasi jika fitur mendukung. |

## iOS — iPhone “biasa” masih relevan (contoh: iPhone XR)

Di Indonesia masih banyak pengguna **iPhone bekas / kelas menengah** (mis. **iPhone XR**, iPhone 11). Layar **notch + home indicator** (garis bawah) memberi **safe area** berbeda dari Android; keyboard iOS juga punya perilaku inset sendiri.

| Perangkat / ciri | Kenapa diuji |
|------------------|--------------|
| **iPhone XR** (atau iPhone 11 / layar notch serupa) | Representatif “iPhone umum”: notch, **LCD** lebar 6,1", banyak unit di pasar. Cocok untuk cek **Login/Daftar**, keyboard, overlay loading—sama seperti skenario Android. |
| iPhone lebih baru (Dynamic Island) | Opsional: inset atas beda; jika sudah punya unit, sekali regresi sebelum rilis besar cukup. |

**Matriks iOS minimal:** satu perangkat **notch + home indicator** (XR/11/12/13 non-Pro Max sudah cukup merepresentasikan kelas ini). Tidak wajib punya semua model.

## Matriks minimal — Android (disarankan sebelum rilis besar)

| Prioritas | Perangkat / pengaturan | Tujuan |
|-----------|------------------------|--------|
| **Wajib** | Satu HP dengan **navigasi gesture** | Cek inset bawah + keyboard |
| **Wajib** | Satu HP dengan **tombol navigasi 3** | Cek tinggi bilah sistem berbeda |
| **Disarankan** | Resolusi berbeda (mis. ~720p vs FHD+) | Cek overflow / scroll |
| **Opsional** | Merek kedua (Samsung vs Xiaomi/Oppo) | Cakup variasi OEM |

Tidak perlu membeli banyak unit: kombinasi **2 HP Android nyata** (gesture + tombol) sudah menangkap sebagian besar kasus. **Tambah 1 iPhone** jika app rilis ke App Store atau ada pengguna iOS.

## Skenario cepat — Login & Daftar (layout penuh)

**Android:** jalankan di **kedua** mode navigasi (gesture dan tombol):

**iOS (XR dll.):** tidak ada mode tombol sistem seperti Android—cukup jalankan langkah yang sama dengan **gesture + keyboard iOS**:

1. Buka **Login** → fokus field → buka keyboard → tutup keyboard (back atau tap luar).
2. Isi kredensial → tap login → **loading overlay** aktif → pastikan **tidak ada blok putih besar** di atas bilah sistem; latar layar terasa penuh.
3. Ulangi di layar **Daftar** (penumpang atau driver): keyboard buka/tutup → submit jika perlu → overlay loading.

**Lulus:** tidak ada strip kosong mencolok di bawah konten; scroll tetap natural jika konten panjang.

## Rujukan

- Regresi alur utama: [`QA_REGRESI_ALUR_UTAMA.md`](QA_REGRESI_ALUR_UTAMA.md)
- Ikon peta penumpang: [`CHECKLIST_ICON_MOBIL_PETA_PENUMPANG.md`](CHECKLIST_ICON_MOBIL_PETA_PENUMPANG.md)
