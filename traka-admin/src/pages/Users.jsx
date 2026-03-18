import { useState, useEffect, useRef } from 'react'
import { useOutletContext } from 'react-router-dom'
import { useFocusTrap } from '../hooks/useFocusTrap'
import { collection, getDocs, doc, updateDoc, getDoc, query, where, limit, deleteField } from 'firebase/firestore'
import { db, functions, httpsCallable } from '../firebase'
import { isApiEnabled } from '../config/apiConfig'
import { getDriverStatus } from '../services/trakaApi'
import { downloadCsv } from '../utils/exportCsv'
import { logAudit } from '../utils/auditLog'

const TABS = [
  { id: 'all', label: 'Semua Pengguna', icon: '👥' },
  { id: 'pending_deletion', label: 'Pending Penghapusan', icon: '⏳' },
]

export default function Users() {
  const [users, setUsers] = useState([])
  const [loading, setLoading] = useState(true)
  const [searchQuery, setSearchQuery] = useState('')
  const [activeTab, setActiveTab] = useState('all')
  const [editingUser, setEditingUser] = useState(null)
  const [editForm, setEditForm] = useState({ displayName: '', phoneNumber: '', verified: false })
  const [saving, setSaving] = useState(false)
  const [detailUser, setDetailUser] = useState(null)
  const [userLocation, setUserLocation] = useState(null)
  const [recoveryCode, setRecoveryCode] = useState(null)
  const [recoveryLoading, setRecoveryLoading] = useState(false)
  const detailModalRef = useRef(null)
  const editModalRef = useRef(null)
  useFocusTrap(!!detailUser, detailModalRef)
  useFocusTrap(!!editingUser, editModalRef)

  const loadUsers = () => {
    getDocs(collection(db, 'users')).then((snap) => {
      setUsers(snap.docs.map((d) => ({ id: d.id, ...d.data() })))
      setLoading(false)
    })
  }

  useEffect(() => {
    loadUsers()
  }, [])

  const openEdit = (u, e) => {
    e?.stopPropagation()
    setEditingUser(u)
    setEditForm({
      displayName: u.displayName || '',
      phoneNumber: u.phoneNumber || '',
      verified: !!u.verified,
    })
  }

  const closeEdit = () => {
    setEditingUser(null)
  }

  const openDetail = async (u) => {
    setDetailUser(u)
    setUserLocation(null)
    try {
      if (u.role === 'driver') {
        let d = null
        if (isApiEnabled) {
          d = await getDriverStatus(u.id)
        } else {
          const statusSnap = await getDoc(doc(db, 'driver_status', u.id))
          if (statusSnap.exists()) d = statusSnap.data()
        }
        if (d) {
          const lat = d?.latitude
          const lng = d?.longitude
          const updated = d?.lastUpdated?.toDate?.() ?? (typeof d?.lastUpdated === 'string' ? new Date(d.lastUpdated) : null)
          if (lat != null && lng != null) {
            setUserLocation({ lat, lng, updated })
          }
        }
      } else {
        const [passengerSnap, receiverSnap] = await Promise.all([
          getDocs(query(collection(db, 'orders'), where('passengerUid', '==', u.id), limit(50))),
          getDocs(query(collection(db, 'orders'), where('receiverUid', '==', u.id), limit(50))),
        ])
        const allOrders = [
          ...passengerSnap.docs.map((d) => ({ ...d.data(), _src: 'passenger' })),
          ...receiverSnap.docs.map((d) => ({ ...d.data(), _src: 'receiver' })),
        ]
        const withLoc = allOrders
          .map((o) => {
            const lat = o._src === 'passenger' ? (o.pickupLat ?? o.passengerLat ?? o.dropLat) : o.receiverLat
            const lng = o._src === 'passenger' ? (o.pickupLng ?? o.passengerLng ?? o.dropLng) : o.receiverLng
            return { ...o, lat, lng }
          })
          .filter((o) => o.lat != null && o.lng != null)
          .sort((a, b) => {
            const at = a.updatedAt?.toDate?.() || a.createdAt?.toDate?.() || new Date(0)
            const bt = b.updatedAt?.toDate?.() || b.createdAt?.toDate?.() || new Date(0)
            return bt - at
          })
        const last = withLoc[0]
        if (last) {
          setUserLocation({
            lat: last.lat,
            lng: last.lng,
            updated: last.updatedAt?.toDate?.() ?? last.createdAt?.toDate?.(),
          })
        }
      }
    } catch (err) {
      console.error(err)
    }
  }

  const closeDetail = () => {
    setDetailUser(null)
    setUserLocation(null)
  }

  const openMapLocation = (lat, lng) => {
    window.open(`https://www.google.com/maps?q=${lat},${lng}`, '_blank')
  }

  const handleSaveEdit = async () => {
    if (!editingUser) return
    setSaving(true)
    try {
      await updateDoc(doc(db, 'users', editingUser.id), {
        displayName: editForm.displayName.trim() || null,
        phoneNumber: editForm.phoneNumber.trim() || null,
        verified: editForm.verified,
      })
      await logAudit('user_edit', { userId: editingUser.id, email: editingUser.email })
      loadUsers()
      closeEdit()
    } catch (err) {
      console.error(err)
      alert('Gagal menyimpan: ' + (err.message || err))
    } finally {
      setSaving(false)
    }
  }

  const nonAdminUsers = users.filter((u) => u.role !== 'admin')
  const pendingDeletionUsers = nonAdminUsers.filter((u) => u.deletedAt != null)
  const searchLower = searchQuery.trim().toLowerCase()
  const searchEffective = searchLower.length > 0

  let baseUsers = activeTab === 'pending_deletion' ? pendingDeletionUsers : nonAdminUsers
  const filteredUsers = searchLower
    ? baseUsers.filter((u) => {
        const name = (u.displayName || '').toLowerCase()
        const email = (u.email || '').toLowerCase()
        const phone = (u.phoneNumber || '').toLowerCase()
        const role = (u.role || '').toLowerCase()
        return (
          name.includes(searchLower) ||
          email.includes(searchLower) ||
          phone.includes(searchLower) ||
          role.includes(searchLower)
        )
      })
    : baseUsers

  const daysUntilDeletion = (u) => {
    const scheduled = u.scheduledDeletionAt?.toDate?.()
    if (!scheduled) return null
    const days = Math.ceil((scheduled - new Date()) / (24 * 60 * 60 * 1000))
    return days > 0 ? days : 0
  }

  const handleGenerateRecoveryCode = async (u) => {
    if (!confirm(`Generate kode recovery untuk ${u.displayName || u.email || u.phoneNumber}?\n\nVerifikasi identitas user dulu (KTP, dll). Kode berlaku 15 menit.`)) return
    setRecoveryLoading(true)
    setRecoveryCode(null)
    try {
      const createRecoveryToken = httpsCallable(functions, 'createRecoveryToken')
      const { data } = await createRecoveryToken({ uid: u.id })
      setRecoveryCode({ code: data.code, userName: u.displayName || u.email || u.phoneNumber })
      await logAudit('recovery_code_generated', { userId: u.id, userName: u.displayName })
    } catch (err) {
      console.error(err)
      alert('Gagal: ' + (err.message || err))
    } finally {
      setRecoveryLoading(false)
    }
  }

  const handleCancelDeletion = async (u) => {
    if (!confirm(`Batalkan penghapusan akun ${u.displayName || u.email}?`)) return
    setSaving(true)
    try {
      await updateDoc(doc(db, 'users', u.id), {
        deletedAt: deleteField(),
        scheduledDeletionAt: deleteField(),
      })
      await logAudit('cancel_deletion', { userId: u.id, email: u.email })
      loadUsers()
    } catch (err) {
      alert('Gagal: ' + (err.message || err))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row gap-4 sm:items-center sm:justify-between">
        <div className="flex items-center gap-2">
          <button
            onClick={() => {
              const rows = filteredUsers.map((u) => ({
                id: u.id,
                nama: u.displayName || '',
                email: u.email || '',
                telepon: u.phoneNumber || '',
                role: u.role || '',
                verified: u.verified ? 'Ya' : 'Tidak',
                suspended: u.suspendedAt ? 'Ya' : 'Tidak',
                deletedAt: u.deletedAt ? 'Ya' : 'Tidak',
              }))
              downloadCsv(rows, 'users')
            }}
            className="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-lg transition"
          >
            📥 Ekspor CSV
          </button>
        </div>
        <div className="flex gap-2 p-1 bg-gray-100 rounded-lg overflow-x-auto shrink-0">
          {TABS.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`px-4 py-2 rounded-md text-sm font-medium transition ${
                activeTab === tab.id
                  ? 'bg-white text-orange-600 shadow-sm'
                  : 'text-gray-600 hover:text-gray-800'
              }`}
            >
              <span className="mr-1.5">{tab.icon}</span>
              {tab.label}
              {tab.id === 'pending_deletion' && pendingDeletionUsers.length > 0 && (
                <span className="ml-1.5 px-1.5 py-0.5 text-xs bg-orange-100 text-orange-600 rounded">
                  {pendingDeletionUsers.length}
                </span>
              )}
            </button>
          ))}
        </div>
        <input
          type="text"
          placeholder="Cari nama, email, telepon, role..."
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="px-4 py-2 border border-gray-200 rounded-lg text-sm focus:ring-2 focus:ring-orange-500/30 focus:border-orange-500 w-full sm:w-72"
        />
      </div>
      <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
      <div className="overflow-x-auto">
      <table className="w-full min-w-[640px]">
        <thead className="bg-gray-50">
          <tr>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Nama</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Email</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Telepon</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Role</th>
            {activeTab === 'pending_deletion' && (
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Sisa Hari</th>
            )}
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Verified</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Aksi</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-200">
          {filteredUsers.map((u) => (
            <tr
              key={u.id}
              onClick={() => openDetail(u)}
              className="cursor-pointer hover:bg-gray-50 transition"
            >
              <td className="px-6 py-4 text-sm">{u.displayName || '-'}</td>
              <td className="px-6 py-4 text-sm">{u.email || '-'}</td>
              <td className="px-6 py-4 text-sm">{u.phoneNumber || '-'}</td>
              <td className="px-6 py-4 text-sm">{u.role || 'penumpang'}</td>
              {activeTab === 'pending_deletion' && (
                <td className="px-6 py-4">
                  <span className="px-2 py-1 text-xs font-medium bg-amber-100 text-amber-800 rounded">
                    {daysUntilDeletion(u)} hari
                  </span>
                </td>
              )}
              <td className="px-6 py-4">{u.verified ? '✓' : '-'}</td>
              <td className="px-6 py-4" onClick={(e) => e.stopPropagation()}>
                {activeTab === 'pending_deletion' ? (
                  <button
                    onClick={() => handleCancelDeletion(u)}
                    disabled={saving}
                    className="px-3 py-1.5 text-sm font-medium text-green-700 bg-green-50 hover:bg-green-100 rounded-lg transition disabled:opacity-50"
                  >
                    Batalkan Penghapusan
                  </button>
                ) : u.role !== 'admin' ? (
                  <button
                    onClick={(e) => openEdit(u, e)}
                    className="p-2 text-gray-400 hover:text-orange-500 hover:bg-orange-50 rounded-lg transition"
                    title="Edit"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                      <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
                    </svg>
                  </button>
                ) : null}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      {loading && <p className="p-6 text-center text-gray-500">Memuat...</p>}
        {!loading && filteredUsers.length === 0 && (
        <p className="p-6 text-center text-gray-500">
          {searchEffective ? 'Tidak ada hasil pencarian' : 'Belum ada pengguna'}
        </p>
      )}
      </div>
      </div>

      {detailUser && (
        <div
          className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
          onClick={(e) => e.target === e.currentTarget && closeDetail()}
          role="dialog"
          aria-modal="true"
          aria-labelledby="detail-modal-title"
        >
          <div ref={detailModalRef} className="bg-white rounded-lg shadow-xl max-w-md w-full max-h-[90vh] overflow-y-auto" onClick={(e) => e.stopPropagation()} tabIndex={-1}>
            <div className="p-6">
              <div className="flex items-start gap-4 mb-6">
                <img
                  src={detailUser.photoUrl || `https://ui-avatars.com/api/?name=${encodeURIComponent(detailUser.displayName || 'U')}&size=96&background=random`}
                  alt=""
                  className="w-24 h-24 rounded-full object-cover bg-gray-200"
                  onError={(e) => {
                    e.target.src = `https://ui-avatars.com/api/?name=${encodeURIComponent(detailUser.displayName || 'U')}&size=96`
                  }}
                />
                <div className="flex-1 min-w-0">
                  <h3 id="detail-modal-title" className="text-lg font-semibold truncate">{detailUser.displayName || '-'}</h3>
                  <p className="text-sm text-gray-500 truncate">{detailUser.email}</p>
                  <p className="text-sm text-gray-600 mt-1">{detailUser.phoneNumber || '-'}</p>
                  <div className="flex flex-wrap items-center gap-2 mt-2">
                    <span className="px-2 py-0.5 text-xs rounded bg-gray-200">{detailUser.role || 'penumpang'}</span>
                    {detailUser.verified && <span className="text-green-600 text-sm">✓ Verified</span>}
                    {detailUser.deletedAt && (
                      <span className="px-2 py-0.5 text-xs rounded bg-amber-100 text-amber-800">Pending Penghapusan</span>
                    )}
                    {detailUser.suspendedAt && (
                      <span className="px-2 py-0.5 text-xs rounded bg-red-100 text-red-800">Diblokir</span>
                    )}
                  </div>
                </div>
              </div>

              <div className="border-t pt-4">
                <h4 className="text-sm font-medium text-gray-700 mb-2">Lokasi Terakhir</h4>
                {userLocation ? (
                  <div className="flex items-center justify-between gap-2 p-3 bg-gray-50 rounded-lg">
                    <div className="text-sm">
                      <p className="text-gray-600">
                        {userLocation.lat.toFixed(6)}, {userLocation.lng.toFixed(6)}
                      </p>
                      {userLocation.updated && (
                        <p className="text-xs text-gray-500 mt-1">
                          Update: {userLocation.updated.toLocaleString('id-ID')}
                        </p>
                      )}
                    </div>
                    <button
                      onClick={() => openMapLocation(userLocation.lat, userLocation.lng)}
                      className="p-2 text-orange-500 hover:bg-orange-50 rounded-lg transition flex-shrink-0"
                      title="Lacak lokasi"
                    >
                      <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                      </svg>
                    </button>
                  </div>
                ) : (
                  <p className="text-sm text-gray-500 py-2">
                    {detailUser.role === 'driver'
                      ? 'Driver tidak aktif / belum ada data lokasi'
                      : 'Belum ada data lokasi dari pesanan'}
                  </p>
                )}
              </div>

              <div className="flex flex-wrap gap-2 mt-6">
                {detailUser.deletedAt && detailUser.role !== 'admin' && (
                  <button
                    onClick={() => handleCancelDeletion(detailUser)}
                    disabled={saving}
                    className="px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 font-medium disabled:opacity-50"
                  >
                    Batalkan Penghapusan
                  </button>
                )}
                {detailUser.role !== 'admin' && (
                  <button
                    onClick={() => handleGenerateRecoveryCode(detailUser)}
                    disabled={recoveryLoading}
                    className="px-4 py-2 bg-amber-600 text-white rounded-lg hover:bg-amber-700 font-medium disabled:opacity-50 flex items-center gap-2"
                    title="Untuk user yang nomor hilang/tidak aktif"
                  >
                    {recoveryLoading ? (
                      <span className="h-4 w-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
                    ) : (
                      <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                        <path fillRule="evenodd" d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z" clipRule="evenodd" />
                      </svg>
                    )}
                    Kode Recovery
                  </button>
                )}
                {detailUser.role !== 'admin' && !detailUser.deletedAt && (
                  <button
                    onClick={() => { closeDetail(); openEdit(detailUser); }}
                    className="flex-1 px-4 py-2 border border-gray-200 rounded-lg text-gray-700 hover:bg-gray-50 flex items-center justify-center gap-2"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                      <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
                    </svg>
                    Edit
                  </button>
                )}
                <button
                  onClick={closeDetail}
                  className="flex-1 px-4 py-2 bg-orange-500 text-white rounded-lg hover:bg-orange-600 font-medium"
                >
                  Tutup
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {recoveryCode && (
        <div
          className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
          onClick={() => setRecoveryCode(null)}
          role="dialog"
          aria-modal="true"
        >
          <div
            className="bg-white rounded-lg shadow-xl max-w-md w-full p-6"
            onClick={(e) => e.stopPropagation()}
          >
            <h3 className="text-lg font-semibold text-amber-800 mb-2">Kode Recovery</h3>
            <p className="text-sm text-gray-600 mb-4">
              Kirim kode ini ke user <strong>{recoveryCode.userName}</strong>. Berlaku 15 menit.
            </p>
            <div className="p-4 bg-amber-50 rounded-lg border border-amber-200 mb-4">
              <p className="text-2xl font-mono font-bold text-center tracking-widest text-amber-900">
                {recoveryCode.code}
              </p>
            </div>
            <p className="text-xs text-gray-500 mb-4">
              User buka app → Login → &quot;Nomor hilang? Masukkan kode recovery&quot; → masukkan kode.
            </p>
            <button
              onClick={() => {
                navigator.clipboard?.writeText(recoveryCode.code)
                alert('Kode disalin ke clipboard')
              }}
              className="w-full px-4 py-2 border border-amber-300 text-amber-800 rounded-lg hover:bg-amber-50 mb-2"
            >
              Salin Kode
            </button>
            <button
              onClick={() => setRecoveryCode(null)}
              className="w-full px-4 py-2 bg-orange-500 text-white rounded-lg hover:bg-orange-600 font-medium"
            >
              Tutup
            </button>
          </div>
        </div>
      )}

      {editingUser && (
        <div
          className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
          onClick={(e) => e.target === e.currentTarget && closeEdit()}
          role="dialog"
          aria-modal="true"
          aria-labelledby="edit-modal-title"
        >
          <div ref={editModalRef} className="bg-white rounded-lg shadow-xl max-w-md w-full p-6" onClick={(e) => e.stopPropagation()} tabIndex={-1}>
            <h3 id="edit-modal-title" className="text-lg font-semibold mb-4">Edit Pengguna</h3>
            <p className="text-sm text-gray-500 mb-4">{editingUser.email}</p>
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Nama</label>
                <input
                  type="text"
                  value={editForm.displayName}
                  onChange={(e) => setEditForm((f) => ({ ...f, displayName: e.target.value }))}
                  className="w-full px-3 py-2 border border-gray-200 rounded-lg focus:ring-2 focus:ring-orange-500/30 focus:border-orange-500"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Telepon</label>
                <input
                  type="text"
                  value={editForm.phoneNumber}
                  onChange={(e) => setEditForm((f) => ({ ...f, phoneNumber: e.target.value }))}
                  className="w-full px-3 py-2 border border-gray-200 rounded-lg focus:ring-2 focus:ring-orange-500/30 focus:border-orange-500"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Role</label>
                <p className="px-3 py-2 bg-gray-100 rounded-lg text-gray-700 text-sm">
                  {editingUser.role === 'driver' ? 'Driver' : 'Penumpang'}
                </p>
                <p className="text-xs text-gray-500 mt-1">Role tidak dapat diubah</p>
              </div>
              <div className="flex items-center gap-2">
                <input
                  type="checkbox"
                  id="verified"
                  checked={editForm.verified}
                  onChange={(e) => setEditForm((f) => ({ ...f, verified: e.target.checked }))}
                  className="rounded border-gray-300 text-orange-500 focus:ring-orange-500"
                />
                <label htmlFor="verified" className="text-sm font-medium text-gray-700">Verified</label>
              </div>
            </div>
            <div className="flex gap-2 mt-6 justify-end">
              <button
                onClick={closeEdit}
                disabled={saving}
                className="px-4 py-2 border border-gray-300 rounded-lg text-gray-700 hover:bg-gray-50 disabled:opacity-50"
              >
                Batal
              </button>
              <button
                onClick={handleSaveEdit}
                disabled={saving}
                className="px-4 py-2 bg-orange-500 text-white rounded-lg hover:bg-orange-600 disabled:opacity-50"
              >
                {saving ? 'Menyimpan...' : 'Simpan'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
