# Firestore Rules untuk Admin

Agar web admin bisa membaca data, tambahkan kondisi untuk role admin di Firestore Rules.

## Contoh Rules (sederhana)

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper: cek apakah user adalah admin
    function isAdmin() {
      return request.auth != null && 
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
    }
    
    // Users: admin baca semua, user baca sendiri
    match /users/{userId} {
      allow read: if request.auth != null && 
        (request.auth.uid == userId || isAdmin());
      allow write: if request.auth != null && isAdmin();
    }
    
    // Orders: admin baca semua (tambahkan ke rule existing)
    match /orders/{orderId} {
      allow read: if request.auth != null && isAdmin();
      // ... rule write existing untuk driver/penumpang
    }
    
    // driver_status: admin baca
    match /driver_status/{docId} {
      allow read: if request.auth != null && isAdmin();
    }
    
    // app_config: admin baca & tulis
    match /app_config/{docId} {
      allow read, write: if request.auth != null && isAdmin();
    }
  }
}
```

**Penting:** Sesuaikan dengan rules existing Anda. Jangan hapus rule yang sudah ada untuk driver/penumpang.

## Cara menambah admin

1. Buka Firebase Console > Firestore
2. Buka document `users/{uid}` (uid = user yang akan jadi admin)
3. Tambah field: `role` = `"admin"` (string)
4. Jika document belum ada, buat dulu dengan field minimal + role
