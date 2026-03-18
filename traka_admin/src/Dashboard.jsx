import { useState, useEffect } from 'react'
import { collection, query, where, getDocs, doc, updateDoc, serverTimestamp, orderBy, limit } from 'firebase/firestore'
import { db } from './firebase'

const SUSPENDED_REASON = 'Pelanggaran ketentuan / kebijakan Traka. Hubungi admin untuk informasi.'

export default function Dashboard({ onLogout, hideHeader }) {
  const [tab, setTab] = useState('kabupaten') // kabupaten | orders
  const [users, setUsers] = useState([])
  const [orders, setOrders] = useState([])
  const [loading, setLoading] = useState(true)
  const [selectedKabupaten, setSelectedKabupaten] = useState(null)
  const [cancelModal, setCancelModal] = useState(null)
  const [cancelReason, setCancelReason] = useState('')
  const [cancelling, setCancelling] = useState(false)
  const [message, setMessage] = useState(null)
  const [searchUser, setSearchUser] = useState('')
  const [searchOrder, setSearchOrder] = useState('')
  const [filterOrderStatus, setFilterOrderStatus] = useState('')

  useEffect(() => {
    loadData()
  }, [])

  async function loadData() {
    setLoading(true)
    try {
      const [usersSnap, ordersSnap] = await Promise.all([
        getDocs(query(collection(db, 'users'), where('role', 'in', ['driver', 'penumpang']))),
        getDocs(query(collection(db, 'orders'), orderBy('createdAt', 'desc'), limit(500)))
      ])
      setUsers(usersSnap.docs.map(d => ({ id: d.id, ...d.data() })))
      setOrders(ordersSnap.docs.map(d => ({ id: d.id, ...d.data() })))
    } catch (e) {
      console.error(e)
      setMessage({ type: 'error', text: 'Gagal memuat data' })
    }
    setLoading(false)
  }

  const today = new Date().toDateString()
  const thisMonth = new Date().getMonth()
  const thisYear = new Date().getFullYear()
  const ordersToday = orders.filter(o => {
    const d = o.createdAt?.toDate?.()
    return d && d.toDateString() === today
  })
  const ordersThisMonth = orders.filter(o => {
    const d = o.createdAt?.toDate?.()
    return d && d.getMonth() === thisMonth && d.getFullYear() === thisYear
  })
  const ordersCompleted = orders.filter(o => o.status === 'completed')
  const ordersPending = orders.filter(o => !o.adminCancelled && !o.driverCancelled && !o.passengerCancelled && ['pending_agreement', 'agreed', 'picked_up'].includes(o.status))
  const driversCount = users.filter(u => u.role === 'driver').length
  const penumpangCount = users.filter(u => u.role === 'penumpang').length

  const byKabupaten = users.reduce((acc, u) => {
    const kab = u.kabupaten || u.region || 'Tidak diketahui'
    if (!acc[kab]) acc[kab] = { drivers: 0, penumpang: 0, users: [] }
    acc[kab].users.push(u)
    if (u.role === 'driver') acc[kab].drivers++
    else acc[kab].penumpang++
    return acc
  }, {})

  const kabupatenList = Object.entries(byKabupaten).sort((a, b) => a[0].localeCompare(b[0]))

  let filteredOrders = selectedKabupaten
    ? orders.filter(o => {
        const pass = users.find(u => u.id === o.passengerUid)
        const drv = users.find(u => u.id === o.driverUid)
        const passKab = pass?.kabupaten || pass?.region
        const drvKab = drv?.kabupaten || drv?.region
        return passKab === selectedKabupaten || drvKab === selectedKabupaten
      })
    : orders
  if (filterOrderStatus) {
    filteredOrders = filteredOrders.filter(o => o.status === filterOrderStatus)
  }
  if (searchOrder.trim()) {
    const q = searchOrder.toLowerCase().trim()
    filteredOrders = filteredOrders.filter(o =>
      (o.orderNumber || '').toLowerCase().includes(q) ||
      (o.passengerName || '').toLowerCase().includes(q) ||
      (o.driverName || '').toLowerCase().includes(q)
    )
  }

  let filteredUsers = selectedKabupaten
    ? (byKabupaten[selectedKabupaten]?.users || [])
    : users
  if (searchUser.trim()) {
    const q = searchUser.toLowerCase().trim()
    filteredUsers = filteredUsers.filter(u =>
      (u.displayName || '').toLowerCase().includes(q) ||
      (u.email || '').toLowerCase().includes(q) ||
      (u.kabupaten || u.region || '').toLowerCase().includes(q)
    )
  }

  async function handleCancelOrder() {
    if (!cancelModal || !cancelReason.trim()) return
    setCancelling(true)
    try {
      await updateDoc(doc(db, 'orders', cancelModal.id), {
        adminCancelled: true,
        adminCancelledAt: serverTimestamp(),
        adminCancelReason: cancelReason.trim(),
        status: 'cancelled',
        updatedAt: serverTimestamp()
      })
      setMessage({ type: 'success', text: 'Pesanan berhasil dibatalkan' })
      setCancelModal(null)
      setCancelReason('')
      loadData()
    } catch (e) {
      setMessage({ type: 'error', text: e.message || 'Gagal membatalkan' })
    }
    setCancelling(false)
  }

  const formatDate = (v) => {
    if (!v?.toDate) return '-'
    return v.toDate().toLocaleString('id-ID')
  }

  async function handleSuspendUser() {
    if (!suspendModal) return
    setSuspending(true)
    try {
      await updateDoc(doc(db, 'users', suspendModal.id), {
        suspendedAt: serverTimestamp(),
        suspendedReason: (suspendReason || SUSPENDED_REASON).trim()
      })
      setMessage({ type: 'success', text: 'User berhasil diblokir' })
      setSuspendModal(null)
      setSuspendReason('')
      loadData()
    } catch (e) {
      setMessage({ type: 'error', text: e.message || 'Gagal memblokir' })
    }
    setSuspending(false)
  }

  async function handleUnsuspendUser(userId) {
    setSuspending(true)
    try {
      await updateDoc(doc(db, 'users', userId), {
        suspendedAt: null,
        suspendedReason: null
      })
      setMessage({ type: 'success', text: 'User berhasil dibuka blokir' })
      loadData()
    } catch (e) {
      setMessage({ type: 'error', text: e.message || 'Gagal membuka blokir' })
    }
    setSuspending(false)
  }

  return (
    <div className="container">
      {!hideHeader && (
        <div className="header">
          <h1>Traka Admin</h1>
          <button className="btn" onClick={onLogout} style={{ background: '#e2e8f0' }}>Logout</button>
        </div>
      )}

      {message && (
        <div className={`alert alert-${message.type}`} onAnimationEnd={() => setMessage(null)}>
          {message.text}
        </div>
      )}

      <div className="stats-grid" style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(160px, 1fr))', gap: 12, marginBottom: 24 }}>
        <div className="card" style={{ padding: 16, textAlign: 'center' }}>
          <div style={{ fontSize: 28, fontWeight: 700, color: '#1d4ed8' }}>{driversCount}</div>
          <div style={{ fontSize: 13, color: '#64748b' }}>Driver</div>
        </div>
        <div className="card" style={{ padding: 16, textAlign: 'center' }}>
          <div style={{ fontSize: 28, fontWeight: 700, color: '#15803d' }}>{penumpangCount}</div>
          <div style={{ fontSize: 13, color: '#64748b' }}>Penumpang</div>
        </div>
        <div className="card" style={{ padding: 16, textAlign: 'center' }}>
          <div style={{ fontSize: 28, fontWeight: 700, color: '#22c55e' }}>{ordersToday.length}</div>
          <div style={{ fontSize: 13, color: '#64748b' }}>Pesanan Hari Ini</div>
        </div>
        <div className="card" style={{ padding: 16, textAlign: 'center' }}>
          <div style={{ fontSize: 28, fontWeight: 700, color: '#0ea5e9' }}>{ordersThisMonth.length}</div>
          <div style={{ fontSize: 13, color: '#64748b' }}>Pesanan Bulan Ini</div>
        </div>
        <div className="card" style={{ padding: 16, textAlign: 'center' }}>
          <div style={{ fontSize: 28, fontWeight: 700, color: '#f59e0b' }}>{ordersPending.length}</div>
          <div style={{ fontSize: 13, color: '#64748b' }}>Sedang Berjalan</div>
        </div>
        <div className="card" style={{ padding: 16, textAlign: 'center' }}>
          <div style={{ fontSize: 28, fontWeight: 700, color: '#64748b' }}>{ordersCompleted.length}</div>
          <div style={{ fontSize: 13, color: '#64748b' }}>Selesai</div>
        </div>
      </div>

      <div style={{ marginBottom: 16, display: 'flex', gap: 8 }}>
        <button className={`btn ${tab === 'kabupaten' ? 'btn-primary' : ''}`} style={tab !== 'kabupaten' ? { background: '#e2e8f0' } : {}} onClick={() => setTab('kabupaten')}>
          Data per Kabupaten
        </button>
        <button className={`btn ${tab === 'orders' ? 'btn-primary' : ''}`} style={tab !== 'orders' ? { background: '#e2e8f0' } : {}} onClick={() => setTab('orders')}>
          Pesanan
        </button>
      </div>

      {selectedKabupaten && (
        <div style={{ marginBottom: 16 }}>
          Filter: <strong>{selectedKabupaten}</strong>
          <button className="btn" style={{ marginLeft: 8, background: '#e2e8f0', padding: '6px 12px' }} onClick={() => setSelectedKabupaten(null)}>Hapus filter</button>
        </div>
      )}

      {tab === 'kabupaten' && (
        <div style={{ marginBottom: 16 }}>
          <input
            type="text"
            placeholder="Cari user (nama, email, kabupaten)..."
            value={searchUser}
            onChange={e => setSearchUser(e.target.value)}
            style={{ width: '100%', maxWidth: 400 }}
          />
        </div>
      )}

      {tab === 'orders' && (
        <div style={{ marginBottom: 16, display: 'flex', gap: 12, flexWrap: 'wrap' }}>
          <input
            type="text"
            placeholder="Cari pesanan (no. pesanan, penumpang, driver)..."
            value={searchOrder}
            onChange={e => setSearchOrder(e.target.value)}
            style={{ flex: 1, minWidth: 200 }}
          />
          <select value={filterOrderStatus} onChange={e => setFilterOrderStatus(e.target.value)} style={{ minWidth: 180 }}>
            <option value="">Semua status</option>
            <option value="pending_agreement">Pending Agreement</option>
            <option value="agreed">Agreed</option>
            <option value="picked_up">Picked Up</option>
            <option value="completed">Completed</option>
            <option value="cancelled">Cancelled</option>
          </select>
        </div>
      )}

      {loading ? (
        <div className="loading">Memuat data...</div>
      ) : tab === 'kabupaten' ? (
        <>
          <div className="grid">
            {kabupatenList.map(([kab, data]) => (
              <div
                key={kab}
                className="card kabupaten-card"
                onClick={() => setSelectedKabupaten(selectedKabupaten === kab ? null : kab)}
              >
                <h3 style={{ marginBottom: 8 }}>{kab}</h3>
                <p style={{ color: '#64748b', fontSize: 14 }}>Driver: {data.drivers} | Penumpang: {data.penumpang}</p>
              </div>
            ))}
          </div>
          {selectedKabupaten && (
            <div className="card" style={{ marginTop: 24 }}>
              <h3 style={{ marginBottom: 16 }}>Daftar User - {selectedKabupaten}</h3>
              <table>
                <thead>
                  <tr>
                    <th>Nama</th>
                    <th>Email</th>
                    <th>Role</th>
                    <th>Kabupaten</th>
                    <th>Status</th>
                    <th>Aksi</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredUsers.map(u => {
                    const suspended = !!u.suspendedAt
                    return (
                      <tr key={u.id}>
                        <td>{u.displayName || '-'}</td>
                        <td>{u.email || '-'}</td>
                        <td><span className={`badge badge-${u.role}`}>{u.role}</span></td>
                        <td>{u.kabupaten || u.region || '-'}</td>
                        <td>
                          {suspended ? (
                            <span className="badge badge-cancelled">Diblokir</span>
                          ) : (
                            <span style={{ color: '#22c55e' }}>Aktif</span>
                          )}
                        </td>
                        <td>
                          {suspended ? (
                            <button className="btn" style={{ padding: '6px 12px', background: '#dcfce7', color: '#15803d' }} onClick={() => handleUnsuspendUser(u.id)} disabled={suspending}>
                              Buka blokir
                            </button>
                          ) : (
                            <button className="btn btn-danger" style={{ padding: '6px 12px' }} onClick={() => setSuspendModal(u)} disabled={suspending}>
                              Blokir
                            </button>
                          )}
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
        </>
      ) : (
        <div className="card">
          <h3 style={{ marginBottom: 16 }}>Daftar Pesanan</h3>
          <table>
            <thead>
              <tr>
                <th>No. Pesanan</th>
                <th>Penumpang</th>
                <th>Driver</th>
                <th>Status</th>
                <th>Dibuat</th>
                <th>Aksi</th>
              </tr>
            </thead>
            <tbody>
              {filteredOrders.map(o => {
                const cancelled = o.adminCancelled || o.driverCancelled || o.passengerCancelled
                return (
                  <tr key={o.id}>
                    <td>{o.orderNumber || o.id.slice(0, 8)}</td>
                    <td>{o.passengerName || '-'}</td>
                    <td>{o.driverName || '-'}</td>
                    <td>
                      {cancelled ? (
                        <span className="badge badge-cancelled">
                          {o.adminCancelled ? 'Dibatalkan admin' : 'Dibatalkan'}
                        </span>
                      ) : (
                        o.status
                      )}
                    </td>
                    <td>{formatDate(o.createdAt)}</td>
                    <td>
                      {!cancelled && (o.status === 'pending_agreement' || o.status === 'agreed' || o.status === 'picked_up') && (
                        <button className="btn btn-danger" style={{ padding: '6px 12px' }} onClick={() => setCancelModal(o)}>
                          Batalkan
                        </button>
                      )}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}

      {suspendModal && (
        <div className="modal-overlay" onClick={() => !suspending && setSuspendModal(null)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <h3>Blokir User</h3>
            <p>Nama: {suspendModal.displayName || '-'}</p>
            <p>Email: {suspendModal.email || '-'}</p>
            <p>Alasan pemblokiran (opsional):</p>
            <textarea value={suspendReason} onChange={e => setSuspendReason(e.target.value)} placeholder={SUSPENDED_REASON} />
            <div className="modal-actions">
              <button className="btn" style={{ background: '#e2e8f0' }} onClick={() => setSuspendModal(null)} disabled={suspending}>Batal</button>
              <button className="btn btn-danger" onClick={handleSuspendUser} disabled={suspending}>
                {suspending ? 'Memproses...' : 'Blokir User'}
              </button>
            </div>
          </div>
        </div>
      )}

      {cancelModal && (
        <div className="modal-overlay" onClick={() => !cancelling && setCancelModal(null)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <h3>Batalkan Pesanan</h3>
            <p>No. Pesanan: {cancelModal.orderNumber || cancelModal.id}</p>
            <p>Alasan pembatalan (wajib):</p>
            <textarea value={cancelReason} onChange={e => setCancelReason(e.target.value)} placeholder="Contoh: Penipuan, pelanggaran syarat, dll." />
            <div className="modal-actions">
              <button className="btn" style={{ background: '#e2e8f0' }} onClick={() => setCancelModal(null)} disabled={cancelling}>Batal</button>
              <button className="btn btn-danger" onClick={handleCancelOrder} disabled={cancelling || !cancelReason.trim()}>
                {cancelling ? 'Memproses...' : 'Batalkan Pesanan'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
