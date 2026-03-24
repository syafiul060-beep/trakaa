import { apiBaseUrl, isApiEnabled } from '../config/apiConfig'
import { auth } from '../firebase'

async function bearerHeaders() {
  const user = auth.currentUser
  if (!user) throw new Error('Belum login')
  const token = await user.getIdToken()
  return {
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  }
}

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
/**
 * Metode bayar driver — menunggu persetujuan admin (nama beda profil).
 */
export async function getPendingPaymentMethods() {
  if (!isApiEnabled) return { status: 'disabled', methods: [] }
  try {
    const headers = await bearerHeaders()
    const res = await fetch(`${apiBaseUrl}/api/admin/payment-methods/pending`, { headers })
    if (!res.ok) {
      console.error('getPendingPaymentMethods HTTP', res.status)
      return { status: 'error', methods: [], httpStatus: res.status }
    }
    const data = await res.json()
    return { status: 'ok', methods: data.methods || [] }
  } catch (err) {
    console.error('getPendingPaymentMethods:', err)
    return { status: 'network', methods: [] }
  }
}

export async function approvePaymentMethod(id, adminNote) {
  if (!isApiEnabled) return { ok: false, error: 'API nonaktif' }
  try {
    const headers = await bearerHeaders()
    const res = await fetch(`${apiBaseUrl}/api/admin/payment-methods/${id}/approve`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ adminNote: adminNote || null }),
    })
    const data = await res.json().catch(() => ({}))
    if (!res.ok) return { ok: false, error: data.error || `HTTP ${res.status}` }
    return { ok: true, data }
  } catch (e) {
    return { ok: false, error: e.message }
  }
}

export async function rejectPaymentMethod(id, adminNote) {
  if (!isApiEnabled) return { ok: false, error: 'API nonaktif' }
  try {
    const headers = await bearerHeaders()
    const res = await fetch(`${apiBaseUrl}/api/admin/payment-methods/${id}/reject`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ adminNote: adminNote || '' }),
    })
    const data = await res.json().catch(() => ({}))
    if (!res.ok) return { ok: false, error: data.error || `HTTP ${res.status}` }
    return { ok: true, data }
  } catch (e) {
    return { ok: false, error: e.message }
  }
}

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
