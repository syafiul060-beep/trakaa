import { useState, useEffect, useCallback, useMemo } from 'react'
import { useSearchParams, Link } from 'react-router-dom'
import {
  collection,
  getDocs,
  doc,
  updateDoc,
  deleteDoc,
  deleteField,
  serverTimestamp,
} from 'firebase/firestore'
import { db } from '../firebase'

function formatTs(ts) {
  if (!ts?.toDate) return '—'
  try {
    return ts.toDate().toLocaleString('id-ID', { dateStyle: 'short', timeStyle: 'short' })
  } catch {
    return '—'
  }
}

function formatDateOnly(ts) {
  if (!ts?.toDate) return '—'
  try {
    return ts.toDate().toLocaleDateString('id-ID', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' })
  } catch {
    return '—'
  }
}

export default function DriverSchedules() {
  const [searchParams, setSearchParams] = useSearchParams()
  const uidFromUrl = searchParams.get('uid') || ''

  const [uidInput, setUidInput] = useState(uidFromUrl)
  const [activeUid, setActiveUid] = useState(uidFromUrl.trim())
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState(null)
  const [busyId, setBusyId] = useState(null)

  useEffect(() => {
    setUidInput(uidFromUrl)
    setActiveUid(uidFromUrl.trim())
  }, [uidFromUrl])

  const loadItems = useCallback(async () => {
    const uid = activeUid.trim()
    if (!uid) {
      setItems([])
      return
    }
    setLoading(true)
    setError(null)
    try {
      const colRef = collection(db, 'driver_schedules', uid, 'schedule_items')
      const snap = await getDocs(colRef)
      const rows = snap.docs.map((d) => ({ id: d.id, ...d.data() }))
      rows.sort((a, b) => {
        const ad = a.date?.toMillis?.() ?? 0
        const bd = b.date?.toMillis?.() ?? 0
        if (ad !== bd) return ad - bd
        const at = a.departureTime?.toMillis?.() ?? 0
        const bt = b.departureTime?.toMillis?.() ?? 0
        return at - bt
      })
      setItems(rows)
    } catch (e) {
      console.error(e)
      setError(e?.message || 'Gagal memuat jadwal.')
      setItems([])
    } finally {
      setLoading(false)
    }
  }, [activeUid])

  useEffect(() => {
    loadItems()
  }, [loadItems])

  const onSubmitUid = (e) => {
    e.preventDefault()
    const uid = uidInput.trim()
    setActiveUid(uid)
    if (uid) setSearchParams({ uid })
    else setSearchParams({})
  }

  const refForItem = (itemId) => doc(db, 'driver_schedules', activeUid.trim(), 'schedule_items', itemId)

  const hideSlot = async (itemId) => {
    if (!activeUid.trim() || !itemId) return
    setBusyId(itemId)
    setError(null)
    try {
      await updateDoc(refForItem(itemId), { hiddenAt: serverTimestamp() })
      await loadItems()
    } catch (e) {
      console.error(e)
      setError(e?.message || 'Gagal menyembunyikan jadwal.')
    } finally {
      setBusyId(null)
    }
  }

  const unhideSlot = async (itemId) => {
    if (!activeUid.trim() || !itemId) return
    setBusyId(itemId)
    setError(null)
    try {
      await updateDoc(refForItem(itemId), { hiddenAt: deleteField() })
      await loadItems()
    } catch (e) {
      console.error(e)
      setError(e?.message || 'Gagal menampilkan kembali jadwal.')
    } finally {
      setBusyId(null)
    }
  }

  const removeSlot = async (itemId) => {
    if (!activeUid.trim() || !itemId) return
    if (!window.confirm('Hapus slot jadwal ini dari Firestore? Tindakan tidak bisa dibatalkan.')) return
    setBusyId(itemId)
    setError(null)
    try {
      await deleteDoc(refForItem(itemId))
      await loadItems()
    } catch (e) {
      console.error(e)
      setError(e?.message || 'Gagal menghapus jadwal.')
    } finally {
      setBusyId(null)
    }
  }

  const emptyHint = useMemo(() => {
    if (!activeUid.trim()) return 'Masukkan UID driver lalu klik Muat jadwal (gunakan tautan dari halaman Driver bila perlu).'
    if (!loading && items.length === 0 && !error) return 'Tidak ada dokumen di schedule_items untuk UID ini.'
    return null
  }, [activeUid, loading, items.length, error])

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold text-slate-800">Jadwal driver</h1>
          <p className="text-sm text-slate-600 mt-1">
            Lihat, sembunyikan dari penumpang, atau hapus slot di subkoleksi{' '}
            <code className="text-xs bg-slate-100 px-1 rounded">driver_schedules/…/schedule_items</code>.
          </p>
        </div>
        <Link
          to="/drivers"
          className="text-sm font-medium text-orange-600 hover:text-orange-700 shrink-0"
        >
          ← Kembali ke daftar driver
        </Link>
      </div>

      <form onSubmit={onSubmitUid} className="flex flex-col sm:flex-row gap-3 items-stretch sm:items-center">
        <label className="sr-only" htmlFor="driver-uid">
          UID driver
        </label>
        <input
          id="driver-uid"
          type="text"
          placeholder="UID driver"
          value={uidInput}
          onChange={(e) => setUidInput(e.target.value)}
          className="flex-1 min-w-0 px-4 py-2 border border-gray-200 rounded-lg text-sm focus:ring-2 focus:ring-orange-500/30 focus:border-orange-500"
        />
        <button
          type="submit"
          className="px-4 py-2 rounded-lg bg-orange-500 text-white text-sm font-medium hover:bg-orange-600 shrink-0"
        >
          Muat jadwal
        </button>
      </form>

      {error && (
        <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800" role="alert">
          {error}
        </div>
      )}

      {emptyHint && (
        <p className="text-sm text-slate-500">{emptyHint}</p>
      )}

      {activeUid.trim() && (
        <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full min-w-[720px] text-sm">
              <thead className="bg-gray-50 text-left text-xs font-medium text-gray-500 uppercase">
                <tr>
                  <th className="px-4 py-3">Tanggal</th>
                  <th className="px-4 py-3">Berangkat</th>
                  <th className="px-4 py-3">Rute</th>
                  <th className="px-4 py-3">scheduleId</th>
                  <th className="px-4 py-3">Status</th>
                  <th className="px-4 py-3 text-right">Aksi</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {loading ? (
                  <tr>
                    <td colSpan={6} className="px-4 py-12 text-center text-slate-500">
                      <span className="inline-block h-6 w-6 animate-spin rounded-full border-2 border-orange-500 border-t-transparent align-middle mr-2" />
                      Memuat…
                    </td>
                  </tr>
                ) : (
                  items.map((row) => {
                    const hid = row.hiddenAt != null
                    const origin = row.origin || '—'
                    const dest = row.destination || '—'
                    const sid = row.scheduleId || row.id
                    return (
                      <tr key={row.id} className="hover:bg-slate-50/80">
                        <td className="px-4 py-3 text-slate-700 whitespace-nowrap">{formatDateOnly(row.date)}</td>
                        <td className="px-4 py-3 text-slate-700 whitespace-nowrap">{formatTs(row.departureTime)}</td>
                        <td className="px-4 py-3 text-slate-600 max-w-[240px]">
                          <span className="line-clamp-2" title={`${origin} → ${dest}`}>
                            {origin} → {dest}
                          </span>
                        </td>
                        <td className="px-4 py-3 text-xs text-slate-500 font-mono truncate max-w-[140px]" title={sid}>
                          {sid}
                        </td>
                        <td className="px-4 py-3">
                          {hid ? (
                            <span className="inline-flex px-2 py-0.5 text-xs font-medium rounded-full bg-amber-100 text-amber-900">
                              Disembunyikan
                            </span>
                          ) : (
                            <span className="inline-flex px-2 py-0.5 text-xs font-medium rounded-full bg-green-100 text-green-800">
                              Aktif
                            </span>
                          )}
                        </td>
                        <td className="px-4 py-3 text-right whitespace-nowrap space-x-2">
                          {hid ? (
                            <button
                              type="button"
                              disabled={busyId === row.id}
                              onClick={() => unhideSlot(row.id)}
                              className="text-xs font-medium text-slate-700 hover:text-slate-900 disabled:opacity-50"
                            >
                              Tampilkan
                            </button>
                          ) : (
                            <button
                              type="button"
                              disabled={busyId === row.id}
                              onClick={() => hideSlot(row.id)}
                              className="text-xs font-medium text-amber-700 hover:text-amber-900 disabled:opacity-50"
                            >
                              Sembunyikan
                            </button>
                          )}
                          <button
                            type="button"
                            disabled={busyId === row.id}
                            onClick={() => removeSlot(row.id)}
                            className="text-xs font-medium text-red-600 hover:text-red-800 disabled:opacity-50"
                          >
                            Hapus
                          </button>
                        </td>
                      </tr>
                    )
                  })
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  )
}
