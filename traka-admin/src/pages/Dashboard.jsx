import { useState, useEffect, useRef } from 'react'
import { Link, useOutletContext } from 'react-router-dom'
import { collection, getDocs } from 'firebase/firestore'
import { db } from '../firebase'
import { isApiEnabled } from '../config/apiConfig'
import { getDriverStatusList } from '../services/trakaApi'
import MiniSparkline from '../components/MiniSparkline'

const CARD_CONFIG = [
  {
    key: 'ordersToday',
    label: 'Pesanan Hari Ini',
    icon: '📦',
    bg: 'bg-white',
    border: 'border-slate-100',
    valueColor: 'text-blue-600',
    iconBg: 'bg-blue-100',
    iconColor: 'text-blue-600',
  },
  {
    key: 'driversActive',
    label: 'Driver Aktif',
    icon: '🚗',
    bg: 'bg-white',
    border: 'border-slate-100',
    valueColor: 'text-emerald-600',
    iconBg: 'bg-emerald-100',
    iconColor: 'text-emerald-600',
  },
  {
    key: 'ordersPending',
    label: 'Pesanan menunggu',
    icon: '⏳',
    bg: 'bg-white',
    border: 'border-slate-100',
    valueColor: 'text-amber-600',
    iconBg: 'bg-amber-100',
    iconColor: 'text-amber-600',
  },
  {
    key: 'ordersCompleted',
    label: 'Pesanan Selesai',
    icon: '✅',
    bg: 'bg-white',
    border: 'border-slate-100',
    valueColor: 'text-teal-600',
    iconBg: 'bg-teal-100',
    iconColor: 'text-teal-600',
  },
  {
    key: 'totalUsers',
    label: 'Total Pengguna',
    icon: '👥',
    bg: 'bg-white',
    border: 'border-slate-100',
    valueColor: 'text-slate-700',
    iconBg: 'bg-slate-100',
    iconColor: 'text-slate-600',
  },
]

export default function Dashboard() {
  const outletContext = useOutletContext() ?? {}
  const contextSearch = outletContext?.searchQuery ?? ''
  const [searchQuery, setSearchQuery] = useState('')
  const searchQueryEffective = ((contextSearch || searchQuery) || '').trim().toLowerCase()
  const [stats, setStats] = useState({
    ordersToday: 0,
    driversActive: 0,
    ordersCompleted: 0,
    ordersPending: 0,
    totalUsers: 0,
  })
  const [trends, setTrends] = useState({
    ordersToday: [],
    driversActive: [],
    ordersCompleted: [],
    ordersPending: [],
    totalUsers: [],
  })
  const [trendPct, setTrendPct] = useState({})
  const [recentOrders, setRecentOrders] = useState([])
  const [loading, setLoading] = useState(true)
  /** Peringatan jika hybrid API gagal (bukan sekadar 0 driver). */
  const [hybridApiWarning, setHybridApiWarning] = useState(null)

  const loadingRef = useRef(false)

  useEffect(() => {
    let cancelled = false
    async function load() {
      if (loadingRef.current) return
      loadingRef.current = true
      try {
        const today = new Date()
        today.setHours(0, 0, 0, 0)
        const todayMs = today.getTime()
        const yesterday = new Date(today)
        yesterday.setDate(yesterday.getDate() - 1)
        const yesterdayMs = yesterday.getTime()

        let statusSnap
        if (isApiEnabled) {
          const apiDrivers = await getDriverStatusList()
          statusSnap = { docs: apiDrivers.map((d) => ({ id: d.uid || d.id, data: () => d })) }
        } else {
          statusSnap = await getDocs(collection(db, 'driver_status'))
        }

        if (cancelled) return
        const [ordersSnap, usersSnap] = await Promise.all([
          getDocs(collection(db, 'orders')),
          getDocs(collection(db, 'users')),
        ])

        if (cancelled) return
        let todayCount = 0
        let yesterdayCount = 0
        let completedCount = 0
        let pendingCount = 0
        const recent = []
        const ordersByDay = [0, 0, 0, 0, 0, 0, 0]

        ordersSnap.docs.forEach((docSnap) => {
          const d = docSnap.data()
          const createdAt = d.createdAt?.toDate?.()
          const status = d.status || ''
          if (createdAt) {
            const dDate = new Date(createdAt)
            dDate.setHours(0, 0, 0, 0)
            const dMs = dDate.getTime()
            if (dMs === todayMs) todayCount++
            if (dMs === yesterdayMs) yesterdayCount++
            const dayIdx = (todayMs - dMs) / (24 * 60 * 60 * 1000)
            if (dayIdx >= 0 && dayIdx < 7) ordersByDay[6 - Math.floor(dayIdx)]++
          }
          if (status === 'completed') completedCount++
          if (['pending_agreement', 'agreed', 'picked_up'].includes(status)) pendingCount++
          recent.push({ id: docSnap.id, ...d })
        })

        recent.sort((a, b) => {
          const at = a.createdAt?.toDate?.() || new Date(0)
          const bt = b.createdAt?.toDate?.() || new Date(0)
          return bt - at
        })

        let activeDrivers = 0
        statusSnap.docs.forEach((d) => {
          const data = typeof d.data === 'function' ? d.data() : d
          if (data?.status === 'siap_kerja') activeDrivers++
        })

        const totalUsers = usersSnap.docs.filter((d) => d.data()?.role !== 'admin').length

        const ordersTodayPct = yesterdayCount > 0
          ? ((todayCount - yesterdayCount) / yesterdayCount * 100).toFixed(1)
          : todayCount > 0 ? 100 : 0

        if (!cancelled) {
          setStats({
            ordersToday: todayCount,
            driversActive: activeDrivers,
            ordersCompleted: completedCount,
            ordersPending: pendingCount,
            totalUsers,
          })
          setTrends({
            ordersToday: ordersByDay,
            driversActive: [0, 0, 0, 0, 0, 0, activeDrivers],
            ordersCompleted: [0, 0, 0, 0, 0, 0, completedCount],
            ordersPending: [0, 0, 0, 0, 0, 0, pendingCount],
            totalUsers: [0, 0, 0, 0, 0, 0, totalUsers],
          })
          setTrendPct({
            ordersToday: parseFloat(ordersTodayPct),
          })
          setRecentOrders(recent.slice(0, 8))
        }
      } catch (err) {
        if (!cancelled) console.error(err)
      } finally {
        loadingRef.current = false
        if (!cancelled) setLoading(false)
      }
    }
    load()
    return () => { cancelled = true }
  }, [])

  if (loading) {
    return (
      <div className="flex flex-col items-center justify-center py-24">
        <div className="h-14 w-14 animate-spin rounded-full border-4 border-orange-500 border-t-transparent" />
        <p className="mt-4 text-sm text-slate-500">Memuat dashboard...</p>
      </div>
    )
  }

  const displayedOrders = searchQueryEffective
    ? recentOrders.filter((o) => {
        const orderNum = (o.orderNumber || o.id || '').toString().toLowerCase()
        const passenger = (o.passengerName || '').toLowerCase()
        const status = (o.status || '').toLowerCase()
        return orderNum.includes(searchQueryEffective) || passenger.includes(searchQueryEffective) || status.includes(searchQueryEffective)
      })
    : recentOrders

  return (
    <div className="space-y-8">
      {hybridApiWarning && (
        <div
          role="alert"
          className="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900"
        >
          <strong className="font-semibold">API hybrid: </strong>
          {hybridApiWarning}
        </div>
      )}
      {/* Stat cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-5">
        {CARD_CONFIG.map((card) => {
          const value = stats[card.key]
          const trendData = trends[card.key] || []
          const pct = card.key === 'ordersToday' ? trendPct.ordersToday : null
          return (
            <div
              key={card.key}
              className={`rounded-2xl border shadow-card hover:shadow-card-hover transition-all duration-300 p-6 ${card.bg} ${card.border}`}
            >
              <div className="flex items-start justify-between">
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-slate-500">{card.label}</p>
                  <p className={`text-2xl font-bold mt-1 ${card.valueColor}`}>{value}</p>
                  {pct != null && (
                    <div className="flex items-center gap-1 mt-2">
                      <MiniSparkline data={trendData} positive={pct >= 0} />
                      <span className={`text-xs font-medium ${pct >= 0 ? 'text-emerald-600' : 'text-red-600'}`}>
                        {pct >= 0 ? '+' : ''}{pct}%
                      </span>
                      <span className="text-xs text-slate-400">vs kemarin</span>
                    </div>
                  )}
                </div>
                <div className={`w-12 h-12 rounded-xl flex items-center justify-center text-2xl ${card.iconBg} ${card.iconColor}`}>
                  {card.icon}
                </div>
              </div>
            </div>
          )
        })}
      </div>

      {/* Recent orders table */}
      <div className="bg-white rounded-2xl shadow-card border border-slate-100 overflow-hidden">
        <div className="px-6 py-5 border-b border-slate-100 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <h3 className="font-bold text-slate-800 text-lg">Pesanan Terbaru</h3>
          <div className="flex gap-2">
            <input
              type="text"
              placeholder="Cari no. pesanan, penumpang, status..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="px-4 py-2.5 border border-slate-200 rounded-xl text-sm focus:ring-2 focus:ring-orange-500/30 focus:border-orange-500 w-full sm:w-72 bg-slate-50 focus:bg-white transition"
            />
            <button
              onClick={() => window.location.reload()}
              className="px-4 py-2.5 border border-slate-200 rounded-xl text-sm font-medium text-slate-600 hover:bg-slate-50 transition"
              title="Muat ulang data"
            >
              🔄
            </button>
          </div>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[500px]">
            <thead className="bg-slate-50">
              <tr>
                <th className="px-6 py-4 text-left text-xs font-semibold text-slate-500 uppercase tracking-wider">No. Pesanan</th>
                <th className="px-6 py-4 text-left text-xs font-semibold text-slate-500 uppercase tracking-wider">Penumpang</th>
                <th className="px-6 py-4 text-left text-xs font-semibold text-slate-500 uppercase tracking-wider">Status</th>
                <th className="px-6 py-4 text-left text-xs font-semibold text-slate-500 uppercase tracking-wider">Tanggal</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {(Array.isArray(displayedOrders) ? displayedOrders : []).map((o) => (
                <tr key={o?.id || Math.random()} className="hover:bg-slate-50/50 transition">
                  <td className="px-6 py-4 text-sm font-semibold text-slate-800">{o?.orderNumber || (o?.id ? String(o.id).slice(0, 8) : '-')}</td>
                  <td className="px-6 py-4 text-sm text-slate-600">{o.passengerName || '-'}</td>
                  <td className="px-6 py-4">
                    <span
                      className={`inline-flex px-3 py-1 text-xs font-medium rounded-full ${
                        o.status === 'completed'
                          ? 'bg-emerald-100 text-emerald-800'
                          : o.status === 'cancelled' || o.adminCancelled || o.driverCancelled || o.passengerCancelled
                          ? 'bg-red-100 text-red-800'
                          : 'bg-amber-100 text-amber-800'
                      }`}
                    >
                      {o.status || '-'}
                    </span>
                  </td>
                  <td className="px-6 py-4 text-sm text-slate-500">
                    {o.createdAt?.toDate?.()?.toLocaleDateString('id-ID') || '-'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {displayedOrders.length === 0 && (
          <p className="px-6 py-16 text-center text-slate-500">
            {searchQuery.trim() ? 'Tidak ada hasil pencarian' : 'Belum ada pesanan'}
          </p>
        )}
      </div>
    </div>
  )
}
