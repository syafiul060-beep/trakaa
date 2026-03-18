/**
 * Validasi input untuk Settings dan form lainnya.
 */

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
export function isValidEmail(value) {
  if (!value || typeof value !== 'string') return false
  return EMAIL_REGEX.test(value.trim())
}

export function isValidWhatsApp(value) {
  if (!value || typeof value !== 'string') return true // kosong = ok
  const cleaned = value.trim().replace(/\s/g, '').replace(/^\+/, '')
  return /^[0-9]{10,15}$/.test(cleaned) || /^62[0-9]{9,12}$/.test(cleaned)
}

export function isValidVersion(value) {
  if (!value || typeof value !== 'string') return true
  return /^[0-9]+\.[0-9]+(\.[0-9]+)?$/.test(value.trim())
}

/** Normalisasi nomor Indonesia ke E.164 (+62...). */
export function toE164(input) {
  if (!input || typeof input !== 'string') return ''
  const digits = input.replace(/\D/g, '')
  if (digits.length < 9) return ''
  if (digits.startsWith('0')) return '+62' + digits.substring(1)
  if (!digits.startsWith('62')) return '+62' + digits
  return '+' + digits
}

/** Cek apakah string mirip nomor telepon (bukan UID). UID biasanya alfanumerik. */
export function looksLikePhone(input) {
  if (!input || typeof input !== 'string') return false
  const trimmed = input.trim()
  if (/[a-zA-Z]/.test(trimmed)) return false
  const digits = trimmed.replace(/\D/g, '')
  return digits.length >= 9
}
