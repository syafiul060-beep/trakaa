import { Component } from 'react'

/**
 * Error Boundary untuk menangkap error di child components.
 * Mencegah crash seluruh aplikasi saat terjadi error.
 */
export default class ErrorBoundary extends Component {
  state = { hasError: false, error: null }

  static getDerivedStateFromError(error) {
    return { hasError: true, error }
  }

  componentDidCatch(error, errorInfo) {
    console.error('ErrorBoundary caught:', error, errorInfo)
  }

  handleReset = () => {
    this.setState({ hasError: false, error: null })
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="min-h-screen flex items-center justify-center bg-slate-50 p-4">
          <div className="bg-white rounded-2xl shadow-lg border border-slate-200 p-8 max-w-md text-center">
            <div className="w-16 h-16 mx-auto mb-4 rounded-full bg-red-100 flex items-center justify-center text-3xl">
              ⚠️
            </div>
            <h2 className="text-xl font-bold text-slate-800 mb-2">Terjadi Kesalahan</h2>
            <p className="text-slate-600 text-sm mb-6">
              Halaman tidak dapat dimuat. Silakan refresh atau kembali ke dashboard.
            </p>
            <div className="flex gap-3 justify-center flex-wrap">
              <button
                onClick={() => window.location.reload()}
                className="px-4 py-2 bg-orange-500 text-white rounded-lg hover:bg-orange-600 font-medium"
              >
                Muat Ulang
              </button>
              <button
                onClick={() => (window.location.href = '/')}
                className="px-4 py-2 border border-slate-300 text-slate-700 rounded-lg hover:bg-slate-50 font-medium"
              >
                Ke Beranda
              </button>
            </div>
          </div>
        </div>
      )
    }
    return this.props.children
  }
}
