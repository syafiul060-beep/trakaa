import { useState, useEffect, useRef } from 'react'
import { Link, useOutletContext } from 'react-router-dom'
import { collection, getDocs, query, orderBy, limit, startAfter, onSnapshot } from 'firebase/firestore'
import { db } from '../firebase'
import { downloadCsv } from '../utils/exportCsv'

const PAGE_SIZE = 50

export default function Orders() {
  const { searchQuery: contextSearch = '' } = useOutletContext() || {}
  const [baseOrders, setBaseOrders] = useState([])
  const [extraOrders, setExtraOrders] = useState([])
  const [loading, setLoading] = useState(true)
  const [filter, setFilter] = useState('all')
  const [searchQuery, setSearchQuery] = useState('')
  const [hasMore, setHasMore] = useState(true)
  const [loadingMore, setLoadingMore] = useState(false)
  const lastDocRef = useRef(null)
  const extraOrdersRef = useRef([])
  extraOrdersRef.current = extraOrders

  const orders = [...(Array.isArray(baseOrders) ? baseOrders : []), ...(Array.isArray(extraOrders) ? extraOrders : [])]
  const searchEffective = (contextSearch || searchQuery).trim().toLowerCase()

  // Real-time: subscribe ke 50 order terbaru
  useEffect(() => {
    setLoading(true)
    const q = query(
      collection(db, 'orders'),
      orderBy('createdAt', 'desc'),
      limit(PAGE_SIZE)
    )
    const unsub = onSnapshot(
      q,
      (snap) => {
        const list = snap.docs.map((d) => ({ id: d.id, ...d.data() }))
        setBaseOrders(list)
        if (extraOrdersRef.current.length === 0) {
          lastDocRef.current = snap.docs.length > 0 ? snap.docs[snap.docs.length - 1] : null
          setHasMore(snap.docs.length === PAGE_SIZE)
        }
        setLoading(false)
      },
      (err) => {
        console.error('Orders onSnapshot error:', err)
        setLoading(false)
      }
    )
    return () => unsub()
  }, [])

  const loadMore = async () => {
    if (!lastDocRef.current || loadingMore || !hasMore) return
    setLoadingMore(true)
    try {
      const q = query(
        collection(db, 'orders'),
        orderBy('createdAt', 'desc'),
        startAfter(lastDocRef.current),
        limit(PAGE_SIZE)
      )
      const snap = await getDocs(q)
      const list = snap.docs.map((d) => ({ id: d.id, ...d.data() }))
      setExtraOrders((prev) => [...prev, ...list])
      lastDocRef.current = snap.docs.length > 0 ? snap.docs[snap.docs.length - 1] : null
      setHasMore(snap.docs.length === PAGE_SIZE)
    } finally {
      setLoadingMore(false)
    }
  }

  const statusFiltered = filter === 'all'
    ? orders
    : orders.filter((o) => o.status === filter)

  const filtered = searchEffective
    ? statusFiltered.filter((o) => {
        const orderNum = (o.orderNumber || o.id || '').toString().toLowerCase()
        const passenger = (o.passengerName || '').toLowerCase()
        const origin = (o.originText || '').toLowerCase()
        const dest = (o.destText || '').toLowerCase()
        const status = (o.status || '').toLowerCase()
        const type = (o.orderType === 'kirim_barang' ? 'kirim barang' : 'travel').toLowerCase()
        return (
          orderNum.includes(searchEffective) ||
          passenger.includes(searchEffective) ||
          origin.includes(searchEffective) ||
          dest.includes(searchEffective) ||
          status.includes(searchEffective) ||
          type.includes(searchEffective)
        )
      })
    : statusFiltered

  const statusLabel = (s) => {
    const map = {
      pending_agreement: 'Pending',
      agreed: 'Agreed',
      picked_up: 'Di Jalan',
      completed: 'Selesai',
      cancelled: 'Dibatalkan',
    }
    return map[s] || s
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-col sm:flex-row gap-4 sm:items-center sm:justify-between">
        <div className="flex gap-2 flex-wrap items-center">
          <button
            onClick={() => {
              const rows = filtered.map((o) => ({
                id: o.id,
                orderNumber: o.orderNumber || '',
                passengerName: o.passengerName || '',
                originText: o.originText || '',
                destText: o.destText || '',
                orderType: o.orderType || '',
                jenis: o.orderType === 'kirim_barang' ? 'Kirim Barang' : 'Travel',
                status: o.status || '',
                createdAt: o.createdAt?.toDate?.()?.toLocaleString('id-ID') || '',
                createdAtRaw: o.createdAt?.toDate?.()?.toISOString?.() || '',
              }))
              downloadCsv(rows, 'orders')
            }}
            className="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-lg transition"
          >
            📥 Ekspor CSV
          </button>
        {['all', 'pending_agreement', 'agreed', 'picked_up', 'completed', 'cancelled'].map((f) => (
          <button
            key={f}
            onClick={() => setFilter(f)}
            className={`px-4 py-2 rounded-lg text-sm font-medium ${
              filter === f ? 'bg-traka-orange text-white' : 'bg-gray-200 text-gray-700'
            }`}
          >
            {f === 'all' ? 'Semua' : statusLabel(f)}
          </button>
        ))}
        </div>
        <input
          type="text"
          placeholder="Cari no. pesanan, penumpang, rute, status..."
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="px-4 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-traka-orange focus:border-traka-orange w-full sm:w-72"
        />
      </div>

      <div className="bg-white rounded-lg shadow overflow-hidden">
        <div className="overflow-x-auto">
        <table className="w-full min-w-[640px]">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">No.</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Penumpang</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Rute</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Tipe</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Tanggal</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Aksi</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {filtered.map((o) => (
              <tr key={o.id}>
                <td className="px-6 py-4 text-sm">{o.orderNumber || o.id.slice(0, 8)}</td>
                <td className="px-6 py-4 text-sm">{o.passengerName || '-'}</td>
                <td className="px-6 py-4 text-sm">{o.originText} → {o.destText}</td>
                <td className="px-6 py-4 text-sm">{o.orderType === 'kirim_barang' ? 'Kirim Barang' : 'Travel'}</td>
                <td className="px-6 py-4">
                  <span className={`px-2 py-1 text-xs rounded ${
                    o.status === 'completed' ? 'bg-green-100 text-green-800' :
                    o.status === 'cancelled' ? 'bg-red-100 text-red-800' :
                    'bg-amber-100 text-amber-800'
                  }`}>
                    {statusLabel(o.status)}
                  </span>
                </td>
                <td className="px-6 py-4 text-sm text-gray-600">
                  {o.createdAt?.toDate?.()?.toLocaleDateString('id-ID') || '-'}
                </td>
                <td className="px-6 py-4">
                  <Link to={`/orders/${o.id}`} className="text-traka-orange hover:underline text-sm">
                    Detail
                  </Link>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {loading && <p className="p-6 text-center text-gray-500">Memuat...</p>}
        {!loading && filtered.length === 0 && (
          <p className="p-6 text-center text-gray-500">Tidak ada data</p>
        )}
        {hasMore && !searchEffective && (
          <div className="p-4 text-center border-t">
            <button
              onClick={loadMore}
              disabled={loadingMore}
              className="px-4 py-2 text-sm font-medium text-orange-600 hover:bg-orange-50 rounded-lg disabled:opacity-50"
            >
              {loadingMore ? 'Memuat...' : 'Muat lebih banyak'}
            </button>
          </div>
        )}
        </div>
      </div>
    </div>
  )
}
