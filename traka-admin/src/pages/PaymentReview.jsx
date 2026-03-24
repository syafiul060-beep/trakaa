import { useState, useEffect, useCallback } from 'react'
import {
  getPendingPaymentMethods,
  approvePaymentMethod,
  rejectPaymentMethod,
} from '../services/trakaApi'
import { apiBaseUrl, isApiEnabled } from '../config/apiConfig'

export default function PaymentReview() {
  const [methods, setMethods] = useState([])
  const [loading, setLoading] = useState(true)
  const [msg, setMsg] = useState(null)
  const [busyId, setBusyId] = useState(null)

  const load = useCallback(async () => {
    if (!isApiEnabled) {
      setMethods([])
      setLoading(false)
      return
    }
    setLoading(true)
    setMsg(null)
    const r = await getPendingPaymentMethods()
    if (r.status === 'ok') {
      setMethods(r.methods)
    } else {
      setMethods([])
      setMsg(
        r.status === 'disabled'
          ? 'Set VITE_TRAKA_API_BASE_URL dan VITE_TRAKA_USE_HYBRID=true untuk memakai API.'
          : 'Gagal memuat daftar. Cek jaringan / CORS / login.',
      )
    }
    setLoading(false)
  }, [])

  useEffect(() => {
    load()
  }, [load])

  const onApprove = async (id) => {
    setBusyId(id)
    setMsg(null)
    const r = await approvePaymentMethod(id, 'approved by admin')
    setBusyId(null)
    if (r.ok) await load()
    else setMsg(r.error || 'Gagal setujui')
  }

  const onReject = async (id) => {
    setBusyId(id)
    setMsg(null)
    const r = await rejectPaymentMethod(id, 'rejected by admin')
    setBusyId(null)
    if (r.ok) await load()
    else setMsg(r.error || 'Gagal tolak')
  }

  if (!isApiEnabled) {
    return (
      <div className="p-6 max-w-3xl">
        <h1 className="text-2xl font-bold text-slate-800 mb-2">Review instruksi bayar</h1>
        <p className="text-amber-800 bg-amber-50 border border-amber-200 rounded-lg p-4">
          Hybrid API belum diaktifkan di build admin. Set environment:{' '}
          <code className="text-sm">VITE_TRAKA_API_BASE_URL</code> dan{' '}
          <code className="text-sm">VITE_TRAKA_USE_HYBRID=true</code>
          (contoh: {apiBaseUrl || '—'}).
        </p>
      </div>
    )
  }

  return (
    <div className="p-6 max-w-4xl">
      <div className="flex items-center justify-between gap-4 mb-6">
        <h1 className="text-2xl font-bold text-slate-800">Review instruksi bayar</h1>
        <button
          type="button"
          onClick={() => load()}
          className="px-4 py-2 rounded-lg bg-slate-200 hover:bg-slate-300 text-slate-800 text-sm font-medium"
        >
          Muat ulang
        </button>
      </div>
      <p className="text-slate-600 text-sm mb-4">
        Driver dengan nama pemilik rekening berbeda dari profil masuk ke sini. Setujui setelah nama profil
        disamakan, atau tolak.
      </p>
      {msg && (
        <div className="mb-4 text-sm text-amber-900 bg-amber-50 border border-amber-200 rounded-lg px-4 py-3">
          {msg}
        </div>
      )}
      {loading ? (
        <p className="text-slate-500">Memuat…</p>
      ) : methods.length === 0 ? (
        <p className="text-slate-500">Tidak ada antrian pending_review.</p>
      ) : (
        <ul className="space-y-4">
          {methods.map((m) => (
            <li
              key={m.id}
              className="border border-slate-200 rounded-xl p-4 bg-white shadow-sm"
            >
              <div className="font-mono text-xs text-slate-500 mb-1">{m.id}</div>
              <div className="font-semibold text-slate-800">
                Driver UID: {m.driverUid} · {m.type}
              </div>
              <div className="text-sm text-slate-700 mt-2 whitespace-pre-wrap">
                {m.type === 'qris'
                  ? m.qrisImageUrl
                  : `${m.bankName || m.ewalletProvider || ''} · ${m.accountNumber || ''}`}
                {'\n'}a.n. {m.accountHolderName}
              </div>
              <div className="flex gap-2 mt-4">
                <button
                  type="button"
                  disabled={busyId === m.id}
                  onClick={() => onApprove(m.id)}
                  className="px-4 py-2 rounded-lg bg-green-600 text-white text-sm font-medium hover:bg-green-700 disabled:opacity-50"
                >
                  Setujui
                </button>
                <button
                  type="button"
                  disabled={busyId === m.id}
                  onClick={() => onReject(m.id)}
                  className="px-4 py-2 rounded-lg bg-red-600 text-white text-sm font-medium hover:bg-red-700 disabled:opacity-50"
                >
                  Tolak
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
