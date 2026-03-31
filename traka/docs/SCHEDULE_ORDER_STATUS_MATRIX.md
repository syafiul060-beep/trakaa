# Matriks jadwal (`schedule_items`) ↔ order aktif

Ringkasan untuk operasi **server** dan **aturan bisnis**: kapan slot jadwal masih “terikat” order.

## Status order yang menahan slot (Cloud Function)

Fungsi `onDriverScheduleItemDeleted` memanggil `restoreIfScheduleHasActiveOrders` (`functions/lib/scheduleItemDeleteGuard.js`). Jika dokumen `schedule_items` dihapus dan masih ada dokumen di `orders` dengan:

- `scheduleId` yang cocok dengan salah satu kandidat (`scheduleId` tersimpan, varian legacy tanpa suffix jam, atau ID legacy dihitung dari `date` + `departureTime`), **dan**
- `status` ∈ `{ pending_agreement, agreed, picked_up, pending_receiver }`,

maka dokumen slot **dipulihkan** dengan `set` ke path yang sama (safety net terhadap penghapusan klien atau race).

## Status lain

| `status`    | Menahan slot (guard di atas) |
|------------|------------------------------|
| `completed`| Tidak                        |
| `cancelled`| Tidak                        |

Detail transisi status dan peran `scheduleId` / `scheduledDate`: [ORDER_STATUS_TRANSITIONS.md](ORDER_STATUS_TRANSITIONS.md).
