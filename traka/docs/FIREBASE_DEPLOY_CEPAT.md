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

## Runtime Cloud Functions — Node.js 22

Proyek ini memakai **`nodejs22`** (1st Gen) di `traka/firebase.json` dan `engines.node` **`22`** di `traka/functions/package.json`. Jadwal dukungan: [Runtime support](https://cloud.google.com/functions/docs/runtime-support).

### `firebase deploy --only functions` gagal (fungsi “orphan”)

Jika CLI menghentikan deploy karena ada fungsi di **cloud** yang **tidak** ada di `functions/index.js` lokal, hindari `--force` kecuali Anda memang ingin menghapus fungsi itu dari cloud.

**Keluaran aman:** deploy **eksplisit** semua export lokal (`firebase deploy --only "functions:a,functions:b,…"`). Alternatif: hapus fungsi orphan dengan `firebase functions:delete <nama> --region us-central1` setelah menilai dampaknya.

### Develop & deploy Functions

1. Disarankan **Node.js 22 LTS** untuk lokal; dari `traka/functions`: `npm install`, `npm run lint`.
2. Deploy: gunakan catatan orphan di atas bila deploy penuh ditolak CLI.
3. Setelah deploy: smoke test (login, callable, trigger penting). Log build ada di Firebase Console → Functions.

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

**Catatan:** Upgrade `firebase-functions` **tidak** otomatis mengganti runtime Node; runtime tetap diatur oleh **`firebase.json`** (`nodejs22`, dll.) dan **`engines.node`** di `package.json`.

## Backend Node (traka-api di Railway)

**App hybrid** membutuhkan API Node terpisah (bukan Firebase Hosting). Deploy Firebase **tidak** menggantikan redeploy API.

- **Langkah cepat** (Redeploy, Variables, rate limit `POST /api/driver/location`): [`../traka-api/docs/RAILWAY_DEPLOY_CEPAT.md`](../traka-api/docs/RAILWAY_DEPLOY_CEPAT.md).
- **Health & monitoring**: [`../traka-api/docs/MONITORING_PRODUCTION.md`](../traka-api/docs/MONITORING_PRODUCTION.md).

## Quota / error deploy

Jika deploy Functions gagal karena kuota atau terlalu banyak fungsi sekaligus, lihat [`SOLUSI_ERROR_429_DEPLOY.md`](SOLUSI_ERROR_429_DEPLOY.md).
