import { apiBaseUrl, isApiEnabled } from '../config/apiConfig'

/**
 * Ambil daftar semua driver aktif dari API (Redis).
 */
export async function getDriverStatusList() {
  if (!isApiEnabled) return []
  try {
    const res = await fetch(`${apiBaseUrl}/api/driver/status`)
    if (!res.ok) return []
    const data = await res.json()
    return data.drivers || []
  } catch (err) {
    console.error('trakaApi.getDriverStatusList:', err)
    return []
  }
}

/**
 * Ambil status driver tunggal dari API.
 */
export async function getDriverStatus(uid) {
  if (!isApiEnabled) return null
  try {
    const res = await fetch(`${apiBaseUrl}/api/driver/${uid}/status`)
    if (!res.ok) return null
    return await res.json()
  } catch (err) {
    console.error('trakaApi.getDriverStatus:', err)
    return null
  }
}
