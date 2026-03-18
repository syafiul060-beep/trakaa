import { useState } from 'react'
import { signInWithEmailAndPassword } from 'firebase/auth'
import { auth } from './firebase'

export default function Login() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  const handleSubmit = async (e) => {
    e.preventDefault()
    setError('')
    setLoading(true)
    try {
      await signInWithEmailAndPassword(auth, email, password)
    } catch (err) {
      setError(err.message || 'Login gagal')
    }
    setLoading(false)
  }

  return (
    <div style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', background: '#0f172a' }}>
      <div className="card" style={{ width: '100%', maxWidth: 400 }}>
        <h1 style={{ marginBottom: 24, color: '#1e293b' }}>Traka Admin</h1>
        {error && <div className="alert alert-error">{error}</div>}
        <form onSubmit={handleSubmit}>
          <div style={{ marginBottom: 16 }}>
            <label style={{ display: 'block', marginBottom: 6, fontSize: 14, color: '#64748b' }}>Email</label>
            <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required style={{ width: '100%' }} />
          </div>
          <div style={{ marginBottom: 20 }}>
            <label style={{ display: 'block', marginBottom: 6, fontSize: 14, color: '#64748b' }}>Password</label>
            <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} required style={{ width: '100%' }} />
          </div>
          <button type="submit" className="btn btn-primary" disabled={loading} style={{ width: '100%' }}>
            {loading ? 'Memproses...' : 'Login'}
          </button>
        </form>
      </div>
    </div>
  )
}
