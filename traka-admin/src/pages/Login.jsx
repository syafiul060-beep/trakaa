import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { signInWithEmailAndPassword } from 'firebase/auth'
import { auth } from '../firebase'

export default function Login() {
  const navigate = useNavigate()
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
      navigate('/dashboard')
    } catch (err) {
      setError(err.code === 'auth/invalid-credential' ? 'Email atau password salah.' : err.message)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-50 via-white to-orange-50/30 flex items-center justify-center p-4">
      <div className="w-full max-w-md bg-white rounded-2xl shadow-xl border border-slate-100 p-8">
        <div className="flex justify-center mb-6">
          <div className="flex items-center gap-2">
            <div className="flex -space-x-1">
              <div className="w-4 h-4 rounded-md bg-orange-500" />
              <div className="w-4 h-4 rounded-md bg-teal-500" />
              <div className="w-4 h-4 rounded-md bg-orange-400" />
              <div className="w-4 h-4 rounded-md bg-teal-400" />
            </div>
            <span className="text-2xl font-bold text-slate-800">Traka</span>
          </div>
        </div>
        <h1 className="text-lg font-semibold text-center text-slate-600 mb-6">
          Panel Admin
        </h1>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Email</label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full px-4 py-2.5 border border-slate-200 rounded-xl focus:ring-2 focus:ring-orange-500/30 focus:border-orange-500 transition"
              placeholder="admin@traka.id"
              required
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Password</label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full px-4 py-2.5 border border-slate-200 rounded-xl focus:ring-2 focus:ring-orange-500/30 focus:border-orange-500 transition"
              required
            />
          </div>
          {error && (
            <p className="text-sm text-red-600">{error}</p>
          )}
          <button
            type="submit"
            disabled={loading}
            className="w-full py-3 bg-orange-500 text-white font-semibold rounded-xl hover:bg-orange-600 disabled:opacity-50 shadow-md hover:shadow-lg transition"
          >
            {loading ? 'Memuat...' : 'Login'}
          </button>
        </form>
      </div>
    </div>
  )
}
