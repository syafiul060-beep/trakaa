import { apiBaseUrl, isApiEnabled } from '../config/apiConfig'

/**
 * @typedef {'ok'|'disabled'|'error'|'network'} DriverListStatus
 */

/**
 * Daftar driver dari API hybrid.
 * @returns {{ status: DriverListStatus, drivers: object[], httpStatus?: number }}
 */
export async function getDriverStatusList() {
  if (!isApiEnabled) {
    return { status: 'disabled', drivers: [] }
  }
  try {
    const res = await fetch(`${apiBaseUrl}/api/driver/status`)
    if (!res.ok) {
      console.error('trakaApi.getDriverStatusList HTTP', res.status)
      return { status: 'error', drivers: [], httpStatus: res.status }
    }
    const data = await res.json()
    return { status: 'ok', drivers: data.drivers || [] }
  } catch (err) {
    console.error('trakaApi.getDriverStatusList:', err)
    return { status: 'network', drivers: [] }
  }
}

/**
 * Status driver tunggal.
 * @returns {{ status: DriverListStatus, driver: object|null, httpStatus?: number }}
 */
export async function getDriverStatus(uid) {
  if (!isApiEnabled) {
    return { status: 'disabled', driver: null }
  }
  try {
    const res = await fetch(`${apiBaseUrl}/api/driver/${uid}/status`)
    if (!res.ok) {
      console.error('trakaApi.getDriverStatus HTTP', res.status, uid)
      return { status: 'error', driver: null, httpStatus: res.status }
    }
    const driver = await res.json()
    return { status: 'ok', driver }
  } catch (err) {
    console.error('trakaApi.getDriverStatus:', err)
    return { status: 'network', driver: null }
  }
}
