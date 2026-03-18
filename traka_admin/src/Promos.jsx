import { useState, useEffect } from 'react'
import {
  collection,
  doc,
  getDocs,
  addDoc,
  updateDoc,
  deleteDoc,
  query,
  orderBy,
  serverTimestamp,
  Timestamp
} from 'firebase/firestore'
import { db } from './firebase'

const COLLECTION = 'promotions'

function formatDate(d) {
  if (!d) return ''
  const t = d?.toDate?.() || d
  return t instanceof Date ? t.toISOString().slice(0, 16) : ''
}

function parseDateStr(s) {
  if (!s || !s.trim()) return null
  const d = new Date(s)
  return isNaN(d.getTime()) ? null : Timestamp.fromDate(d)
}

export default function Promos() {
  const [promos, setPromos] = useState([])
  const [loading, setLoading] = useState(true)
  const [message, setMessage] = useState(null)
  const [editing, setEditing] = useState(null)
  const [form, setForm] = useState({
    title: '',
    content: '',
    imageUrl: '',
    target: 'both',
    type: 'article',
    priority: 0,
    publishedAt: '',
    expiresAt: ''
  })

  async function loadPromos() {
    setLoading(true)
    try {
      const q = query(
        collection(db, COLLECTION),
        orderBy('priority', 'desc'),
        orderBy('publishedAt', 'desc')
      )
      const snap = await getDocs(q)
      setPromos(snap.docs.map(d => ({ id: d.id, ...d.data() })))
    } catch (e) {
      console.error(e)
      setMessage({ type: 'error', text: 'Gagal memuat promosi' })
    }
    setLoading(false)
  }

  useEffect(() => {
    loadPromos()
  }, [])

  function resetForm() {
    setEditing(null)
    setForm({
      title: '',
      content: '',
      imageUrl: '',
      target: 'both',
      type: 'article',
      priority: 0,
      publishedAt: '',
      expiresAt: ''
    })
  }

  function openEdit(p) {
    setEditing(p.id)
    setForm({
      title: p.title || '',
      content: p.content || '',
      imageUrl: p.imageUrl || '',
      target: p.target || 'both',
      type: p.type || 'article',
      priority: p.priority ?? 0,
      publishedAt: formatDate(p.publishedAt),
      expiresAt: formatDate(p.expiresAt)
    })
  }

  async function handleSubmit(e) {
    e.preventDefault()
    setMessage(null)
    const payload = {
      title: form.title.trim(),
      content: form.content.trim(),
      imageUrl: form.imageUrl.trim() || null,
      target: form.target,
      type: form.type,
      priority: Number(form.priority) || 0,
      publishedAt: parseDateStr(form.publishedAt) || serverTimestamp(),
      expiresAt: parseDateStr(form.expiresAt) || null,
      updatedAt: serverTimestamp()
    }
    try {
      if (editing) {
        await updateDoc(doc(db, COLLECTION, editing), payload)
        setMessage({ type: 'success', text: 'Promosi berhasil diperbarui' })
      } else {
        await addDoc(collection(db, COLLECTION), {
          ...payload,
          createdAt: serverTimestamp()
        })
        setMessage({ type: 'success', text: 'Promosi berhasil ditambahkan' })
      }
      resetForm()
      loadPromos()
    } catch (e) {
      console.error(e)
      setMessage({ type: 'error', text: e.message || 'Gagal menyimpan' })
    }
  }

  async function handleDelete(id) {
    if (!confirm('Hapus promosi ini?')) return
    setMessage(null)
    try {
      await deleteDoc(doc(db, COLLECTION, id))
      setMessage({ type: 'success', text: 'Promosi dihapus' })
      resetForm()
      loadPromos()
    } catch (e) {
      console.error(e)
      setMessage({ type: 'error', text: e.message || 'Gagal menghapus' })
    }
  }

  return (
    <div className="container" style={{ paddingTop: 16 }}>
      <h2 style={{ marginBottom: 16 }}>Promosi & Info</h2>
      {message && (
        <div className={`alert alert-${message.type}`} style={{ marginBottom: 12 }}>
          {message.text}
        </div>
      )}

      <form onSubmit={handleSubmit} style={{ marginBottom: 24, maxWidth: 500 }}>
        <h3 style={{ marginBottom: 12 }}>{editing ? 'Edit Promosi' : 'Tambah Promosi'}</h3>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <div>
            <label>Judul</label>
            <input
              type="text"
              value={form.title}
              onChange={e => setForm(f => ({ ...f, title: e.target.value }))}
              required
              placeholder="Judul promosi"
            />
          </div>
          <div>
            <label>Isi (bisa HTML)</label>
            <textarea
              value={form.content}
              onChange={e => setForm(f => ({ ...f, content: e.target.value }))}
              rows={4}
              placeholder="Konten promosi"
            />
          </div>
          <div>
            <label>URL Gambar (opsional)</label>
            <input
              type="url"
              value={form.imageUrl}
              onChange={e => setForm(f => ({ ...f, imageUrl: e.target.value }))}
              placeholder="https://..."
            />
          </div>
          <div style={{ display: 'flex', gap: 16, flexWrap: 'wrap' }}>
            <div>
              <label>Target</label>
              <select
                value={form.target}
                onChange={e => setForm(f => ({ ...f, target: e.target.value }))}
              >
                <option value="penumpang">Penumpang</option>
                <option value="driver">Driver</option>
                <option value="both">Keduanya</option>
              </select>
            </div>
            <div>
              <label>Tipe</label>
              <select
                value={form.type}
                onChange={e => setForm(f => ({ ...f, type: e.target.value }))}
              >
                <option value="article">Artikel</option>
                <option value="banner">Banner</option>
              </select>
            </div>
            <div>
              <label>Prioritas (lebih tinggi = lebih atas)</label>
              <input
                type="number"
                value={form.priority}
                onChange={e => setForm(f => ({ ...f, priority: e.target.value }))}
                min={0}
              />
            </div>
          </div>
          <div style={{ display: 'flex', gap: 16, flexWrap: 'wrap' }}>
            <div>
              <label>Terbit (YYYY-MM-DD HH:mm)</label>
              <input
                type="datetime-local"
                value={form.publishedAt}
                onChange={e => setForm(f => ({ ...f, publishedAt: e.target.value }))}
              />
            </div>
            <div>
              <label>Kadaluarsa (YYYY-MM-DD HH:mm)</label>
              <input
                type="datetime-local"
                value={form.expiresAt}
                onChange={e => setForm(f => ({ ...f, expiresAt: e.target.value }))}
              />
            </div>
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            <button type="submit" className="btn btn-primary">
              {editing ? 'Simpan' : 'Tambah'}
            </button>
            {editing && (
              <button type="button" className="btn" onClick={resetForm}>
                Batal
              </button>
            )}
          </div>
        </div>
      </form>

      <h3 style={{ marginBottom: 12 }}>Daftar Promosi</h3>
      {loading ? (
        <p>Memuat...</p>
      ) : promos.length === 0 ? (
        <p>Tidak ada promosi.</p>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {promos.map(p => (
            <div
              key={p.id}
              style={{
                border: '1px solid #e2e8f0',
                borderRadius: 8,
                padding: 16,
                background: editing === p.id ? '#f0f9ff' : '#fff'
              }}
            >
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: 8 }}>
                <div>
                  <strong>{p.title || '(Tanpa judul)'}</strong>
                  <span style={{ marginLeft: 8, fontSize: 12, color: '#64748b' }}>
                    [{p.target}] {p.type} • prioritas {p.priority ?? 0}
                  </span>
                </div>
                <div style={{ display: 'flex', gap: 8 }}>
                  <button className="btn" style={{ padding: '4px 12px', fontSize: 13 }} onClick={() => openEdit(p)}>
                    Edit
                  </button>
                  <button className="btn" style={{ padding: '4px 12px', fontSize: 13, background: '#fef2f2', color: '#b91c1c' }} onClick={() => handleDelete(p.id)}>
                    Hapus
                  </button>
                </div>
              </div>
              {p.imageUrl && (
                <div style={{ marginTop: 8 }}>
                  <img src={p.imageUrl} alt="" style={{ maxWidth: 200, maxHeight: 100, objectFit: 'cover', borderRadius: 4 }} />
                </div>
              )}
              <p style={{ marginTop: 8, fontSize: 13, color: '#475569' }}>
                {(p.content || '').slice(0, 150)}{(p.content || '').length > 150 ? '...' : ''}
              </p>
              <div style={{ fontSize: 12, color: '#94a3b8', marginTop: 4 }}>
                Terbit: {formatDate(p.publishedAt) || '-'} • Kadaluarsa: {formatDate(p.expiresAt) || '-'}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
