import { useState, useEffect, useRef } from 'react'
import { useOutletContext } from 'react-router-dom'
import { useFocusTrap } from '../hooks/useFocusTrap'
import {
  collection,
  getDocs,
  doc,
  updateDoc,
  getDoc,
  setDoc,
  deleteDoc,
  query,
  where,
  limit,
  deleteField,
  serverTimestamp,
  Timestamp,
} from 'firebase/firestore'
import { db, functions, httpsCallable } from '../firebase'
import { isApiEnabled } from '../config/apiConfig'
import { getDriverStatus } from '../services/trakaApi'
import { downloadCsv } from '../utils/exportCsv'
import { logAudit } from '../utils/auditLog'

const TABS = [
  { id: 'all', label: 'Semua Pengguna', icon: '👥' },
  { id: 'pending_deletion', label: 'Menunggu penghapusan', icon: '⏳' },
]

function formatFirestoreDate(v) {
  if (!v) return ''
  const d = typeof v.toDate === 'function' ? v.toDate() : null
  if (d && !Number.isNaN(d.getTime())) return d.toLocaleString('id-ID')
  return ''
}

/** Foto profil / verifikasi wajah (URL di users). */
function hasFaceVerification(u) {
  return !!(u.faceVerificationUrl && String(u.faceVerificationUrl).trim())
}

/** Penumpang: NIK KTP terverifikasi (hash + tanggal; foto KTP tidak disimpan di app). */
function hasKtpVerified(u) {
  return !!(u.passengerKTPVerifiedAt || u.passengerKTPNomorHash)
}

/** Driver: SIM terverifikasi (hash + nama; foto SIM tidak disimpan di app). */
function hasSimVerified(u) {
  return !!(u.driverSIMVerifiedAt || u.driverSIMNomorHash)
}

/** Driver: plat/kendaraan tersimpan. */
function hasVehicleSaved(u) {
  return !!(u.vehiclePlat || u.vehicleUpdatedAt)
}

function driverStnkChangePending(u) {
  return u.role === 'driver' && !!u.vehicleChangeRequestAt
}

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
  const [adminVerifMsg, setAdminVerifMsg] = useState('')
  const [adminVerifRestrict, setAdminVerifRestrict] = useState(true)
  const [adminVerifDeadline, setAdminVerifDeadline] = useState('')
  const [vehicleForm, setVehicleForm] = useState({
    plat: '',
    merek: '',
    type: '',
    jumlah: '',
  })
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

  useEffect(() => {
    if (!detailUser) return
    setAdminVerifMsg(detailUser.adminVerificationMessage || '')
    setAdminVerifRestrict(detailUser.adminVerificationRestrictFeatures !== false)
    const da = detailUser.adminVerificationDeadlineAt?.toDate?.()
    if (da && !Number.isNaN(da.getTime())) {
      const local = new Date(da.getTime() - da.getTimezoneOffset() * 60000)
      setAdminVerifDeadline(local.toISOString().slice(0, 16))
    } else {
      setAdminVerifDeadline('')
    }
  }, [detailUser])

  useEffect(() => {
    if (!detailUser || detailUser.role !== 'driver') return
    setVehicleForm({
      plat: detailUser.vehiclePlat || '',
      merek: detailUser.vehicleMerek || '',
      type: detailUser.vehicleType || '',
      jumlah:
        detailUser.vehicleJumlahPenumpang != null
          ? String(detailUser.vehicleJumlahPenumpang)
          : '',
    })
  }, [detailUser])

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
          const r = await getDriverStatus(u.id)
          d = r.driver
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

  const handleSaveAdminVerification = async () => {
    if (!detailUser || detailUser.role === 'admin') return
    const msg = adminVerifMsg.trim()
    if (!msg) {
      alert('Isi pesan untuk pengguna (apa yang harus dikirim/diperbaiki).')
      return
    }
    setSaving(true)
    try {
      const payload = {
        adminVerificationPendingAt: serverTimestamp(),
        adminVerificationMessage: msg,
        adminVerificationRestrictFeatures: adminVerifRestrict,
        adminVerificationUserSubmittedAt: deleteField(),
      }
      if (adminVerifDeadline) {
        const d = new Date(adminVerifDeadline)
        if (!Number.isNaN(d.getTime())) {
          payload.adminVerificationDeadlineAt = Timestamp.fromDate(d)
        }
      } else {
        payload.adminVerificationDeadlineAt = deleteField()
      }
      await updateDoc(doc(db, 'users', detailUser.id), payload)
      await logAudit('admin_verification_request', { userId: detailUser.id })
      loadUsers()
      closeDetail()
    } catch (err) {
      console.error(err)
      alert('Gagal menyimpan: ' + (err.message || err))
    } finally {
      setSaving(false)
    }
  }

  const handleClearVehicleChangeRequest = async () => {
    if (!detailUser || detailUser.role !== 'driver') return
    if (
      !confirm(
        'Hapus tanda permintaan ubah kendaraan? (Data kendaraan yang tersimpan tidak berubah.)',
      )
    )
      return
    setSaving(true)
    try {
      await updateDoc(doc(db, 'users', detailUser.id), {
        vehicleChangeRequestAt: deleteField(),
        vehicleChangeRequestStnkUrl: deleteField(),
        vehicleChangeRequestNote: deleteField(),
      })
      await logAudit('vehicle_change_request_clear', { userId: detailUser.id })
      loadUsers()
      setDetailUser({
        ...detailUser,
        vehicleChangeRequestAt: undefined,
        vehicleChangeRequestStnkUrl: undefined,
        vehicleChangeRequestNote: undefined,
      })
    } catch (err) {
      console.error(err)
      alert('Gagal: ' + (err.message || err))
    } finally {
      setSaving(false)
    }
  }

  const handleSaveDriverVehicle = async () => {
    if (!detailUser || detailUser.role !== 'driver') return
    const plat = (vehicleForm.plat || '').trim().toUpperCase()
    if (!plat) {
      alert('Nomor plat wajib diisi.')
      return
    }
    const jumlah = parseInt(String(vehicleForm.jumlah).trim(), 10)
    setSaving(true)
    try {
      const uid = detailUser.id
      const oldPlat = detailUser.vehiclePlat
      if (oldPlat && oldPlat !== plat) {
        try {
          await deleteDoc(doc(db, 'vehicles', oldPlat))
        } catch (e) {
          console.warn(e)
        }
      }
      const vehicleRef = doc(db, 'vehicles', plat)
      const existingV = await getDoc(vehicleRef)
      const vehiclePayload = {
        driverUid: uid,
        nomorPlat: plat,
        merek: vehicleForm.merek.trim() || null,
        type: vehicleForm.type.trim() || null,
        jumlahPenumpang: Number.isNaN(jumlah) ? null : jumlah,
        updatedAt: serverTimestamp(),
      }
      if (!existingV.exists()) {
        vehiclePayload.createdAt = serverTimestamp()
      }
      await setDoc(vehicleRef, vehiclePayload, { merge: true })
      await updateDoc(doc(db, 'users', uid), {
        vehiclePlat: plat,
        vehicleMerek: vehicleForm.merek.trim() || null,
        vehicleType: vehicleForm.type.trim() || null,
        vehicleJumlahPenumpang: Number.isNaN(jumlah) ? null : jumlah,
        vehicleUpdatedAt: serverTimestamp(),
        vehicleChangeRequestAt: deleteField(),
        vehicleChangeRequestStnkUrl: deleteField(),
        vehicleChangeRequestNote: deleteField(),
      })
      await logAudit('admin_vehicle_update', { userId: uid, plat })
      loadUsers()
      setDetailUser({
        ...detailUser,
        vehiclePlat: plat,
        vehicleMerek: vehicleForm.merek.trim() || null,
        vehicleType: vehicleForm.type.trim() || null,
        vehicleJumlahPenumpang: Number.isNaN(jumlah) ? null : jumlah,
        vehicleChangeRequestAt: undefined,
        vehicleChangeRequestStnkUrl: undefined,
        vehicleChangeRequestNote: undefined,
      })
    } catch (err) {
      console.error(err)
      alert('Gagal menyimpan data kendaraan: ' + (err.message || err))
    } finally {
      setSaving(false)
    }
  }

  const handleClearAdminVerification = async () => {
    if (!detailUser || detailUser.role === 'admin') return
    if (!confirm('Hapus permintaan verifikasi dan pembatasan fitur untuk pengguna ini?')) return
    setSaving(true)
    try {
      await updateDoc(doc(db, 'users', detailUser.id), {
        adminVerificationPendingAt: deleteField(),
        adminVerificationMessage: deleteField(),
        adminVerificationDeadlineAt: deleteField(),
        adminVerificationRestrictFeatures: deleteField(),
        adminVerificationUserSubmittedAt: deleteField(),
      })
      await logAudit('admin_verification_clear', { userId: detailUser.id })
      loadUsers()
      closeDetail()
    } catch (err) {
      console.error(err)
      alert('Gagal: ' + (err.message || err))
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
                mintaDataAdmin: u.adminVerificationPendingAt
                  ? (u.adminVerificationUserSubmittedAt
                      ? `Sudah konfirmasi kirim (${formatFirestoreDate(u.adminVerificationUserSubmittedAt)})`
                      : 'Menunggu pengguna')
                  : '',
                mintaUbahKendaraan: u.role === 'driver' && u.vehicleChangeRequestAt
                  ? `Ya (${formatFirestoreDate(u.vehicleChangeRequestAt)})`
                  : '',
                verifikasiWajah: hasFaceVerification(u) ? 'Ya' : 'Tidak',
                verifikasiKTP: hasKtpVerified(u) ? `Ya (${formatFirestoreDate(u.passengerKTPVerifiedAt)})` : 'Tidak',
                verifikasiSIM:
                  u.role === 'driver'
                    ? hasSimVerified(u)
                      ? `Ya (${formatFirestoreDate(u.driverSIMVerifiedAt)})`
                      : 'Tidak'
                    : '',
                verifikasiMobil:
                  u.role === 'driver'
                    ? hasVehicleSaved(u)
                      ? `Ya (${u.vehiclePlat || ''})`
                      : 'Tidak'
                    : '',
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
          placeholder="Cari nama, email, telepon, peran..."
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="px-4 py-2 border border-gray-200 rounded-lg text-sm focus:ring-2 focus:ring-orange-500/30 focus:border-orange-500 w-full sm:w-72"
        />
      </div>
      <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
      <div className="overflow-x-auto">
      <table className="w-full min-w-[960px]">
        <thead className="bg-gray-50">
          <tr>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Nama</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Email</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Telepon</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Role</th>
            {activeTab === 'pending_deletion' && (
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Sisa Hari</th>
            )}
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Terverifikasi</th>
            <th
              className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase max-w-[200px]"
              title="Wajah, KTP (penumpang), SIM & mobil (driver). Foto KTP/SIM tidak disimpan di server."
            >
              Verifikasi app
            </th>
            <th
              className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase max-w-[140px]"
              title="Permintaan verifikasi dari admin: apakah pengguna sudah konfirmasi kirim di app"
            >
              Minta data
            </th>
            <th
              className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase max-w-[120px]"
              title="Driver mengirim foto STNK untuk minta ubah data kendaraan"
            >
              Ubah STNK
            </th>
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
              <td className="px-6 py-4 text-sm">
                {u.verified ? (
                  u.adminVerificationPendingAt ? (
                    <span
                      className="text-amber-600 font-semibold"
                      title="Permintaan verifikasi admin aktif (sama dengan centang kuning di app)"
                    >
                      ✓
                    </span>
                  ) : (
                    <span className="text-green-600 font-semibold" title="Terverifikasi">
                      ✓
                    </span>
                  )
                ) : (
                  '-'
                )}
              </td>
              <td className="px-6 py-4 text-xs text-gray-700 max-w-[200px]">
                <div className="flex flex-wrap gap-x-2 gap-y-1">
                  <span
                    className={hasFaceVerification(u) ? 'text-green-700 font-medium' : 'text-gray-400'}
                    title="Foto wajah (profil / verifikasi)"
                  >
                    Wajah{hasFaceVerification(u) ? '✓' : '—'}
                  </span>
                  {(u.role === 'penumpang' || !u.role) && (
                    <span
                      className={hasKtpVerified(u) ? 'text-green-700 font-medium' : 'text-gray-400'}
                      title="KTP: hash NIK tersimpan (foto tidak disimpan)"
                    >
                      KTP{hasKtpVerified(u) ? '✓' : '—'}
                    </span>
                  )}
                  {u.role === 'driver' && (
                    <>
                      <span
                        className={hasSimVerified(u) ? 'text-green-700 font-medium' : 'text-gray-400'}
                        title="SIM: nama + hash nomor (foto tidak disimpan)"
                      >
                        SIM{hasSimVerified(u) ? '✓' : '—'}
                      </span>
                      <span
                        className={hasVehicleSaved(u) ? 'text-green-700 font-medium' : 'text-gray-400'}
                        title="Data kendaraan (plat/merek)"
                      >
                        Mobil{hasVehicleSaved(u) ? '✓' : '—'}
                      </span>
                      <span
                        className={driverStnkChangePending(u) ? 'text-amber-800 font-medium' : 'text-gray-400'}
                        title="Permintaan ubah kendaraan (foto STNK dari driver)"
                      >
                        STNK{driverStnkChangePending(u) ? '!' : '—'}
                      </span>
                    </>
                  )}
                </div>
              </td>
              <td className="px-6 py-4 text-sm">
                {!u.adminVerificationPendingAt ? (
                  <span className="text-gray-400">—</span>
                ) : u.adminVerificationUserSubmittedAt ? (
                  <span
                    className="inline-flex px-2 py-0.5 text-xs font-medium rounded-md bg-green-100 text-green-800"
                    title={formatFirestoreDate(u.adminVerificationUserSubmittedAt)}
                  >
                    Sudah kirim
                  </span>
                ) : (
                  <span className="inline-flex px-2 py-0.5 text-xs font-medium rounded-md bg-amber-100 text-amber-900">
                    Menunggu
                  </span>
                )}
              </td>
              <td className="px-6 py-4 text-sm">
                {u.role === 'driver' && u.vehicleChangeRequestAt ? (
                  <span
                    className="inline-flex px-2 py-0.5 text-xs font-medium rounded-md bg-amber-100 text-amber-900"
                    title={formatFirestoreDate(u.vehicleChangeRequestAt)}
                  >
                    Minta ubah
                  </span>
                ) : (
                  <span className="text-gray-400">—</span>
                )}
              </td>
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
                    {detailUser.verified && (
                      <span
                        className={
                          detailUser.adminVerificationPendingAt
                            ? 'text-amber-600 text-sm font-medium'
                            : 'text-green-600 text-sm'
                        }
                        title={
                          detailUser.adminVerificationPendingAt
                            ? 'Akun terverifikasi; admin masih menunggu data (centang kuning di app)'
                            : ''
                        }
                      >
                        {detailUser.adminVerificationPendingAt ? '✓ Terverifikasi (minta data)' : '✓ Terverifikasi'}
                      </span>
                    )}
                    {detailUser.deletedAt && (
                      <span className="px-2 py-0.5 text-xs rounded bg-amber-100 text-amber-800">Menunggu penghapusan</span>
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

              {detailUser.role !== 'admin' && (
                <div className="border-t pt-4 mt-4">
                  <h4 className="text-sm font-medium text-gray-700 mb-2">Verifikasi dokumen (di aplikasi)</h4>
                  <p className="text-xs text-gray-500 mb-3">
                    Foto KTP dan SIM tidak diunggah ke penyimpanan; yang tersimpan hanya hash NIK / hash nomor SIM
                    dan nama (SIM). Foto wajah dipakai untuk profil dan keamanan.
                  </p>
                  <ul className="space-y-3 text-sm text-gray-800">
                    <li className="flex flex-col gap-1 border-b border-gray-100 pb-2">
                      <span className="font-medium text-gray-700">Foto wajah</span>
                      {hasFaceVerification(detailUser) ? (
                        <a
                          href={detailUser.faceVerificationUrl}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="text-orange-600 text-sm font-medium underline break-all"
                        >
                          Buka URL foto wajah
                        </a>
                      ) : (
                        <span className="text-gray-400">Belum ada</span>
                      )}
                    </li>
                    {(detailUser.role === 'penumpang' || !detailUser.role) && (
                      <li className="flex flex-col gap-1 border-b border-gray-100 pb-2">
                        <span className="font-medium text-gray-700">KTP (NIK)</span>
                        {hasKtpVerified(detailUser) ? (
                          <>
                            <span className="text-green-700">Terverifikasi</span>
                            {detailUser.passengerKTPVerifiedAt && (
                              <span className="text-xs text-gray-600">
                                Waktu: {formatFirestoreDate(detailUser.passengerKTPVerifiedAt)}
                              </span>
                            )}
                            <span className="text-xs text-gray-500">
                              Foto KTP tidak disimpan; NIK disimpan sebagai hash (SHA-256).
                            </span>
                          </>
                        ) : (
                          <span className="text-gray-400">Belum</span>
                        )}
                      </li>
                    )}
                    {detailUser.role === 'driver' && (
                      <>
                        <li className="flex flex-col gap-1 border-b border-gray-100 pb-2">
                          <span className="font-medium text-gray-700">SIM</span>
                          {hasSimVerified(detailUser) ? (
                            <>
                              <span className="text-green-700">Terverifikasi</span>
                              {detailUser.driverSIMNama && (
                                <span className="text-sm">Nama di SIM: {detailUser.driverSIMNama}</span>
                              )}
                              {detailUser.driverSIMVerifiedAt && (
                                <span className="text-xs text-gray-600">
                                  Waktu: {formatFirestoreDate(detailUser.driverSIMVerifiedAt)}
                                </span>
                              )}
                              <span className="text-xs text-gray-500">
                                Foto SIM tidak disimpan; nomor SIM disimpan sebagai hash.
                              </span>
                            </>
                          ) : (
                            <span className="text-gray-400">Belum</span>
                          )}
                        </li>
                        <li className="flex flex-col gap-1 pb-1">
                          <span className="font-medium text-gray-700">Data kendaraan (ringkas)</span>
                          {hasVehicleSaved(detailUser) ? (
                            <span className="text-sm">
                              Plat: {detailUser.vehiclePlat || '—'}
                              {detailUser.vehicleMerek ? ` · ${detailUser.vehicleMerek}` : ''}
                              {detailUser.vehicleType ? ` · ${detailUser.vehicleType}` : ''}
                            </span>
                          ) : (
                            <span className="text-gray-400">Belum</span>
                          )}
                          {driverStnkChangePending(detailUser) && (
                            <p className="text-xs text-amber-800 mt-1">
                              Ada permintaan ubah + foto STNK — detail di bagian{' '}
                              <strong>Data kendaraan (admin)</strong> di bawah.
                            </p>
                          )}
                        </li>
                      </>
                    )}
                  </ul>
                </div>
              )}

              {detailUser.role === 'driver' && (
                <div className="border-t pt-4 mt-4">
                  <h4 className="text-sm font-medium text-gray-700 mb-2">Data kendaraan (admin)</h4>
                  <p className="text-xs text-gray-500 mb-3">
                    Driver tidak bisa mengubah plat/merek sendiri setelah data tersimpan. Jika ada permintaan, mereka mengunggah foto STNK; Anda ubah data di bawah lalu simpan.
                  </p>
                  {detailUser.vehicleChangeRequestAt && (
                    <div
                      className={`rounded-lg p-3 mb-3 border ${
                        detailUser.vehicleChangeRequestStnkUrl
                          ? 'bg-amber-50 border-amber-200'
                          : 'bg-gray-50 border-gray-200'
                      }`}
                    >
                      <p className="text-sm font-semibold text-gray-900">
                        Driver meminta perubahan data kendaraan
                      </p>
                      <p className="text-xs text-gray-600 mt-1">
                        Dikirim:{' '}
                        <strong>{formatFirestoreDate(detailUser.vehicleChangeRequestAt)}</strong>
                      </p>
                      {detailUser.vehicleChangeRequestStnkUrl && (
                        <a
                          href={detailUser.vehicleChangeRequestStnkUrl}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="inline-block mt-2 text-sm text-orange-600 font-medium underline"
                        >
                          Buka foto STNK
                        </a>
                      )}
                      {detailUser.vehicleChangeRequestNote && (
                        <p className="text-xs text-gray-700 mt-2">
                          Catatan driver: {detailUser.vehicleChangeRequestNote}
                        </p>
                      )}
                      <button
                        type="button"
                        onClick={handleClearVehicleChangeRequest}
                        disabled={saving}
                        className="mt-3 px-3 py-1.5 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 disabled:opacity-50"
                      >
                        Hapus tanda permintaan (tanpa ubah data)
                      </button>
                    </div>
                  )}
                  <div className="space-y-2">
                    <label className="block text-xs font-medium text-gray-600">Plat</label>
                    <input
                      type="text"
                      value={vehicleForm.plat}
                      onChange={(e) =>
                        setVehicleForm((f) => ({ ...f, plat: e.target.value }))
                      }
                      className="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm"
                    />
                    <label className="block text-xs font-medium text-gray-600">Merek</label>
                    <input
                      type="text"
                      value={vehicleForm.merek}
                      onChange={(e) =>
                        setVehicleForm((f) => ({ ...f, merek: e.target.value }))
                      }
                      className="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm"
                    />
                    <label className="block text-xs font-medium text-gray-600">Tipe</label>
                    <input
                      type="text"
                      value={vehicleForm.type}
                      onChange={(e) =>
                        setVehicleForm((f) => ({ ...f, type: e.target.value }))
                      }
                      className="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm"
                    />
                    <label className="block text-xs font-medium text-gray-600">Jumlah penumpang</label>
                    <input
                      type="number"
                      min={1}
                      value={vehicleForm.jumlah}
                      onChange={(e) =>
                        setVehicleForm((f) => ({ ...f, jumlah: e.target.value }))
                      }
                      className="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm"
                    />
                    <button
                      type="button"
                      onClick={handleSaveDriverVehicle}
                      disabled={saving}
                      className="mt-2 w-full px-4 py-2 bg-orange-600 text-white rounded-lg hover:bg-orange-700 text-sm font-medium disabled:opacity-50"
                    >
                      Simpan data kendaraan
                    </button>
                  </div>
                </div>
              )}

              {detailUser.role !== 'admin' && (
                <div className="border-t pt-4 mt-4">
                  <h4 className="text-sm font-medium text-gray-700 mb-2">Permintaan verifikasi (admin)</h4>
                  <p className="text-xs text-gray-500 mb-3">
                    Pengguna melihat pesan di Profil. Jika pembatasan aktif, pesan travel / mulai kerja diblokir sampai mereka tap &quot;Sudah kirim data&quot; atau Anda menghapus permintaan.
                  </p>
                  {detailUser.adminVerificationPendingAt && (
                    <div
                      className={`rounded-lg p-3 mb-3 border ${
                        detailUser.adminVerificationUserSubmittedAt
                          ? 'bg-green-50 border-green-200'
                          : 'bg-amber-50 border-amber-200'
                      }`}
                    >
                      <p className="text-sm font-semibold text-gray-900">
                        {detailUser.adminVerificationUserSubmittedAt
                          ? 'Pengguna sudah konfirmasi kirim di aplikasi'
                          : 'Menunggu: pengguna belum menekan konfirmasi kirim di aplikasi'}
                      </p>
                      {detailUser.adminVerificationUserSubmittedAt && (
                        <p className="text-xs text-gray-700 mt-1.5">
                          Waktu konfirmasi:{' '}
                          <strong>{formatFirestoreDate(detailUser.adminVerificationUserSubmittedAt)}</strong>
                        </p>
                      )}
                      <p className="text-xs text-gray-600 mt-2">
                        Kolom <strong>Minta data</strong> di daftar pengguna juga berubah menjadi &quot;Sudah kirim&quot; atau &quot;Menunggu&quot;.
                      </p>
                    </div>
                  )}
                  <label className="block text-xs font-medium text-gray-600 mb-1">Pesan ke pengguna</label>
                  <textarea
                    value={adminVerifMsg}
                    onChange={(e) => setAdminVerifMsg(e.target.value)}
                    rows={3}
                    className="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm focus:ring-2 focus:ring-orange-500/30 focus:border-orange-500 mb-3"
                    placeholder="Contoh: Mohon foto STNK/plat lebih jelas. / Mohon unggah ulang foto SIM."
                  />
                  <label className="flex items-center gap-2 text-sm text-gray-700 mb-2">
                    <input
                      type="checkbox"
                      checked={adminVerifRestrict}
                      onChange={(e) => setAdminVerifRestrict(e.target.checked)}
                      className="rounded border-gray-300 text-orange-500 focus:ring-orange-500"
                    />
                    Batasi fitur (pesan order / mulai kerja driver) sampai pengguna konfirmasi
                  </label>
                  <label className="block text-xs font-medium text-gray-600 mb-1">Batas waktu (opsional)</label>
                  <input
                    type="datetime-local"
                    value={adminVerifDeadline}
                    onChange={(e) => setAdminVerifDeadline(e.target.value)}
                    className="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm mb-3"
                  />
                  <div className="flex flex-wrap gap-2">
                    <button
                      type="button"
                      onClick={handleSaveAdminVerification}
                      disabled={saving}
                      className="px-4 py-2 bg-orange-600 text-white rounded-lg hover:bg-orange-700 text-sm font-medium disabled:opacity-50"
                    >
                      Simpan permintaan
                    </button>
                    <button
                      type="button"
                      onClick={handleClearAdminVerification}
                      disabled={saving || !detailUser.adminVerificationPendingAt}
                      className="px-4 py-2 border border-gray-300 rounded-lg text-gray-700 text-sm hover:bg-gray-50 disabled:opacity-50"
                    >
                      Hapus permintaan
                    </button>
                  </div>
                </div>
              )}

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
              Pengguna buka aplikasi → Login → &quot;Nomor hilang? Masukkan kode recovery&quot; → masukkan kode.
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
                <label htmlFor="verified" className="text-sm font-medium text-gray-700">Terverifikasi</label>
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
