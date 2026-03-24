Menambah foto / brosur ke halaman profil (profil.html)
=====================================================

1. Letakkan file gambar di folder ini (hosting/assets/), contoh:
   - promo-travel.jpg
   - promo-kirim-barang.jpg
   Gunakan format JPG atau WebP, lebar disarankan 1200-1600px agar tajam di layar lebar.

2. Buka hosting/profil.html di editor, tambahkan blok figure baru di bagian yang diinginkan, contoh:

   <figure class="brosur-frame">
     <img src="/assets/promo-travel.jpg" alt="Deskripsi singkat untuk aksesibilitas" width="1200" height="675" loading="lazy" decoding="async">
     <figcaption class="brosur-caption">Keterangan opsional.</figcaption>
   </figure>

3. Deploy ulang hosting dari folder traka:
   npx --yes firebase-tools deploy --only hosting

File SVG bawaan (profil-hero.svg, profil-brosur-spread.svg) boleh diganti namanya di HTML jika Anda punya ilustrasi sendiri.
