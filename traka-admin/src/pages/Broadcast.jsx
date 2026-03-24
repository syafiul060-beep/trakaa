import { useState } from 'react'
import { getFunctions, httpsCallable } from 'firebase/functions'
import app from '../firebase'
import { logAudit } from '../utils/auditLog'

export default function Broadcast() {
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [sending, setSending] = useState(false)
  const [message, setMessage] = useState('')

  const handleSend = async () => {
    const t = title.trim() || 'Traka'
    const b = body.trim()
    if (!b) {
      setMessage('Isi pesan wajib.')
      return
    }
    setSending(true)
    setMessage('')
    try {
      const functions = getFunctions(app)
      const broadcast = httpsCallable(functions, 'broadcastNotification')
      await broadcast({ title: t, body: b })
      await logAudit('broadcast', { title: t, bodyLength: b.length })
      setMessage('Notifikasi berhasil dikirim ke semua pengguna.')
      setBody('')
    } catch (err) {
      setMessage('Gagal: ' + (err.message || err.code || 'Kesalahan tidak diketahui'))
    } finally {
      setSending(false)
    }
  }

  return (
    <div className="max-w-xl space-y-6">
      <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="px-6 py-4 border-b border-gray-100">
          <h3 className="font-semibold text-gray-800">Siaran notifikasi</h3>
          <p className="text-sm text-gray-500 mt-0.5">
            Kirim push notification ke semua pengguna yang sudah login (penumpang & driver).
          </p>
        </div>
        <div className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1.5">Judul</label>
            <input
              type="text"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Traka"
              className="w-full px-4 py-2.5 border border-gray-200 rounded-lg focus:ring-2 focus:ring-orange-500/30 focus:border-orange-500"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1.5">Pesan *</label>
            <textarea
              value={body}
              onChange={(e) => setBody(e.target.value)}
              placeholder="Tulis pesan pengumuman..."
              rows={4}
              className="w-full px-4 py-2.5 border border-gray-200 rounded-lg focus:ring-2 focus:ring-orange-500/30 focus:border-orange-500"
            />
          </div>
          <button
            onClick={handleSend}
            disabled={sending || !body.trim()}
            className="px-6 py-3 bg-orange-500 text-white rounded-xl font-semibold hover:bg-orange-600 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {sending ? 'Mengirim...' : 'Kirim ke Semua'}
          </button>
          {message && (
            <p className={`text-sm font-medium ${message.includes('Gagal') ? 'text-red-600' : 'text-green-600'}`}>
              {message}
            </p>
          )}
        </div>
      </div>
    </div>
  )
}
