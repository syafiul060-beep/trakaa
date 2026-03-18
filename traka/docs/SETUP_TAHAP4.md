# Tahap 4 – Cloud Functions minInstances

## Yang Diterapkan

**minInstances: 1** untuk fungsi callable yang paling sering dipanggil (auth & order), untuk mengurangi cold start.

### Fungsi yang Pakai callableWarm

| Fungsi | Alur | Dampak |
|--------|------|--------|
| `requestVerificationCode` | Register – minta kode email | Login/register lebih cepat |
| `requestLoginVerificationCode` | Login – kirim OTP email | Login lebih cepat |
| `verifyLoginVerificationCode` | Login – verifikasi OTP | Login lebih cepat |
| `generateOrderNumber` | Buat order | Pembuatan order lebih cepat |

### Konfigurasi callableWarm

- `minInstances: 1` – 1 instance selalu aktif
- `memory: "256MB"`
- `timeoutSeconds: 60`

---

## Biaya

`minInstances` menambah biaya di **Firebase Blaze plan** (pay-as-you-go). Setiap instance idle dihitung per jam.

Untuk menonaktifkan (misalnya di development):

1. Ubah `callableWarm` di `functions/index.js` agar memakai `callable` (tanpa minInstances), atau
2. Set `minInstances: 0` di `callableWarm`

---

## Deploy

```bash
cd traka
firebase deploy --only functions
```

Setelah deploy, fungsi yang memakai `callableWarm` akan punya 1 instance yang selalu siap.
