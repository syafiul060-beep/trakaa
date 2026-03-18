import { useParams, Link } from 'react-router-dom'
import { useState, useEffect } from 'react'
import { doc, getDoc } from 'firebase/firestore'
import { db } from '../firebase'

export default function OrderDetail() {
  const { id } = useParams()
  const [order, setOrder] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => {
    if (!id) return
    let cancelled = false
    setLoading(true)
    setError(null)
    getDoc(doc(db, 'orders', id))
      .then((snap) => {
        if (cancelled) return
        if (snap.exists()) setOrder({ id: snap.id, ...snap.data() })
        else setOrder(null)
      })
      .catch((err) => {
        if (!cancelled) {
          setError(err?.message || 'Gagal memuat pesanan')
          setOrder(null)
        }
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => { cancelled = true }
  }, [id])

  if (loading) {
    return (
      <div className="space-y-4">
        <div className="animate-pulse h-8 bg-gray-200 rounded w-48" />
        <div className="animate-pulse h-32 bg-gray-200 rounded" />
        <div className="animate-pulse h-24 bg-gray-200 rounded" />
      </div>
    )
  }
  if (error || !order) {
    return (
      <div className="bg-red-50 border border-red-200 rounded-xl p-6 text-center">
        <p className="text-red-700 font-medium">
          {error || 'Pesanan tidak ditemukan.'}
        </p>
        <Link to="/orders" className="inline-block mt-4 text-orange-600 hover:underline font-medium">
          ← Kembali ke Daftar Pesanan
        </Link>
      </div>
    )
  }

  const statusLabel = {
    pending_agreement: 'Pending',
    agreed: 'Agreed',
    picked_up: 'Di Jalan',
    completed: 'Selesai',
    cancelled: 'Dibatalkan',
  }

  return (
    <div className="space-y-6">
      <Link to="/orders" className="inline-flex items-center gap-1 py-2 px-3 -ml-3 rounded-lg text-traka-orange hover:bg-orange-50 transition">← Kembali</Link>

      <div className="bg-white rounded-lg shadow p-6 space-y-4">
        <div className="flex flex-col sm:flex-row sm:justify-between sm:items-start gap-2">
          <h2 className="text-lg font-semibold">Detail Pesanan {order.orderNumber || order.id}</h2>
          <span className={`px-3 py-1 rounded text-sm ${
            order.status === 'completed' ? 'bg-green-100 text-green-800' :
            order.status === 'cancelled' ? 'bg-red-100 text-red-800' :
            'bg-amber-100 text-amber-800'
          }`}>
            {statusLabel[order.status] || order.status}
          </span>
        </div>

        <div className="grid md:grid-cols-2 gap-6">
          <div>
            <h3 className="font-medium text-gray-700 mb-2">Penumpang</h3>
            <p>{order.passengerName || '-'}</p>
            <p className="text-sm text-gray-600">Dari: {order.originText}</p>
            <p className="text-sm text-gray-600">Ke: {order.destText}</p>
          </div>
          <div>
            <h3 className="font-medium text-gray-700 mb-2">Info</h3>
            <p className="text-sm">Tipe: {order.orderType === 'kirim_barang' ? 'Kirim Barang' : 'Travel'}</p>
            <p className="text-sm">Dibuat: {order.createdAt?.toDate?.()?.toLocaleString('id-ID') || '-'}</p>
            {order.completedAt && (
              <p className="text-sm">Selesai: {order.completedAt?.toDate?.()?.toLocaleString('id-ID')}</p>
            )}
            {order.tripDistanceKm != null && (
              <p className="text-sm">Jarak: {order.tripDistanceKm.toFixed(1)} km</p>
            )}
            {order.orderType === 'kirim_barang' ? (
              order.tripBarangFareRupiah != null && (
                <p className="text-sm">Kontribusi driver: Rp {Number(order.tripBarangFareRupiah).toLocaleString('id-ID')}</p>
              )
            ) : (
              order.tripFareRupiah != null && (
                <p className="text-sm">Kontribusi: Rp {order.tripFareRupiah.toLocaleString('id-ID')}</p>
              )
            )}
          </div>
        </div>

        {order.orderType === 'kirim_barang' && (
          <div className="border-t pt-4 mt-4">
            <h3 className="font-medium text-gray-700 mb-2">Detail Barang</h3>
            <p className="text-sm">
              Kategori: {order.barangCategory === 'dokumen' ? 'Dokumen' : order.barangCategory === 'kargo' ? 'Kargo' : 'Kargo (order lama)'}
            </p>
            {(order.barangCategory === 'kargo' || !order.barangCategory) && (order.barangNama || order.barangBeratKg || order.barangPanjangCm) && (
              <div className="text-sm text-gray-600 mt-1 space-y-0.5">
                {order.barangNama && <p>Nama: {order.barangNama}</p>}
                {order.barangBeratKg != null && order.barangBeratKg > 0 && (
                  <p>Berat: {order.barangBeratKg} kg</p>
                )}
                {(order.barangPanjangCm > 0 || order.barangLebarCm > 0 || order.barangTinggiCm > 0) && (
                  <p>
                    Dimensi: {[order.barangPanjangCm, order.barangLebarCm, order.barangTinggiCm]
                      .filter((v) => v != null && v > 0)
                      .join(' × ')} cm
                  </p>
                )}
              </div>
            )}
          </div>
        )}

        {order.orderType === 'kirim_barang' && order.receiverUid && (
          <div className="border-t pt-4 mt-4">
            <h3 className="font-medium text-gray-700 mb-2">Penerima</h3>
            <p className="text-sm">{order.receiverName || '-'}</p>
            {order.receiverLocationText && (
              <p className="text-sm text-gray-600">Lokasi: {order.receiverLocationText}</p>
            )}
            {order.receiverAgreedAt && (
              <p className="text-sm text-green-600">Setuju: {order.receiverAgreedAt?.toDate?.()?.toLocaleString('id-ID')}</p>
            )}
            {order.receiverScannedAt && (
              <p className="text-sm text-green-600">Diterima: {order.receiverScannedAt?.toDate?.()?.toLocaleString('id-ID')}</p>
            )}
          </div>
        )}
      </div>
    </div>
  )
}
