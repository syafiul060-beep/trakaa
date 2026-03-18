import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { useState, useEffect, Suspense, lazy } from 'react'
import { onAuthStateChanged } from 'firebase/auth'
import { doc, getDoc } from 'firebase/firestore'
import { auth, db } from './firebase'
import { ADMIN_LOGIN_PATH } from './config'
import ErrorBoundary from './components/ErrorBoundary'

import Layout from './components/Layout'
import Login from './pages/Login'

// Lazy load pages untuk mengurangi ukuran initial bundle
const Dashboard = lazy(() => import('./pages/Dashboard'))
const Orders = lazy(() => import('./pages/Orders'))
const OrderDetail = lazy(() => import('./pages/OrderDetail'))
const Users = lazy(() => import('./pages/Users'))
const Drivers = lazy(() => import('./pages/Drivers'))
const Chat = lazy(() => import('./pages/Chat'))
const Reports = lazy(() => import('./pages/Reports'))
const Settings = lazy(() => import('./pages/Settings'))
const Violations = lazy(() => import('./pages/Violations'))
const AuditLog = lazy(() => import('./pages/AuditLog'))
const Broadcast = lazy(() => import('./pages/Broadcast'))

function ProtectedRoute({ children, isAdmin }) {
  if (!auth.currentUser) {
    return <Navigate to={ADMIN_LOGIN_PATH} replace />
  }
  if (!isAdmin) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-100">
        <div className="bg-white p-8 rounded-lg shadow text-center">
          <p className="text-red-600 font-medium">Akses ditolak.</p>
          <p className="text-gray-600 text-sm mt-2">Anda bukan admin.</p>
        </div>
      </div>
    )
  }
  return children
}

export default function App() {
  const [user, setUser] = useState(null)
  const [isAdmin, setIsAdmin] = useState(false)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, async (firebaseUser) => {
      setUser(firebaseUser)
      if (firebaseUser) {
        const userDoc = await getDoc(doc(db, 'users', firebaseUser.uid))
        setIsAdmin(userDoc.data()?.role === 'admin')
      } else {
        setIsAdmin(false)
      }
      setLoading(false)
    })
    return () => unsub()
  }, [])

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-100">
        <div className="animate-spin rounded-full h-12 w-12 border-4 border-traka-orange border-t-transparent"></div>
      </div>
    )
  }

  const PageFallback = () => (
    <div className="flex items-center justify-center p-8">
      <div className="animate-spin rounded-full h-8 w-8 border-2 border-traka-orange border-t-transparent" />
    </div>
  )

  return (
    <ErrorBoundary>
    <BrowserRouter basename={import.meta.env.BASE_URL}>
      <Suspense fallback={<PageFallback />}>
        <Routes>
          <Route path={ADMIN_LOGIN_PATH} element={user ? <Navigate to="/" replace /> : <Login />} />
          <Route
            path="/"
            element={
              <ProtectedRoute isAdmin={isAdmin}>
                <Layout />
              </ProtectedRoute>
            }
          >
            <Route index element={<Navigate to="/dashboard" replace />} />
            <Route path="dashboard" element={<Dashboard />} />
            <Route path="orders" element={<Orders />} />
            <Route path="orders/:id" element={<OrderDetail />} />
            <Route path="users" element={<Users />} />
            <Route path="drivers" element={<Drivers />} />
            <Route path="chat" element={<Chat />} />
            <Route path="reports" element={<Reports />} />
            <Route path="violations" element={<Violations />} />
            <Route path="audit" element={<AuditLog />} />
            <Route path="broadcast" element={<Broadcast />} />
            <Route path="settings" element={<Settings />} />
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </Suspense>
    </BrowserRouter>
    </ErrorBoundary>
  )
}
