import { useState, useEffect } from 'react'
import {
  collection,
  getDocs,
  doc,
  getDoc,
  query,
  where,
  orderBy,
  limit,
  addDoc,
  serverTimestamp,
} from 'firebase/firestore'
import { db } from '../firebase'
import {
  extractProvinceFromAddress,
  getTierFromProvinces,
  getLacakBarangFeeForTier,
} from '../utils/geocoding'
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  BarChart,
  Bar,
  Legend,
} from 'recharts'

const COLLECTION_FEEDBACK = 'app_feedback'

function formatRupiah(n) {
  return new Intl.NumberFormat('id-ID', {
    style: 'currency',
    currency: 'IDR',
    minimumFractionDigits: 0,
  }).format(n)
}

function getDateKey(d) {
  if (!d) return ''
  const dt = d.toDate ? d.toDate() : new Date(d)
  return dt.toISOString().slice(0, 10)
}

export default function Reports() {
  const [loading, setLoading] = useState(true)
  const [settings, setSettings] = useState(null)
  const [feeSummary, setFeeSummary] = useState({
    lacakDriver: { total: 0, count: 0 },
    lacakBarang: { total: 0, count: 0 },
    violation: { total: 0, count: 0 },
  })
  const [chartData, setChartData] = useState([])
  const [userGrowthData, setUserGrowthData] = useState([])
  const [feedbackList, setFeedbackList] = useState([])
  const [newFeedback, setNewFeedback] = useState('')
  const [feedbackType, setFeedbackType] = useState('saran')
  const [savingFeedback, setSavingFeedback] = useState(false)
  const [dateRange, setDateRange] = useState(14)

  useEffect(() => {
    loadAll()
  }, [dateRange])

  async function loadAll() {
    setLoading(true)
    try {
      const settingsSnap = await getDoc(doc(db, 'app_config', 'settings'))
      const s = settingsSnap.exists() ? settingsSnap.data() : {}
      setSettings(s)

      const lacakDriverFee = s.lacakDriverFeeRupiah ?? 3000
      const violationFee = s.violationFeeRupiah ?? 5000
      const lacakBarang1 = s.lacakBarangDalamProvinsiRupiah ?? 10000
      const lacakBarang2 = s.lacakBarangBedaProvinsiRupiah ?? 15000
      const lacakBarang3 = s.lacakBarangLebihDari1ProvinsiRupiah ?? 25000

      const cutoff = new Date()
      cutoff.setDate(cutoff.getDate() - dateRange)
      cutoff.setHours(0, 0, 0, 0)

      const [ordersSnap, violationSnap, usersSnap, feedbackSnap] = await Promise.all([
        getDocs(collection(db, 'orders')),
        getDocs(collection(db, 'violation_records')),
        getDocs(collection(db, 'users')),
        getDocs(collection(db, COLLECTION_FEEDBACK)).catch(() => ({ docs: [] })),
      ])

      let lacakDriverTotal = 0
      let lacakDriverCount = 0
      let lacakBarangTotal = 0
      let lacakBarangCount = 0
      const feeByDate = {}
      const usersByDate = {}
      const ordersByDate = {}

      for (const docSnap of ordersSnap.docs) {
        const d = docSnap.data()
        const createdAt = d.createdAt?.toDate?.()
        if (createdAt && createdAt >= cutoff) {
          const key = getDateKey(d.createdAt)
          ordersByDate[key] = (ordersByDate[key] || 0) + 1
        }

        if (d.passengerTrackDriverPaidAt) {
          lacakDriverCount++
          lacakDriverTotal += lacakDriverFee
          const key = getDateKey(d.passengerTrackDriverPaidAt)
          if (!feeByDate[key]) feeByDate[key] = { lacakDriver: 0, lacakBarang: 0, violation: 0 }
          feeByDate[key].lacakDriver = (feeByDate[key].lacakDriver || 0) + lacakDriverFee
        }

        if (d.orderType === 'kirim_barang') {
          const originProv = extractProvinceFromAddress(d.originText || '')
          const destProv = extractProvinceFromAddress(d.receiverLocationText || d.destText || '')
          const tier = getTierFromProvinces(originProv, destProv)
          const fee = getLacakBarangFeeForTier(tier, lacakBarang1, lacakBarang2, lacakBarang3)
          if (d.passengerLacakBarangPaidAt) {
            lacakBarangCount++
            lacakBarangTotal += fee
            const key = getDateKey(d.passengerLacakBarangPaidAt)
            if (!feeByDate[key]) feeByDate[key] = { lacakDriver: 0, lacakBarang: 0, violation: 0 }
            feeByDate[key].lacakBarang = (feeByDate[key].lacakBarang || 0) + fee
          }
          if (d.receiverLacakBarangPaidAt) {
            lacakBarangCount++
            lacakBarangTotal += fee
            const key = getDateKey(d.receiverLacakBarangPaidAt)
            if (!feeByDate[key]) feeByDate[key] = { lacakDriver: 0, lacakBarang: 0, violation: 0 }
            feeByDate[key].lacakBarang = (feeByDate[key].lacakBarang || 0) + fee
          }
        }
      }

      let violationTotal = 0
      let violationCount = 0
      violationSnap.docs.forEach((docSnap) => {
        const d = docSnap.data()
        if (d.paidAt) {
          const amount = d.amount ?? violationFee
          violationCount++
          violationTotal += amount
          const key = getDateKey(d.paidAt)
          if (!feeByDate[key]) feeByDate[key] = { lacakDriver: 0, lacakBarang: 0, violation: 0 }
          feeByDate[key].violation = (feeByDate[key].violation || 0) + amount
        }
      })

      usersSnap.docs.forEach((docSnap) => {
        const d = docSnap.data()
        if (d.role === 'admin') return
        const createdAt = d.createdAt?.toDate?.()
        if (createdAt && createdAt >= cutoff) {
          const key = getDateKey(d.createdAt)
          usersByDate[key] = (usersByDate[key] || 0) + 1
        }
      })

      setFeeSummary({
        lacakDriver: { total: lacakDriverTotal, count: lacakDriverCount },
        lacakBarang: { total: lacakBarangTotal, count: lacakBarangCount },
        violation: { total: violationTotal, count: violationCount },
      })

      const dates = []
      for (let i = dateRange - 1; i >= 0; i--) {
        const d = new Date()
        d.setDate(d.getDate() - i)
        d.setHours(0, 0, 0, 0)
        const key = d.toISOString().slice(0, 10)
        const fd = feeByDate[key] || { lacakDriver: 0, lacakBarang: 0, violation: 0 }
        dates.push({
          date: key.slice(5),
          lacakDriver: fd.lacakDriver,
          lacakBarang: fd.lacakBarang,
          violation: fd.violation,
          total: fd.lacakDriver + fd.lacakBarang + fd.violation,
          users: usersByDate[key] || 0,
          orders: ordersByDate[key] || 0,
        })
      }
      setChartData(dates)

      const feedbacks = (feedbackSnap.docs?.map((d) => ({ id: d.id, ...d.data() })) || [])
        .sort((a, b) => {
          const at = a.createdAt?.toDate?.()?.getTime() ?? 0
          const bt = b.createdAt?.toDate?.()?.getTime() ?? 0
          return bt - at
        })
        .slice(0, 50)
      setFeedbackList(feedbacks)
    } catch (err) {
      console.error('Reports load error:', err)
    } finally {
      setLoading(false)
    }
  }

  const handleAddFeedback = async () => {
    const text = newFeedback.trim()
    if (!text) return
    setSavingFeedback(true)
    try {
      await addDoc(collection(db, COLLECTION_FEEDBACK), {
        text,
        type: feedbackType,
        source: 'admin',
        createdAt: serverTimestamp(),
      })
      setNewFeedback('')
      loadAll()
    } catch (err) {
      alert('Gagal: ' + err.message)
    } finally {
      setSavingFeedback(false)
    }
  }

  const totalFee =
    feeSummary.lacakDriver.total + feeSummary.lacakBarang.total + feeSummary.violation.total

  if (loading) {
    return (
      <div className="flex flex-col items-center justify-center py-16">
        <div className="h-12 w-12 animate-spin rounded-full border-4 border-orange-500 border-t-transparent" />
        <p className="mt-4 text-sm text-gray-500">Memuat laporan...</p>
      </div>
    )
  }

  return (
    <div className="space-y-8">
      {/* Rentang tanggal */}
      <div className="flex items-center gap-4">
        <span className="text-sm font-medium text-gray-600">Rentang:</span>
        <select
          value={dateRange}
          onChange={(e) => setDateRange(Number(e.target.value))}
          className="px-3 py-2 border border-gray-200 rounded-lg text-sm focus:ring-2 focus:ring-orange-500/30"
        >
          <option value={7}>7 hari</option>
          <option value={14}>14 hari</option>
          <option value={30}>30 hari</option>
        </select>
      </div>

      {/* Ringkasan biaya */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-5">
        <div className="bg-gradient-to-br from-emerald-50 to-emerald-100/50 rounded-2xl border border-emerald-100 p-6 shadow-card hover:shadow-card-hover transition-shadow">
          <p className="text-sm font-medium text-emerald-700">Total biaya aplikasi</p>
          <p className="text-2xl font-bold text-emerald-800 mt-1">{formatRupiah(totalFee)}</p>
          <p className="text-xs text-emerald-600 mt-1">
            Lacak Driver + Lacak Barang + Pelanggaran
          </p>
        </div>
        <div className="bg-white rounded-xl border border-gray-100 p-6">
          <p className="text-sm font-medium text-gray-600">Lacak Driver</p>
          <p className="text-xl font-bold text-gray-800 mt-1">
            {formatRupiah(feeSummary.lacakDriver.total)}
          </p>
          <p className="text-xs text-gray-500 mt-1">{feeSummary.lacakDriver.count} transaksi</p>
        </div>
        <div className="bg-white rounded-xl border border-gray-100 p-6">
          <p className="text-sm font-medium text-gray-600">Lacak Barang</p>
          <p className="text-xl font-bold text-gray-800 mt-1">
            {formatRupiah(feeSummary.lacakBarang.total)}
          </p>
          <p className="text-xs text-gray-500 mt-1">{feeSummary.lacakBarang.count} transaksi</p>
        </div>
        <div className="bg-white rounded-xl border border-gray-100 p-6">
          <p className="text-sm font-medium text-gray-600">Pelanggaran</p>
          <p className="text-xl font-bold text-gray-800 mt-1">
            {formatRupiah(feeSummary.violation.total)}
          </p>
          <p className="text-xs text-gray-500 mt-1">{feeSummary.violation.count} transaksi</p>
        </div>
      </div>

      {/* Grafik biaya per hari */}
      <div className="bg-white rounded-2xl shadow-card border border-slate-100 overflow-hidden">
        <div className="px-6 py-5 border-b border-slate-100">
          <h3 className="font-semibold text-gray-800">Biaya aplikasi per hari</h3>
          <p className="text-sm text-gray-500 mt-0.5">Lacak Driver, Lacak Barang, Pelanggaran</p>
        </div>
        <div className="p-6">
          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                <XAxis dataKey="date" tick={{ fontSize: 11 }} />
                <YAxis tick={{ fontSize: 11 }} tickFormatter={(v) => (v >= 1000 ? `${v / 1000}k` : v)} />
                <Tooltip
                  formatter={(value) => formatRupiah(value)}
                  labelFormatter={(label) => `Tanggal: ${label}`}
                />
                <Legend />
                <Area
                  type="monotone"
                  dataKey="lacakDriver"
                  name="Lacak Driver"
                  stackId="1"
                  stroke="#10b981"
                  fill="#10b981"
                  fillOpacity={0.6}
                />
                <Area
                  type="monotone"
                  dataKey="lacakBarang"
                  name="Lacak Barang"
                  stackId="1"
                  stroke="#f59e0b"
                  fill="#f59e0b"
                  fillOpacity={0.6}
                />
                <Area
                  type="monotone"
                  dataKey="violation"
                  name="Pelanggaran"
                  stackId="1"
                  stroke="#ef4444"
                  fill="#ef4444"
                  fillOpacity={0.6}
                />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </div>
      </div>

      {/* Grafik Perkembangan */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
          <div className="px-6 py-4 border-b border-gray-100">
            <h3 className="font-semibold text-gray-800">Pengguna Baru per Hari</h3>
          </div>
          <div className="p-6">
            <div className="h-48">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                  <XAxis dataKey="date" tick={{ fontSize: 10 }} />
                  <YAxis tick={{ fontSize: 11 }} />
                  <Tooltip />
                  <Bar dataKey="users" name="Pengguna Baru" fill="#3b82f6" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </div>
          </div>
        </div>
        <div className="bg-white rounded-2xl shadow-card border border-slate-100 overflow-hidden">
          <div className="px-6 py-5 border-b border-slate-100">
            <h3 className="font-bold text-slate-800">Pesanan per Hari</h3>
          </div>
          <div className="p-6">
            <div className="h-48">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                  <XAxis dataKey="date" tick={{ fontSize: 10 }} />
                  <YAxis tick={{ fontSize: 11 }} />
                  <Tooltip />
                  <Bar dataKey="orders" name="Pesanan" fill="#8b5cf6" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </div>
          </div>
        </div>
      </div>

      {/* Saran & Masukan */}
      <div className="bg-white rounded-2xl shadow-card border border-slate-100 overflow-hidden">
        <div className="px-6 py-5 border-b border-slate-100">
          <h3 className="font-semibold text-gray-800">Saran & Masukan</h3>
          <p className="text-sm text-gray-500 mt-0.5">
            Masukan dari pengguna. Tambah fitur di app untuk mengumpulkan saran otomatis, atau catat manual di sini.
          </p>
        </div>
        <div className="p-6 space-y-4">
          <div className="flex gap-2">
            <select
              value={feedbackType}
              onChange={(e) => setFeedbackType(e.target.value)}
              className="px-3 py-2 border border-gray-200 rounded-lg text-sm"
            >
              <option value="saran">Saran</option>
              <option value="masukan">Masukan</option>
              <option value="keluhan">Keluhan</option>
            </select>
            <input
              type="text"
              value={newFeedback}
              onChange={(e) => setNewFeedback(e.target.value)}
              placeholder="Tambah saran/masukan (catat dari chat/email)..."
              className="flex-1 px-4 py-2 border border-gray-200 rounded-lg focus:ring-2 focus:ring-orange-500/30"
              onKeyDown={(e) => e.key === 'Enter' && handleAddFeedback()}
            />
            <button
              onClick={handleAddFeedback}
              disabled={savingFeedback || !newFeedback.trim()}
              className="px-4 py-2 bg-orange-500 text-white rounded-lg hover:bg-orange-600 disabled:opacity-50 font-medium"
            >
              {savingFeedback ? '...' : 'Tambah'}
            </button>
          </div>
          <div className="space-y-2 max-h-64 overflow-y-auto">
            {feedbackList.length === 0 ? (
              <p className="text-sm text-gray-500 py-4 text-center">
                Belum ada saran atau masukan. Catat manual di atas saat user menghubungi via chat/email.
              </p>
            ) : (
              feedbackList.map((f) => (
                <div
                  key={f.id}
                  className="flex gap-3 p-3 bg-gray-50 rounded-lg text-sm"
                >
                  <span
                    className={`shrink-0 px-2 py-0.5 rounded text-xs font-medium ${
                      f.type === 'keluhan' ? 'bg-red-100 text-red-700' : 'bg-blue-100 text-blue-700'
                    }`}
                  >
                    {f.type || 'saran'}
                  </span>
                  <p className="flex-1 text-gray-700">{f.text}</p>
                  <span className="text-xs text-gray-400 shrink-0">
                    {f.createdAt?.toDate?.()?.toLocaleDateString('id-ID') || '-'}
                  </span>
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
