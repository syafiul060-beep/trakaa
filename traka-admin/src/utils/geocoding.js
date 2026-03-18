/**
 * Reverse geocoding untuk menentukan provinsi dari lat/lng.
 * Menggunakan Nominatim (OpenStreetMap) - gratis, 1 req/detik.
 * Cache hasil untuk mengurangi request.
 */

const CACHE = new Map()
const CACHE_PRECISION = 3 // decimal places for cache key

const PROVINCE_ALIASES = {
  'Aceh': ['Aceh', 'NAD', 'Nanggroe Aceh Darussalam'],
  'Sumatera Utara': ['Sumatera Utara', 'Sumatra Utara'],
  'Sumatera Barat': ['Sumatera Barat', 'Sumatra Barat'],
  'Riau': ['Riau'],
  'Kepulauan Riau': ['Kepulauan Riau', 'Kepri'],
  'Jambi': ['Jambi'],
  'Sumatera Selatan': ['Sumatera Selatan', 'Sumatra Selatan', 'Sumsel'],
  'Bangka Belitung': ['Bangka Belitung', 'Babel'],
  'Bengkulu': ['Bengkulu'],
  'Lampung': ['Lampung'],
  'Banten': ['Banten'],
  'DKI Jakarta': ['DKI Jakarta', 'Jakarta', 'Daerah Khusus Ibukota Jakarta'],
  'Jawa Barat': ['Jawa Barat', 'Jabar'],
  'Jawa Tengah': ['Jawa Tengah', 'Jateng'],
  'Jawa Timur': ['Jawa Timur', 'Jatim'],
  'DI Yogyakarta': ['DI Yogyakarta', 'Yogyakarta', 'Daerah Istimewa Yogyakarta'],
  'Kalimantan Barat': ['Kalimantan Barat', 'Kalbar'],
  'Kalimantan Tengah': ['Kalimantan Tengah', 'Kalteng'],
  'Kalimantan Selatan': ['Kalimantan Selatan', 'Kalsel'],
  'Kalimantan Timur': ['Kalimantan Timur', 'Kaltim'],
  'Kalimantan Utara': ['Kalimantan Utara', 'Kaltara'],
  'Sulawesi Utara': ['Sulawesi Utara', 'Sulut'],
  'Sulawesi Barat': ['Sulawesi Barat', 'Sulbar'],
  'Sulawesi Tengah': ['Sulawesi Tengah', 'Sulteng'],
  'Sulawesi Selatan': ['Sulawesi Selatan', 'Sulsel'],
  'Sulawesi Tenggara': ['Sulawesi Tenggara', 'Sultra'],
  'Gorontalo': ['Gorontalo'],
  'Bali': ['Bali'],
  'Nusa Tenggara Barat': ['Nusa Tenggara Barat', 'NTB'],
  'Nusa Tenggara Timur': ['Nusa Tenggara Timur', 'NTT'],
  'Maluku': ['Maluku'],
  'Maluku Utara': ['Maluku Utara', 'Malut'],
  'Papua': ['Papua'],
  'Papua Barat': ['Papua Barat'],
  'Papua Selatan': ['Papua Selatan'],
  'Papua Tengah': ['Papua Tengah'],
  'Papua Pegunungan': ['Papua Pegunungan'],
  'Papua Barat Daya': ['Papua Barat Daya'],
}

const PROVINCE_TO_ISLAND = {
  'Aceh': 'Sumatera', 'Sumatera Utara': 'Sumatera', 'Sumatera Barat': 'Sumatera',
  'Riau': 'Sumatera', 'Kepulauan Riau': 'Sumatera', 'Jambi': 'Sumatera',
  'Sumatera Selatan': 'Sumatera', 'Bangka Belitung': 'Sumatera', 'Bengkulu': 'Sumatera', 'Lampung': 'Sumatera',
  'Banten': 'Jawa', 'DKI Jakarta': 'Jawa', 'Jawa Barat': 'Jawa', 'Jawa Tengah': 'Jawa',
  'Jawa Timur': 'Jawa', 'DI Yogyakarta': 'Jawa',
  'Kalimantan Barat': 'Kalimantan', 'Kalimantan Tengah': 'Kalimantan', 'Kalimantan Selatan': 'Kalimantan',
  'Kalimantan Timur': 'Kalimantan', 'Kalimantan Utara': 'Kalimantan',
  'Sulawesi Utara': 'Sulawesi', 'Sulawesi Barat': 'Sulawesi', 'Sulawesi Tengah': 'Sulawesi',
  'Sulawesi Selatan': 'Sulawesi', 'Sulawesi Tenggara': 'Sulawesi', 'Gorontalo': 'Sulawesi',
  'Bali': 'Bali', 'Nusa Tenggara Barat': 'Bali', 'Nusa Tenggara Timur': 'Bali',
  'Maluku': 'Maluku', 'Maluku Utara': 'Maluku',
  'Papua': 'Papua', 'Papua Barat': 'Papua', 'Papua Selatan': 'Papua', 'Papua Tengah': 'Papua',
  'Papua Pegunungan': 'Papua', 'Papua Barat Daya': 'Papua',
}

function normalizeProvince(text) {
  if (!text || typeof text !== 'string') return null
  const t = text.trim()
  for (const [canonical, aliases] of Object.entries(PROVINCE_ALIASES)) {
    for (const a of aliases) {
      if (t.includes(a) || t === a) return canonical
    }
  }
  return null
}

/**
 * Coba ekstrak provinsi dari teks alamat (originText, destText).
 * Format umum: "..., Kota/Kabupaten, Provinsi" atau "..., Provinsi"
 */
export function extractProvinceFromAddress(addressText) {
  if (!addressText || typeof addressText !== 'string') return null
  const parts = addressText.split(',').map((p) => p.trim()).filter(Boolean)
  for (let i = parts.length - 1; i >= 0; i--) {
    const p = normalizeProvince(parts[i])
    if (p) return p
  }
  return null
}

function cacheKey(lat, lng) {
  return `${Number(lat).toFixed(CACHE_PRECISION)},${Number(lng).toFixed(CACHE_PRECISION)}`
}

let lastRequestTime = 0
const MIN_INTERVAL_MS = 1100 // 1.1 sec between Nominatim requests

async function delay(ms) {
  return new Promise((r) => setTimeout(r, ms))
}

/**
 * Reverse geocoding via Nominatim. Returns province name or null.
 */
export async function getProvinceFromLatLng(lat, lng) {
  const key = cacheKey(lat, lng)
  if (CACHE.has(key)) return CACHE.get(key)

  const now = Date.now()
  const elapsed = now - lastRequestTime
  if (elapsed < MIN_INTERVAL_MS) {
    await delay(MIN_INTERVAL_MS - elapsed)
  }

  try {
    const url = `https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lng}&zoom=10&addressdetails=1`
    const res = await fetch(url, {
      headers: { 'User-Agent': 'Traka-Admin/1.0 (admin panel)' },
    })
    lastRequestTime = Date.now()
    if (!res.ok) {
      CACHE.set(key, null)
      return null
    }
    const data = await res.json()
    const state = data?.address?.state || data?.address?.province || null
    const province = normalizeProvince(state) || (state ? state : null)
    CACHE.set(key, province)
    return province
  } catch (err) {
    console.warn('Geocoding error:', err)
    CACHE.set(key, null)
    return null
  }
}

/**
 * Tentukan tier (1/2/3) dan fee berdasarkan provinsi asal & tujuan.
 * Tier 1: sama provinsi, 2: beda provinsi sama pulau, 3: beda pulau.
 */
export function getTierFromProvinces(originProvince, destProvince) {
  if (!originProvince || !destProvince) return 2 // default beda provinsi
  if (originProvince === destProvince) return 1
  const oIsland = PROVINCE_TO_ISLAND[originProvince]
  const dIsland = PROVINCE_TO_ISLAND[destProvince]
  if (oIsland && dIsland && oIsland !== dIsland) return 3
  return 2
}

/**
 * Ambil fee lacak barang untuk order berdasarkan tier.
 */
export function getLacakBarangFeeForTier(tier, lacakBarang1, lacakBarang2, lacakBarang3) {
  if (tier === 1) return lacakBarang1
  if (tier === 3) return lacakBarang3
  return lacakBarang2
}

/**
 * Tentukan tier dan fee untuk order kirim_barang.
 * Prioritas: 1) parse dari address, 2) geocoding dari lat/lng.
 */
export async function getLacakBarangTierAndFee(orderData, lacakBarang1, lacakBarang2, lacakBarang3) {
  const pickLat = orderData.pickupLat ?? orderData.passengerLat ?? orderData.originLat
  const pickLng = orderData.pickupLng ?? orderData.passengerLng ?? orderData.originLng
  const recvLat = orderData.receiverLat ?? orderData.destLat
  const recvLng = orderData.receiverLng ?? orderData.destLng

  let originProvince = extractProvinceFromAddress(orderData.originText || '')
  let destProvince = extractProvinceFromAddress(orderData.receiverLocationText || orderData.destText || '')

  if (!originProvince || !destProvince) {
    if (pickLat != null && pickLng != null && recvLat != null && recvLng != null) {
      originProvince = originProvince || (await getProvinceFromLatLng(pickLat, pickLng))
      destProvince = destProvince || (await getProvinceFromLatLng(recvLat, recvLng))
    }
  }

  const tier = getTierFromProvinces(originProvince, destProvince)
  const fee = getLacakBarangFeeForTier(tier, lacakBarang1, lacakBarang2, lacakBarang3)
  return { tier, fee }
}
