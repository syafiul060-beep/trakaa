# Index untuk contribution_payments

Jika Riwayat Pembayaran driver menampilkan error "index required", tambahkan index berikut:

**Firebase Console** → Firestore → Indexes → Create Index

- Collection: `contribution_payments`
- Fields:
  - `driverUid` (Ascending)
  - `paidAt` (Descending)

Atau tambahkan ke `firestore.indexes.json`:

```json
{
  "collectionGroup": "contribution_payments",
  "queryScope": "COLLECTION",
  "fields": [
    {"fieldPath": "driverUid", "order": "ASCENDING"},
    {"fieldPath": "paidAt", "order": "DESCENDING"}
  ]
}
```

Lalu deploy: `firebase deploy --only firestore:indexes`
