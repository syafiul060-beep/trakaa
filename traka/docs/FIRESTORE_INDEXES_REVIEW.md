# Review Firestore Indexes untuk Produksi

## Status saat ini

Indexes di `firestore.indexes.json` sudah mencakup:

- **users:** deviceId + role
- **orders:** 10+ composite indexes (passengerUid, driverUid, status, createdAt, updatedAt, dll.)
- **route_sessions:** driverUid + endedAt
- **voice_calls:** status + updatedAt, calleeUid + status
- **violation_records:** userId + type + paidAt + createdAt
- **contribution_payments:** driverUid + paidAt
- **admin_chats:** status + queueJoinedAt
- **promotions:** priority + publishedAt
- **app_feedback:** userId + createdAt

## Chat messages (orders/{id}/messages)

Subcollection: `orderBy('createdAt', descending).limit(100)`

- Single-field index pada `createdAt` dibuat otomatis oleh Firestore
- Tidak perlu composite index tambahan

## Rekomendasi

1. **Deploy indexes:** `firebase deploy --only firestore:indexes`
2. **Monitor:** Firebase Console → Firestore → Indexes – pastikan semua index status "Enabled"
3. **Query baru:** Jika menambah query dengan `orderBy` + `where` pada field berbeda, tambahkan index di `firestore.indexes.json` (Firestore akan error dan beri link ke console untuk membuat index)
