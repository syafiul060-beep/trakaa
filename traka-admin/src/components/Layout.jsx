import { useState, useEffect, useRef, useCallback } from 'react'
import { Outlet, NavLink, useNavigate, useLocation } from 'react-router-dom'
import { signOut } from 'firebase/auth'
import { auth } from '../firebase'
import { ADMIN_LOGIN_PATH } from '../config'
import Logo from './Logo'
import { useIdleTimeout } from '../hooks/useIdleTimeout'
import { useFocusTrap } from '../hooks/useFocusTrap'
import {
  AdminNavIcon,
  NavIconChevronLeft,
  NavIconChevronRight,
  NavIconLogout,
} from './AdminNavIcons'

const STORAGE_KEY = 'traka_admin_sidebar_collapsed'

const navItems = [
  { path: '/dashboard', label: 'Dasbor', icon: 'dashboard' },
  { path: '/orders', label: 'Pesanan', icon: 'orders' },
  { path: '/users', label: 'Pengguna', icon: 'users' },
  { path: '/notifications', label: 'Notifikasi', icon: 'notifications' },
  { path: '/drivers', label: 'Driver', icon: 'drivers' },
  { path: '/chat', label: 'Chat', icon: 'chat' },
  { path: '/reports', label: 'Laporan', icon: 'reports' },
  { path: '/violations', label: 'Pelanggaran', icon: 'violations' },
  { path: '/audit', label: 'Log audit', icon: 'audit' },
  { path: '/broadcast', label: 'Siaran', icon: 'broadcast' },
  { path: '/settings', label: 'Pengaturan', icon: 'settings' },
]

export default function Layout() {
  const navigate = useNavigate()
  const location = useLocation()
  const [searchQuery, setSearchQuery] = useState('')
  const [collapsed, setCollapsed] = useState(() => {
    try {
      return localStorage.getItem(STORAGE_KEY) === 'true'
    } catch {
      return false
    }
  })
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)
  const [isMobile, setIsMobile] = useState(false)
  const [logoutOpen, setLogoutOpen] = useState(false)
  const logoutModalRef = useRef(null)

  useFocusTrap(logoutOpen, logoutModalRef)

  const performLogout = useCallback(async () => {
    setLogoutOpen(false)
    try {
      await signOut(auth)
    } catch (_) {}
    navigate(ADMIN_LOGIN_PATH, { replace: true })
  }, [navigate])

  const onIdleSignOut = useCallback(async () => {
    try {
      sessionStorage.setItem('traka_admin_session_end', 'idle')
      await signOut(auth)
      navigate(ADMIN_LOGIN_PATH, { replace: true })
    } catch (_) {}
  }, [navigate])

  useIdleTimeout(onIdleSignOut, 30 * 60 * 1000, true)

  useEffect(() => {
    const mq = window.matchMedia('(min-width: 768px)')
    const fn = () => setIsMobile(!mq.matches)
    fn()
    mq.addEventListener('change', fn)
    return () => mq.removeEventListener('change', fn)
  }, [])

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, String(collapsed))
    } catch (_) {}
  }, [collapsed])

  useEffect(() => {
    setMobileMenuOpen(false)
  }, [location.pathname])

  useEffect(() => {
    if (!logoutOpen) return
    const onKey = (e) => {
      if (e.key === 'Escape') setLogoutOpen(false)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [logoutOpen])

  const currentLabel = navItems.find((i) => location.pathname.startsWith(i.path))?.label || 'Dasbor'

  const sidebarExpanded = !collapsed || isMobile

  const SidebarContent = () => (
    <>
      <div className={`p-4 border-b border-slate-700/80 ${!sidebarExpanded ? 'flex justify-center' : ''}`}>
        <Logo collapsed={!sidebarExpanded} />
      </div>
      <nav
        className="flex-1 p-3 space-y-1 overflow-y-auto"
        aria-label="Menu utama admin"
      >
        {navItems.map((item) => (
          <NavLink
            key={item.path}
            to={item.path}
            title={!sidebarExpanded ? item.label : undefined}
            className={({ isActive }) =>
              `flex items-center gap-3 px-3 py-3 rounded-xl transition-all duration-200 ${
                !sidebarExpanded ? 'justify-center' : ''
              } ${
                isActive
                  ? 'bg-gradient-to-r from-orange-500 to-orange-600 text-white shadow-lg shadow-orange-500/25'
                  : 'hover:bg-slate-700/80 text-slate-200 hover:text-white'
              }`
            }
          >
            <span className="shrink-0 opacity-90" aria-hidden>
              <AdminNavIcon name={item.icon} className="w-5 h-5" />
            </span>
            {sidebarExpanded && <span className="font-medium truncate">{item.label}</span>}
          </NavLink>
        ))}
      </nav>
      <div className="p-3 border-t border-slate-700/80 space-y-1">
        {!isMobile && (
          <button
            type="button"
            onClick={() => setCollapsed(!collapsed)}
            title={collapsed ? 'Perluas menu' : 'Minimalkan menu'}
            className={`w-full flex items-center gap-3 px-3 py-3 rounded-xl hover:bg-slate-700/80 text-slate-300 hover:text-white transition-all ${
              collapsed ? 'justify-center' : ''
            }`}
          >
            <span className="shrink-0" aria-hidden>
              {collapsed ? <NavIconChevronRight className="w-5 h-5" /> : <NavIconChevronLeft className="w-5 h-5" />}
            </span>
            {!collapsed && <span className="font-medium text-sm">Minimalkan</span>}
          </button>
        )}
        <button
          type="button"
          onClick={() => setLogoutOpen(true)}
          title={!sidebarExpanded ? 'Keluar' : undefined}
          className={`w-full flex items-center gap-3 px-3 py-3 rounded-xl hover:bg-slate-700/80 text-red-300 hover:text-red-200 transition-all ${
            !sidebarExpanded ? 'justify-center' : ''
          }`}
        >
          <span className="shrink-0" aria-hidden>
            <NavIconLogout className="w-5 h-5" />
          </span>
          {sidebarExpanded && <span className="font-medium">Keluar</span>}
        </button>
      </div>
    </>
  )

  return (
    <div className="h-screen overflow-hidden bg-slate-50/50 flex">
      {logoutOpen && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center p-4">
          <button
            type="button"
            className="absolute inset-0 bg-black/50 border-0 cursor-default w-full h-full"
            aria-label="Tutup dialog"
            onClick={() => setLogoutOpen(false)}
          />
          <div
            ref={logoutModalRef}
            role="dialog"
            aria-modal="true"
            aria-labelledby="logout-dialog-title"
            aria-describedby="logout-dialog-desc"
            className="relative bg-white rounded-2xl shadow-xl p-6 max-w-md w-full z-10"
          >
            <h2 id="logout-dialog-title" className="text-lg font-semibold text-slate-800">
              Keluar dari panel admin?
            </h2>
            <p id="logout-dialog-desc" className="text-sm text-slate-600 mt-2">
              Anda perlu masuk lagi untuk mengakses halaman ini.
            </p>
            <div className="flex justify-end gap-2 mt-6">
              <button
                type="button"
                onClick={() => setLogoutOpen(false)}
                className="px-4 py-2 rounded-xl border border-slate-200 text-slate-700 text-sm font-medium hover:bg-slate-50"
              >
                Batal
              </button>
              <button
                type="button"
                onClick={performLogout}
                className="px-4 py-2 rounded-xl bg-red-600 text-white text-sm font-medium hover:bg-red-700"
              >
                Keluar
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Mobile backdrop */}
      <div
        className={`fixed inset-0 bg-black/50 z-40 md:hidden transition-opacity ${
          mobileMenuOpen ? 'opacity-100' : 'opacity-0 pointer-events-none'
        }`}
        onClick={() => setMobileMenuOpen(false)}
        aria-hidden="true"
      />

      <aside
        className={`fixed inset-y-0 left-0 z-50 flex flex-col shrink-0 bg-slate-800 text-white shadow-xl transition-all duration-300 ease-out w-64 ${collapsed ? 'md:w-20' : 'md:w-64'} ${
          mobileMenuOpen ? 'translate-x-0' : '-translate-x-full md:translate-x-0'
        }`}
      >
        <SidebarContent />
      </aside>

      <main className={`flex-1 overflow-auto min-w-0 transition-all duration-300 ${collapsed ? 'md:ml-20' : 'md:ml-64'}`}>
        <header className="bg-white/90 backdrop-blur-sm border-b border-slate-100 px-4 sm:px-6 lg:px-8 py-4 shadow-sm">
          <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
            <div className="flex items-center gap-3">
              <button
                type="button"
                onClick={() => setMobileMenuOpen(true)}
                className="md:hidden p-2 -ml-2 rounded-xl hover:bg-slate-100 text-slate-600"
                aria-label="Buka menu"
              >
                <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
                </svg>
              </button>
              <h2 className="text-lg sm:text-xl font-bold text-slate-800 truncate">{currentLabel}</h2>
            </div>
            <div className="flex items-center gap-4">
              <input
                type="search"
                placeholder="Cari..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="hidden sm:block px-4 py-2 w-48 rounded-xl border border-slate-200 bg-slate-50 text-sm focus:ring-2 focus:ring-orange-500/30 focus:border-orange-500 focus:bg-white transition"
                aria-label="Cari di halaman"
              />
              <div className="flex items-center gap-2 px-3 py-2 rounded-xl bg-slate-100">
                <div className="w-8 h-8 rounded-full bg-gradient-to-br from-orange-400 to-teal-500 flex items-center justify-center text-white text-sm font-bold" aria-hidden>
                  {auth.currentUser?.email?.[0]?.toUpperCase() || 'A'}
                </div>
                <span className="text-sm text-slate-600 truncate max-w-[140px] hidden md:inline">
                  {auth.currentUser?.email}
                </span>
              </div>
            </div>
          </div>
        </header>
        <div className="p-4 sm:p-6 lg:p-8">
          <Outlet context={{ searchQuery }} />
        </div>
      </main>
    </div>
  )
}
