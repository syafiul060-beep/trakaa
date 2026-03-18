# Konfigurasi Panggilan Suara

## TURN Server (opsional)

Jika panggilan suara sering gagal (NAT/firewall), tambahkan TURN server di Firestore.

### Via script (deploy)

1. Edit `traka/functions/scripts/set-voice-call-turn.js` – ubah `TURN_CONFIG`:

```javascript
const TURN_CONFIG = {
  voiceCallTurnUrls: ['turn:turn.example.com:3478'],
  voiceCallTurnUsername: 'user',
  voiceCallTurnCredential: 'secret',
};
```

2. Pastikan `serviceAccountKey.json` ada di `traka/functions/` (dari Firebase Console > Project Settings > Service Accounts > Generate new private key).

3. Jalankan:

```bash
cd traka/functions
npm run set-turn
```

### Via Firebase Console

**Lokasi:** `app_config/settings`

| Field | Tipe | Contoh |
|-------|------|--------|
| `voiceCallTurnUrls` | array string | `["turn:turn.example.com:3478"]` |
| `voiceCallTurnUsername` | string | `"user"` |
| `voiceCallTurnCredential` | string | `"password"` |

Penyedia TURN: [Twilio](https://www.twilio.com/stun-turn), [Xirsys](https://xirsys.com/), atau self-hosted (coturn).

## Ringtone

- **Asset:** `assets/sounds/ringtone.mp3` – jika ada, dipakai saat panggilan masuk.
- **Fallback:** URL Mixkit (online) jika asset tidak ada.
- Untuk ringtone kustom, tambahkan file `ringtone.mp3` di `traka/assets/sounds/`.
