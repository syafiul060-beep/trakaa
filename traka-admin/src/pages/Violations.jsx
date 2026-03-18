import { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { collection, getDocs, query, orderBy, limit, doc, getDoc } from 'firebase/firestore'
import { db } from '../firebase'

export default function Violations() {
  const [violations, setViolations] = useState([])
  const [loading, setLoading] = useState(true)
  const [filter, setFilter] = useState('all') // all | unpaid | paid

  const [usersWithOutstanding, setUsersWithOutstanding] = useState([])

  useEffect(() => {
    loadViolations()
  }, [filter])

  useEffect(() => {
    getDocs(collection(db, 'users')).then((snap) => {
      const withFee = snap.docs
        .filter((d) => (d.data().outstandingViolationFee || 0) > 0)
        .map((d) => ({ id: d.id, ...d.data() }))
      setUsersWithOutstanding(withFee)
    })
  }, [])

  async function loadViolations() {
    setLoading(true)
    try {
      const q = query(
        collection(db, 'violation_records'),
        orderBy('createdAt', 'desc'),
        limit(300)
      )
      const snap = await getDocs(q)
      const items = []
      for (const d of snap.docs) {
        const data = d.data()
        const userDoc = await getDoc(doc(db, 'users', data.userId))
        const userData = userDoc.exists ? userDoc.data() : {}
        items.push({
          id: d.id,
          ...data,
          userName: userData.displayName || '-',
          userEmail: userData.email || '-',
          userPhone: userData.phoneNumber || '-',
          paidAt: data.paidAt?.toDate?.() || null,
          createdAt: data.createdAt?.toDate?.() || null,
        })
      }
      // Filter di client untuk hindari index
      const filtered = filter === 'all'
        ? items
        : filter === 'unpaid'
          ? items.filter((v) => !v.paidAt)
          : items.filter((v) => v.paidAt)
      setViolations(filtered)
    } catch (e) {
      console.error('Load violations error:', e)
      setViolations([])
    }
    setLoading(false)
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap gap-4 items-center justify-between">
        <h2 className="text-xl font-semibold text-gray-800">Pelanggaran (Tidak Scan Barcode)</h2>
        <div className="flex gap-2">
          <button
            onClick={() => setFilter('all')}
            className={`px-4 py-2 rounded-lg text-sm font-medium ${
              filter === 'all' ? 'bg-traka-orange text-white' : 'bg-gray-200 text-gray-700'
            }`}
          >
            Semua
          </button>
          <button
            onClick={() => setFilter('unpaid')}
            className={`px-4 py-2 rounded-lg text-sm font-medium ${
              filter === 'unpaid' ? 'bg-red-500 text-white' : 'bg-gray-200 text-gray-700'
            }`}
          >
            Belum Bayar
          </button>
          <button
            onClick={() => setFilter('paid')}
            className={`px-4 py-2 rounded-lg text-sm font-medium ${
              filter === 'paid' ? 'bg-green-600 text-white' : 'bg-gray-200 text-gray-700'
            }`}
          >
            Sudah Bayar
          </button>
        </div>
      </div>

      <p className="text-sm text-gray-600">
        Pelanggaran terjadi saat driver/penumpang konfirmasi tanpa scan barcode. Penumpang bayar via Google Play; driver bayar via kontribusi.
      </p>

      {usersWithOutstanding.length > 0 && (
        <div className="bg-amber-50 border border-amber-200 rounded-lg p-4">
          <h3 className="font-medium text-amber-900 mb-2">
            Penumpang dengan pelanggaran belum bayar ({usersWithOutstanding.length})
          </h3>
          <div className="flex flex-wrap gap-2">
            {usersWithOutstanding.map((u) => (
              <span
                key={u.id}
                className="inline-flex items-center px-3 py-1 rounded-full text-sm bg-amber-100 text-amber-800"
              >
                {u.displayName || u.email || u.phoneNumber || u.id} — Rp {(u.outstandingViolationFee || 0).toLocaleString('id-ID')}
              </span>
            ))}
          </div>
        </div>
      )}

      <div className="bg-white rounded-lg shadow overflow-hidden">
        <table className="w-full">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Tanggal</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">User</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Tipe</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Order</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Jumlah</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {violations.map((v) => (
              <tr key={v.id}>
                <td className="px-6 py-4 text-sm text-gray-600">
                  {v.createdAt?.toLocaleDateString('id-ID') || '-'}
                </td>
                <td className="px-6 py-4 text-sm">
                  <div>{v.userName}</div>
                  <div className="text-xs text-gray-500">{v.userEmail || v.userPhone || '-'}</div>
                </td>
                <td className="px-6 py-4 text-sm">
                  <span className={`px-2 py-1 rounded text-xs ${
                    v.type === 'passenger' ? 'bg-blue-100 text-blue-800' : 'bg-amber-100 text-amber-800'
                  }`}>
                    {v.type === 'passenger' ? 'Penumpang' : 'Driver'}
                  </span>
                </td>
                <td className="px-6 py-4 text-sm">
                  <Link to={`/orders/${v.orderId}`} className="text-traka-orange hover:underline">
                    {v.orderId?.slice(0, 8)}...
                  </Link>
                </td>
                <td className="px-6 py-4 text-sm font-medium">
                  Rp {(v.amount || 0).toLocaleString('id-ID')}
                </td>
                <td className="px-6 py-4">
                  {v.paidAt ? (
                    <span className="text-green-600 text-sm">
                      ✓ Bayar {v.paidAt?.toLocaleDateString('id-ID')}
                    </span>
                  ) : (
                    <span className="text-red-600 text-sm">Belum bayar</span>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {loading && <p className="p-6 text-center text-gray-500">Memuat...</p>}
        {!loading && violations.length === 0 && (
          <p className="p-6 text-center text-gray-500">Tidak ada data pelanggaran.</p>
        )}
      </div>
    </div>
  )
}
