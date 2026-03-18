/**
 * Konfigurasi Traka Backend API (hybrid driver_status).
 * Set VITE_TRAKA_API_BASE_URL dan VITE_TRAKA_USE_HYBRID di .env
 */
export const apiBaseUrl = import.meta.env.VITE_TRAKA_API_BASE_URL || ''
export const useHybrid = import.meta.env.VITE_TRAKA_USE_HYBRID === 'true'
export const isApiEnabled = apiBaseUrl && useHybrid
