# Deploy Firebase (ringkas)

## App utama — folder `traka/`

Konfigurasi di root Flutter: `traka/firebase.json` (hosting `syafiul-traka`, Functions, Firestore, Storage).

### OTP / Phone Auth (Android) — SHA & App Check

Agar verifikasi nomor sering **tanpa** layar reCAPTCHA kosong dan Play Integrity lancar:

1. **Firebase Console** → Pengaturan project → Aplikasi Android: daftarkan **SHA-1** dan **SHA-256** untuk keystore **debug** dan **release** (yang dipakai build ke Play / APK).
2. Unduh ulang **`google-services.json`** jika perlu, lalu build ulang aplikasi.
3. **App Check** (jika diaktifkan di project): pastikan device test / keystore selaras dengan [dokumentasi Firebase](https://firebase.google.com/docs/app-check), atau OTP bisa gagal di lingkungan tertentu.

**Lihat juga:** `docs/FIREBASE_OTP_LANGKAH.md` bila perlu langkah detail.

**Deploy sekaligus** (semua target di `firebase.json`):

```bash
cd traka
firebase deploy
```

**Hanya bagian tertentu** (contoh):

```bash
firebase deploy --only hosting,functions,firestore,storage
```

### Notifikasi Android (ikon status bar / FCM)

- **`FirebaseMessaging.onBackgroundMessage`** harus dipanggil di **`main.dart` sebelum `runApp()`**. Jika didaftarkan terlambat (mis. setelah UI jalan), pesan **data-only** di background/terminated sering **tidak** memicu notifikasi lokal.
- **Android 13+ (`POST_NOTIFICATIONS`):** izin diminta saat **`AuthFlowService.navigateToHome`** (setelah login / masuk home dari splash), bukan dari init FCM di background — meminta terlalu awal sering **gagal tanpa dialog** di beberapa HP (mis. Samsung).
- Saluran **`traka_fcm_default`** dibuat saat startup dan direferensikan oleh **`com.google.firebase.messaging.default_notification_channel_id`** di manifest agar pesan dengan payload **`notification`** tidak masuk channel default yang lemah (risiko tidak terlihat di beberapa OEM).
- Ikon kecil di status bar memakai **`@drawable/ic_notification`**; meta **`com.google.firebase.messaging.default_notification_icon`** ada di `android/app/src/main/AndroidManifest.xml`.
- Untuk mengganti gambar sambil menjaga jarak aman dari crop bundar: jalankan dari folder `traka/`:

```bash
python tool/generate_notification_icon.py path/ke/logo_sumber.png
```

- Jika backend mengirim FCM dengan field **`android.notification.icon`**, samakan dengan nama resource di atas agar tidak tertimpa ikon lain.

**Checklist uji di HP (disarankan sebelum rilis):**

| Langkah | Catatan |
|--------|---------|
| Build release / APK internal dan **install bersih** (uninstall app lama dulu) | Menghindari ikon/channel cache lama. |
| Minimal **dua merek** (mis. Samsung atau Xiaomi + Pixel/stock) | OEM sering memotong atau menata ulang ikon status bar. |
| Tes **notifikasi lokal** (chat/route di app) dan satu **FCM** dari server / Console | Pastikan keduanya memakai drawable yang sama. |
| Cek ikon **tidak terpotong** dan bukan kotak hitam | Kalau hitam: drawable bukan putih+alpha atau resource salah. |

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

### Deploy Functions — auth (satu perintah)

Setelah mengubah logika login/daftar di **klien** dan **Functions** (`getPhoneLoginEmail`, `checkGoogleEmailConflictForRegister`, dll.), deploy backend agar tidak **fail-open** atau perilaku lama di production.

Dari folder **`traka/`** (bukan `functions/`). Di **PowerShell**, pakai **satu string** untuk `--only` (koma tidak boleh memecah argumen):

```bash
cd traka
firebase deploy --only "functions:getPhoneLoginEmail,functions:checkGoogleEmailConflictForRegister,functions:checkPhoneExists,functions:checkRegistrationAllowed"
```

Setiap nama callable harus diawali `functions:` (bukan hanya dipisah koma). Jika CLI menolak daftar panjang, cukup `firebase deploy --only functions` (perhatikan catatan **fungsi orphan** di atas).

### Checklist QA — login & daftar (Google + nomor)

Centang setelah deploy app + Functions terkait. HP fisik disarankan untuk OTP/Play Integrity.

| # | Skenario | Yang diharapkan |
|---|----------|------------------|
| 1 | Daftar **nomor + sandi** baru (penumpang atau driver) | OTP → profil tersimpan → diarahkan login; perangkat tercatat sesuai role. |
| 2 | Login nomor + sandi (akun `…@traka.phone`) | Masuk tanpa pesan “sandi salah” yang salah sasaran. |
| 3 | Daftar / login **Google + OTP** (role sama) | Selesai verifikasi nomor; login berikutnya via **Google** atau **nomor + OTP**, bukan sandi Traka. |
| 4 | Login nomor + sandi untuk akun yang **hanya** Google+nomor (tanpa penyedia password di Auth) | Aplikasi mengarahkan ke **OTP** atau meminta **Google**, bukan memaksa email Google + sandi. |
| 5 | Daftar Google: **email Google** sudah dipakai dokumen `users` milik **uid lain** | Pesan bentrok email; tidak lanjut buat profil ganda (perlu Function `checkGoogleEmailConflictForRegister` ter-deploy). |
| 6 | Daftar Google: perangkat sudah terdaftar **role yang sama** | Pesan perangkat sudah penumpang/driver → diarahkan ke login dengan penjelasan jelas. |
| 7 | Role **beda** di device yang sama (penumpang + driver) | Sesuai kebijakan app: biasanya **diizinkan**; pastikan tidak ikut tertahan oleh cek role yang sama. |
| 8 | Nomor sudah terdaftar: user membuka **Daftar** (Google atau sandi) | Pesan “nomor sudah terdaftar / login”, tidak menimpa akun. |
| 9 | (Opsional) **Lupa sandi** untuk akun nomor+sandi | Email/OTP sesuai implementasi; tidak membingungkan dengan akun Google-only. |

### Smoke test cepat (~5 menit) pasca-deploy Hosting + Functions

Lakukan setelah `firebase deploy --only "hosting,functions"` (atau deploy penuh). Tidak mengganti checklist lengkap di atas; ini untuk verifikasi regressi besar.

1. **Hosting / web** — Buka `https://syafiul-traka.web.app` (dan salah satu `legal/*.html`). Hard refresh (Ctrl+Shift+R). Pastikan aksen tautan/judul **bukan biru lama** (warna amber merek).
2. **Email OTP** — Dari app atau flow yang memicu kode: cek satu email masuk; kotak kode HTML memakai warna **amber** (`#D97706`), bukan biru.
3. **App release / profile** — Build **release** terbaru di HP: login **nomor+sandi** (skenario #2) dan **satu akun Google+nomor** (#3 atau #4). Jika semua hijau, sisa baris checklist bisa dilakukan bertahap sebelum rilis store.
4. **Catatan internal** — Rekam di changelog tim: tanggal deploy, apakah hanya hosting, functions, atau keduanya; versi build app yang diuji.

### Langkah detail checklist QA (#1–#9)

Isi kolom **OK / Gagal / Catatan** di lembar tim Anda. Semua di **HP fisik**, build **release** (atau profile) yang menunjuk ke project Firebase production.

**Persiapan umum:** pastikan Functions auth sudah ter-deploy (`getPhoneLoginEmail`, `checkGoogleEmailConflictForRegister`, `checkPhoneExists`, `checkRegistrationAllowed`). Lokasi & izin ON.

| # | Langkah uji (urut) | Lulus jika |
|---|-------------------|------------|
| **1** | 1) Keluar dari akun jika masuk. 2) Daftar **penumpang** (atau **driver**) pakai **nomor baru** + **sandi** → OTP. 3) Selesaikan sampai masuk ke home role tersebut atau diarahkan login. 4) Cek di Console Firestore: dokumen `users/{uid}` ada, `phoneNumber` benar. | Tidak error OTP; profil tersimpan; bisa login dengan nomor+sandi setelahnya. |
| **2** | 1) Login dengan **mode email+password** / terpadu: isi **nomor** (format 08… atau 628…) + **sandi** akun dari #1. 2) Submit. | Masuk aplikasi tanpa kredensial salah akibat **email Google dipakai sebagai identifier sandi** (bug lama). |
| **3** | 1) Akun **baru** (nomor belum dipakai): **Daftar dengan Google** → pilih akun Google → OTP nomor → selesai. 2) Logout. 3) Login lagi lewat **Google**. 4) Logout. 5) Login lewat **nomor + OTP** (mode telepon), bukan sandi. | Semua jalur sukses; tidak diminta sandi Traka untuk akun ini. |
| **4** | Pakai **akun yang sama** seperti #3 (Google+nomor, **tanpa** penyedia password di Firebase Auth). Di login: coba **nomor + sandi** (isi sandi sembarang atau kosong). | Aplikasi **tidak** memaksa `signInWithEmailAndPassword` ke Gmail + sandi salah; ada arahan **OTP** atau **Google** / snackbar jelas. |
| **5** | **Butuh data uji:** di Firestore, pastikan ada user A dengan `email` = alamat Gmail yang akan dipakai. Di HP **bersih** / akun lain: **Daftar Google** dengan Gmail **yang sama** (uid berbeda dari A jika Auth mengizinkan skenario uji). Atau: duplikasi email antar uid (jarang) — utamanya pastikan callable `checkGoogleEmailConflictForRegister` aktif. | Muncul pesan bentrok email / tidak lanjut buat profil duplikat. |
| **6** | Di perangkat yang **sudah** punya akun **penumpang** (device+role tercatat): buka **Daftar penumpang dengan Google** (belum login). | Diarahkan ke **Login** + pesan perangkat/role sudah terdaftar (bukan crash atau lanjut OTP sia-sia). |
| **7** | Perangkat yang sama: sudah ada **penumpang** → coba **Daftar driver** (nomor+sandi atau Google) dengan nomor/driver **baru** sesuai aturan app. | **Driver** bisa terdaftar jika kebijakan 1 penumpang + 1 driver per device diizinkan (sesuai kode); tidak terblokir oleh cek “role sama” penumpang. |
| **8** | Tanpa login: **Daftar** (sandi atau Google) dengan **nomor yang sudah terpakai** akun lain. Kirim OTP / lanjut sampai titik cek. | Pesan **nomor sudah terdaftar** / arahan login; **tidak** menimpa akun lain. |
| **9** | Dari login: **Lupa sandi** untuk akun **nomor+sandi** (bukan Google-only). Ikuti email/OTP/wajah sesuai app. | Alur selesai atau pesan jelas; akun Google-only **tidak** disuruh reset sandi yang tidak pernah ada. |

### Verifikasi tema & logo (app)

Centang sekilas setelah mengganti aset atau `AppTheme`:

- **Launcher & splash native:** ikon + splash pertama buka app = logo baru (`traka_brand_logo` / generator splash).
- **Login / splash Flutter:** gambar logo besar, tidak pecah; warm-up cache: uninstall lalu install ulang bila masih logo lama.
- **Tombol & link utama:** warna primer **amber** (`#D97706`), bukan biru lama; mode gelap tetap terbaca.
- **PDF struk / laporan:** strip atas / logo = palet baru.

### Sebelum unggah ke Play Store / App Store

- Screenshot toko disesuaikan tema/logo baru (opsional tapi disarankan).
- **Android:** SHA-1/SHA-256 release + App Check jika dipakai.
- **iOS:** ikon tanpa saluran alpha (sudah `remove_alpha_ios` di `pubspec`).

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

## Google Sign-In (app mobile Flutter)

Langkah Firebase Console, SHA-1 Android, `google-services.json`, dan URL scheme iOS: [`GOOGLE_SIGN_IN_FIREBASE_SETUP.md`](GOOGLE_SIGN_IN_FIREBASE_SETUP.md).
