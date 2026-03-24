import { useState, useEffect, useRef } from 'react'
import {
  collection,
  query,
  orderBy,
  limit,
  onSnapshot,
  updateDoc,
  doc,
  deleteDoc,
  serverTimestamp,
} from 'firebase/firestore'
import { db } from '../firebase'
import { useFocusTrap } from '../hooks/useFocusTrap'
import { logAudit } from '../utils/auditLog'

function formatFirestoreDate(v) {
  if (!v) return ''
  const d = typeof v.toDate === 'function' ? v.toDate() : null
  if (d && !Number.isNaN(d.getTime())) return d.toLocaleString('id-ID')
  return ''
}

export default function AdminNotifications() {
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(true)
  const [detail, setDetail] = useState(null)
  const [saving, setSaving] = useState(false)
  const detailRef = useRef(null)
  useFocusTrap(!!detail, detailRef)

  useEffect(() => {
    const q = query(
      collection(db, 'admin_notifications'),
      orderBy('createdAt', 'desc'),
      limit(200),
    )
    const unsub = onSnapshot(
      q,
      (snap) => {
        setItems(snap.docs.map((d) => ({ id: d.id, ...d.data() })))
        setLoading(false)
      },
      (err) => {
        console.error(err)
        setLoading(false)
      },
    )
    return () => unsub()
  }, [])

  useEffect(() => {
    setDetail((d) => {
      if (!d?.id) return d
      const fresh = items.find((i) => i.id === d.id)
      return fresh || d
    })
  }, [items])

  const markRead = async (row) => {
    if (!row?.id || row.readAt) return
    setSaving(true)
    try {
      await updateDoc(doc(db, 'admin_notifications', row.id), {
        readAt: serverTimestamp(),
      })
      await logAudit('admin_notification_read', { notificationId: row.id })
    } catch (e) {
      console.error(e)
      alert('Gagal menandai dibaca: ' + (e.message || e))
    } finally {
      setSaving(false)
    }
  }

  const openDetail = (row) => {
    setDetail(row)
    if (!row.readAt) markRead(row)
  }

  const removeOne = async (row) => {
    if (!row?.id || !confirm('Hapus entri notifikasi ini dari daftar?')) return
    setSaving(true)
    try {
      await deleteDoc(doc(db, 'admin_notifications', row.id))
      await logAudit('admin_notification_delete', { notificationId: row.id })
      setDetail(null)
    } catch (e) {
      alert('Gagal hapus: ' + (e.message || e))
    } finally {
      setSaving(false)
    }
  }

  const unreadCount = items.filter((x) => !x.readAt).length

  let metaPretty = ''
  if (detail?.metaJson) {
    try {
      metaPretty = JSON.stringify(JSON.parse(detail.metaJson), null, 2)
    } catch {
      metaPretty = String(detail.metaJson)
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Notifikasi</h1>
        <p className="text-sm text-gray-600 mt-1">
          Riwayat dari aplikasi pengguna: konfirmasi kirim data verifikasi, permintaan ubah kendaraan (STNK),
          dll. Email ke operasional tetap dikirim oleh Cloud Functions.
        </p>
        {!loading && unreadCount > 0 && (
          <p className="text-sm text-amber-800 mt-2">
            <span className="font-semibold">{unreadCount}</span> belum dibaca
          </p>
        )}
      </div>

      <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full min-w-[640px]">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Waktu</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Jenis</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Ringkasan</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Pengguna</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200">
              {items.map((row) => (
                <tr
                  key={row.id}
                  onClick={() => openDetail(row)}
                  className={`cursor-pointer hover:bg-orange-50/50 transition ${
                    !row.readAt ? 'bg-amber-50/40 font-medium' : ''
                  }`}
                >
                  <td className="px-4 py-3 text-sm text-gray-700 whitespace-nowrap">
                    {formatFirestoreDate(row.createdAt)}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-800">
                    <span className="inline-block px-2 py-0.5 rounded-md bg-gray-100 text-xs">
                      {row.eventType || row.type || '—'}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-800 max-w-[280px] truncate" title={row.title}>
                    {row.title || '—'}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-600 max-w-[200px] truncate">
                    {row.userLabel || row.userEmail || row.userId || '—'}
                  </td>
                  <td className="px-4 py-3 text-sm">
                    {row.readAt ? (
                      <span className="text-green-700 text-xs">Dibaca</span>
                    ) : (
                      <span className="text-amber-800 text-xs font-medium">Baru</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {loading && <p className="p-6 text-center text-gray-500">Memuat...</p>}
        {!loading && items.length === 0 && (
          <p className="p-8 text-center text-gray-500">
            Belum ada notifikasi. Akan terisi saat pengguna mengonfirmasi kirim data atau mengirim STNK
            (setelah deploy Functions + aturan Firestore).
          </p>
        )}
      </div>

      {detail && (
        <div
          className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
          onClick={(e) => e.target === e.currentTarget && setDetail(null)}
          role="dialog"
          aria-modal="true"
          aria-labelledby="notif-detail-title"
        >
          <div
            ref={detailRef}
            className="bg-white rounded-xl shadow-xl max-w-lg w-full max-h-[90vh] overflow-y-auto p-6"
            onClick={(e) => e.stopPropagation()}
            tabIndex={-1}
          >
            <h2 id="notif-detail-title" className="text-lg font-semibold text-gray-900 mb-2">
              {detail.title || 'Detail'}
            </h2>
            <p className="text-xs text-gray-500 mb-4">
              {formatFirestoreDate(detail.createdAt)}
            </p>
            <div className="space-y-3 text-sm text-gray-800">
              <div>
                <span className="text-gray-500 text-xs font-medium uppercase">Isi</span>
                <p className="mt-1 whitespace-pre-wrap">{detail.body || '—'}</p>
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                <div>
                  <span className="text-gray-500 text-xs font-medium uppercase">Jenis</span>
                  <p>{detail.eventType || detail.type || '—'}</p>
                </div>
                <div>
                  <span className="text-gray-500 text-xs font-medium uppercase">UID pengguna</span>
                  <p className="break-all font-mono text-xs">{detail.userId || '—'}</p>
                </div>
                {detail.userEmail && (
                  <div className="sm:col-span-2">
                    <span className="text-gray-500 text-xs font-medium uppercase">Email</span>
                    <p>{detail.userEmail}</p>
                  </div>
                )}
              </div>
              {metaPretty && (
                <div>
                  <span className="text-gray-500 text-xs font-medium uppercase">Meta (JSON)</span>
                  <pre className="mt-1 p-3 bg-gray-50 rounded-lg text-xs overflow-x-auto max-h-40">
                    {metaPretty}
                  </pre>
                </div>
              )}
            </div>
            <div className="flex flex-wrap gap-2 mt-6">
              <button
                type="button"
                onClick={() => {
                  if (detail.userId) {
                    navigator.clipboard?.writeText(detail.userId)
                    alert('UID disalin')
                  }
                }}
                disabled={!detail.userId}
                className="px-4 py-2 border border-gray-300 rounded-lg text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50"
              >
                Salin UID
              </button>
              <button
                type="button"
                onClick={() => removeOne(detail)}
                disabled={saving}
                className="px-4 py-2 border border-red-200 text-red-700 rounded-lg text-sm hover:bg-red-50 disabled:opacity-50"
              >
                Hapus dari daftar
              </button>
              <button
                type="button"
                onClick={() => setDetail(null)}
                className="flex-1 min-w-[120px] px-4 py-2 bg-orange-500 text-white rounded-lg hover:bg-orange-600 font-medium"
              >
                Tutup
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
