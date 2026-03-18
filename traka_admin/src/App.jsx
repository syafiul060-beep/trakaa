import { useState, useEffect } from 'react'
import { onAuthStateChanged } from 'firebase/auth'
import { doc, getDoc } from 'firebase/firestore'
import { auth, db } from './firebase'
import Login from './Login'
import Dashboard from './Dashboard'
import Support from './Support'
import Promos from './Promos'

function App() {
  const [user, setUser] = useState(null)
  const [isAdmin, setIsAdmin] = useState(false)
  const [loading, setLoading] = useState(true)
  const [view, setView] = useState('dashboard') // dashboard | support | promos

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, async (u) => {
      setUser(u)
      if (u) {
        const userDoc = await getDoc(doc(db, 'users', u.uid))
        setIsAdmin(userDoc.data()?.role === 'admin')
      } else {
        setIsAdmin(false)
      }
      setLoading(false)
    })
    return () => unsub()
  }, [])

  if (loading) return <div className="loading">Memuat...</div>
  if (!user) return <Login />
  if (!isAdmin) return <div className="container"><div className="alert alert-error">Akses ditolak. Hanya admin yang dapat mengakses panel ini.</div></div>

  return (
    <>
      <div className="container" style={{ paddingBottom: 8 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 12 }}>
          <div style={{ display: 'flex', gap: 8 }}>
            <button
              className={`btn ${view === 'dashboard' ? 'btn-primary' : ''}`}
              style={view !== 'dashboard' ? { background: '#e2e8f0' } : {}}
              onClick={() => setView('dashboard')}
            >
              Dashboard
            </button>
            <button
              className={`btn ${view === 'support' ? 'btn-primary' : ''}`}
              style={view !== 'support' ? { background: '#e2e8f0' } : {}}
              onClick={() => setView('support')}
            >
              Live Chat Support
            </button>
            <button
              className={`btn ${view === 'promos' ? 'btn-primary' : ''}`}
              style={view !== 'promos' ? { background: '#e2e8f0' } : {}}
              onClick={() => setView('promos')}
            >
              Promosi
            </button>
          </div>
          <button className="btn" style={{ background: '#e2e8f0' }} onClick={() => auth.signOut()}>Logout</button>
        </div>
      </div>
      {view === 'dashboard' && <Dashboard onLogout={() => auth.signOut()} hideHeader />}
      {view === 'support' && <Support onLogout={() => auth.signOut()} />}
      {view === 'promos' && <Promos />}
    </>
  )
}

export default App
