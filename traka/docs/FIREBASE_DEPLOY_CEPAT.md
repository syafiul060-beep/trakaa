# Deploy Firebase (ringkas)

## App utama — folder `traka/`

Konfigurasi di root Flutter: `traka/firebase.json` (hosting `syafiul-traka`, Functions, Firestore, Storage).

**Deploy sekaligus** (semua target di `firebase.json`):

```bash
cd traka
firebase deploy
```

**Hanya bagian tertentu** (contoh):

```bash
firebase deploy --only hosting,functions,firestore,storage
```

## Admin web — folder `traka-admin/`

`traka-admin` memakai **`firebase.json` terpisah** (Hosting site **`traka-admin`**). Menjalankan `firebase deploy` dari **`traka/` tidak** mendeploy situs admin.

Urutan deploy admin:

1. Build frontend: `npm run build` (output biasanya ke `dist/`).
2. Dari folder **`traka-admin/`**:

```bash
firebase deploy
```

## Peringatan CLI — Node.js 20 (bukan error)

Firebase mengingatkan bahwa runtime **Node.js 20** untuk Cloud Functions punya tanggal akhir dukungan (lihat [Runtime support](https://cloud.google.com/functions/docs/runtime-support)). Sampai tanggal itu, deploy tetap jalan; ini hanya peringatan perencanaan.

### Kapan perlu tindakan?

- **Sekarang**: tidak wajib mengubah apa pun selama deploy sukses dan runtime masih didukung.
- **Sebelum batas deprecation**: naikkan ke runtime yang didukung (misalnya **Node 22**).

### Cara upgrade runtime ke Node.js 22 (proyek Traka)

Lakukan di branch terpisah, lalu uji emulator / staging jika ada.

1. **Pasang Node.js 22** di mesin Anda (mis. dari [nodejs.org](https://nodejs.org/) atau nvm) supaya `node -v` menunjukkan v22.x saat develop Functions.

2. **Ubah `traka/firebase.json`** — pada blok `functions`, ganti runtime:

   - Dari: `"runtime": "nodejs20"`
   - Ke: `"runtime": "nodejs22"`

3. **Ubah `traka/functions/package.json`** — field `engines`:

   - Dari: `"node": "20"`
   - Ke: `"node": "22"`

4. **Instal ulang dependensi** (dari folder `traka/functions`):

   ```bash
   cd traka/functions
   rm -rf node_modules
   npm install
   ```

   Di Windows PowerShell, hapus folder `node_modules` lewat Explorer atau `Remove-Item -Recurse -Force node_modules` jika perlu.

5. **Cek kode & lint**:

   ```bash
   npm run lint
   ```

6. **Deploy hanya Functions** (lebih aman untuk verifikasi):

   ```bash
   cd traka
   firebase deploy --only functions
   ```

7. **Smoke test** di app: login, callable penting, trigger Firestore yang kritis.

Jika ada error build di Google Cloud Build, baca log di Firebase Console → Functions; kadang perlu menyesuaikan dependency atau versi `firebase-functions` / `firebase-admin`.

---

## Upgrade paket `firebase-functions` (dan terkait)

CLI bisa mengingatkan bahwa **`firebase-functions`** di `package.json` ketinggalan dibanding versi terbaru npm.

### Langkah aman

1. Baca [changelog / release notes](https://github.com/firebase/firebase-functions/releases) untuk major version baru — kadang ada breaking change API.

2. Dari folder **`traka/functions`**:

   ```bash
   cd traka/functions
   npm install --save firebase-functions@latest
   ```

   Disarankan sekalian menjaga **`firebase-admin`** selaras (versi yang direkomendasikan biasanya tercantum di dokumentasi Firebase untuk kombinasi Functions + Admin SDK):

   ```bash
   npm install --save firebase-admin@latest
   ```

3. Jalankan lint:

   ```bash
   npm run lint
   ```

4. (Opsional) Uji lokal:

   ```bash
   npm run serve
   ```

   atau `firebase emulators:start --only functions` dari `traka/` sesuai kebiasaan Anda.

5. Deploy:

   ```bash
   cd traka
   firebase deploy --only functions
   ```

**Catatan:** Upgrade `firebase-functions` **tidak** otomatis mengganti runtime Node; runtime tetap diatur oleh **`firebase.json`** (`nodejs20` / `nodejs22`, dll.) dan **`engines.node`** di `package.json`. Anda bisa memperbarui npm dulu, lalu terpisah naikkan Node runtime ketika siap.

## Quota / error deploy

Jika deploy Functions gagal karena kuota atau terlalu banyak fungsi sekaligus, lihat [`SOLUSI_ERROR_429_DEPLOY.md`](SOLUSI_ERROR_429_DEPLOY.md).
