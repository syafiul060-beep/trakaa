import { useState, useEffect } from 'react'
import { doc, getDoc, setDoc, collection, getDocs, query, where, deleteField } from 'firebase/firestore'
import { db } from '../firebase'
import { logAudit } from '../utils/auditLog'
import { isValidEmail, isValidWhatsApp, isValidVersion, toE164, looksLikePhone } from '../utils/validation'

/** Ikon chip hero login — selaras dengan whitelist di app Flutter. */
const LOGIN_HERO_ICON_OPTIONS = [
  { value: 'route', label: 'Rute / travel' },
  { value: 'map', label: 'Peta / lacak' },
  { value: 'inventory', label: 'Paket / inventory' },
  { value: 'post', label: 'Kantor pos' },
  { value: 'shipping', label: 'Pengiriman truk' },
  { value: 'shield', label: 'Keamanan' },
  { value: 'star', label: 'Bintang / promo' },
  { value: 'bolt', label: 'Kilat / cepat' },
  { value: 'taxi', label: 'Taksi' },
  { value: 'gps', label: 'GPS / lokasi' },
  { value: 'payment', label: 'Pembayaran' },
  { value: 'groups', label: 'Komunitas' },
  { value: 'favorite', label: 'Favorit' },
]
const LOGIN_HERO_ICON_KEYS = LOGIN_HERO_ICON_OPTIONS.map((o) => o.value)

const DEFAULT_LOGIN_HERO_PILLS = [
  { icon: 'route', labelId: '', labelEn: '' },
  { icon: 'map', labelId: '', labelEn: '' },
  { icon: 'post', labelId: '', labelEn: '' },
]

function SettingsCard({ title, icon, children }) {
  return (
    <div className="bg-white rounded-2xl shadow-card border border-slate-100 overflow-hidden hover:shadow-card-hover transition-shadow">
      <div className="px-6 py-5 bg-gradient-to-r from-slate-50 to-white border-b border-slate-100">
        <h3 className="text-lg font-bold text-slate-800 flex items-center gap-2">
          <span className="text-2xl">{icon}</span>
          {title}
        </h3>
      </div>
      <div className="p-6">{children}</div>
    </div>
  )
}

function InputField({ label, value, onChange, type = 'text', min, max, placeholder, hint, maxLength }) {
  return (
    <div className="mb-4 last:mb-0">
      <label className="block text-sm font-medium text-gray-700 mb-1.5">{label}</label>
      <input
        type={type}
        min={min}
        max={max}
        maxLength={maxLength}
        value={value}
        onChange={onChange}
        placeholder={placeholder}
        className="w-full px-4 py-2.5 border border-slate-200 rounded-xl focus:ring-2 focus:ring-orange-500/30 focus:border-orange-500 transition"
      />
      {hint && <p className="text-xs text-gray-500 mt-1">{hint}</p>}
    </div>
  )
}

function TextAreaField({ label, value, onChange, placeholder, hint, rows = 3, maxLength }) {
  return (
    <div className="mb-4 last:mb-0">
      <label className="block text-sm font-medium text-gray-700 mb-1.5">{label}</label>
      <textarea
        rows={rows}
        maxLength={maxLength}
        value={value}
        onChange={onChange}
        placeholder={placeholder}
        className="w-full px-4 py-2.5 border border-slate-200 rounded-xl focus:ring-2 focus:ring-orange-500/30 focus:border-orange-500 transition resize-y min-h-[4.5rem]"
      />
      {hint && <p className="text-xs text-gray-500 mt-1">{hint}</p>}
    </div>
  )
}

export default function Settings() {
  const [tarifPerKm, setTarifPerKm] = useState(70)
  const [violationFeeRupiah, setViolationFeeRupiah] = useState(5000)
  const [lacakDriverFeeRupiah, setLacakDriverFeeRupiah] = useState(3000)
  const [lacakBarangDalamProvinsiRupiah, setLacakBarangDalamProvinsiRupiah] = useState(10000)
  const [lacakBarangBedaProvinsiRupiah, setLacakBarangBedaProvinsiRupiah] = useState(15000)
  const [lacakBarangLebihDari1ProvinsiRupiah, setLacakBarangLebihDari1ProvinsiRupiah] = useState(25000)
  const [minKontribusiTravelRupiah, setMinKontribusiTravelRupiah] = useState(5000)
  const [maxKontribusiTravelPerRuteRupiah, setMaxKontribusiTravelPerRuteRupiah] = useState(30000)
  const [tarifKontribusiTravelDalamProvinsiPerKm, setTarifKontribusiTravelDalamProvinsiPerKm] = useState(90)
  const [tarifKontribusiTravelBedaProvinsiPerKm, setTarifKontribusiTravelBedaProvinsiPerKm] = useState(110)
  const [tarifKontribusiTravelBedaPulauPerKm, setTarifKontribusiTravelBedaPulauPerKm] = useState(140)
  const [tarifBarangDalamProvinsiPerKm, setTarifBarangDalamProvinsiPerKm] = useState(15)
  const [tarifBarangBedaProvinsiPerKm, setTarifBarangBedaProvinsiPerKm] = useState(35)
  const [tarifBarangLebihDari1ProvinsiPerKm, setTarifBarangLebihDari1ProvinsiPerKm] = useState(50)
  const [tarifBarangDokumenDalamProvinsiPerKm, setTarifBarangDokumenDalamProvinsiPerKm] = useState(10)
  const [tarifBarangDokumenBedaProvinsiPerKm, setTarifBarangDokumenBedaProvinsiPerKm] = useState(25)
  const [tarifBarangDokumenLebihDari1ProvinsiPerKm, setTarifBarangDokumenLebihDari1ProvinsiPerKm] = useState(35)
  const [adminEmail, setAdminEmail] = useState('')
  const [adminWhatsApp, setAdminWhatsApp] = useState('')
  const [adminInstagram, setAdminInstagram] = useState('')
  const [minVersion, setMinVersion] = useState('')
  const [maintenanceEnabled, setMaintenanceEnabled] = useState(false)
  const [maintenanceMessage, setMaintenanceMessage] = useState('')
  const [exemptDriverUids, setExemptDriverUids] = useState([])
  const [newExemptInput, setNewExemptInput] = useState('')
  const [lacakExemptUserUids, setLacakExemptUserUids] = useState([])
  const [newLacakExemptInput, setNewLacakExemptInput] = useState('')
  const [fakeGpsAllowedUserUids, setFakeGpsAllowedUserUids] = useState([])
  const [newFakeGpsInput, setNewFakeGpsInput] = useState('')
  const [navPremiumDistEnabled, setNavPremiumDistEnabled] = useState(false)
  const [navPremiumFeeDalam, setNavPremiumFeeDalam] = useState(50000)
  const [navPremiumFeeAntar, setNavPremiumFeeAntar] = useState(75000)
  const [navPremiumFeeNasional, setNavPremiumFeeNasional] = useState(100000)
  const [navPremiumExemptPhones, setNavPremiumExemptPhones] = useState([])
  const [newNavPremiumExemptPhone, setNewNavPremiumExemptPhone] = useState('')
  const [loginSloganTitleId, setLoginSloganTitleId] = useState('')
  const [loginSloganSubtitleId, setLoginSloganSubtitleId] = useState('')
  const [loginSloganTitleEn, setLoginSloganTitleEn] = useState('')
  const [loginSloganSubtitleEn, setLoginSloganSubtitleEn] = useState('')
  const [loginHeroPills, setLoginHeroPills] = useState(() =>
    DEFAULT_LOGIN_HERO_PILLS.map((p) => ({ ...p }))
  )
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [message, setMessage] = useState('')
  const [messageType, setMessageType] = useState('success')

  useEffect(() => {
    loadSettings()
  }, [])

  async function loadSettings() {
    try {
      const [settingsSnap, contactSnap, minVersionSnap, exemptSnap, maintenanceSnap, lacakExemptSnap, fakeGpsSnap] = await Promise.all([
        getDoc(doc(db, 'app_config', 'settings')),
        getDoc(doc(db, 'app_config', 'admin_contact')),
        getDoc(doc(db, 'app_config', 'min_version')),
        getDoc(doc(db, 'app_config', 'contribution_exempt_drivers')),
        getDoc(doc(db, 'app_config', 'maintenance')),
        getDoc(doc(db, 'app_config', 'lacak_exempt_users')),
        getDoc(doc(db, 'app_config', 'fake_gps_allowed_users')),
      ])

      if (settingsSnap.exists() && settingsSnap.data()) {
        const d = settingsSnap.data()
        if (d.tarifPerKm != null) setTarifPerKm(d.tarifPerKm)
        if (d.violationFeeRupiah != null) setViolationFeeRupiah(d.violationFeeRupiah)
        if (d.lacakDriverFeeRupiah != null) setLacakDriverFeeRupiah(d.lacakDriverFeeRupiah)
        if (d.lacakBarangDalamProvinsiRupiah != null) setLacakBarangDalamProvinsiRupiah(d.lacakBarangDalamProvinsiRupiah)
        if (d.lacakBarangBedaProvinsiRupiah != null) setLacakBarangBedaProvinsiRupiah(d.lacakBarangBedaProvinsiRupiah)
        if (d.lacakBarangLebihDari1ProvinsiRupiah != null) setLacakBarangLebihDari1ProvinsiRupiah(d.lacakBarangLebihDari1ProvinsiRupiah)
        if (d.minKontribusiTravelRupiah != null) setMinKontribusiTravelRupiah(d.minKontribusiTravelRupiah)
        if (d.maxKontribusiTravelPerRuteRupiah != null) setMaxKontribusiTravelPerRuteRupiah(d.maxKontribusiTravelPerRuteRupiah)
        if (d.tarifKontribusiTravelDalamProvinsiPerKm != null) setTarifKontribusiTravelDalamProvinsiPerKm(d.tarifKontribusiTravelDalamProvinsiPerKm)
        if (d.tarifKontribusiTravelBedaProvinsiPerKm != null) setTarifKontribusiTravelBedaProvinsiPerKm(d.tarifKontribusiTravelBedaProvinsiPerKm)
        if (d.tarifKontribusiTravelBedaPulauPerKm != null) setTarifKontribusiTravelBedaPulauPerKm(d.tarifKontribusiTravelBedaPulauPerKm)
        if (d.tarifBarangDalamProvinsiPerKm != null) setTarifBarangDalamProvinsiPerKm(d.tarifBarangDalamProvinsiPerKm)
        if (d.tarifBarangBedaProvinsiPerKm != null) setTarifBarangBedaProvinsiPerKm(d.tarifBarangBedaProvinsiPerKm)
        if (d.tarifBarangLebihDari1ProvinsiPerKm != null) setTarifBarangLebihDari1ProvinsiPerKm(d.tarifBarangLebihDari1ProvinsiPerKm)
        if (d.tarifBarangDokumenDalamProvinsiPerKm != null) setTarifBarangDokumenDalamProvinsiPerKm(d.tarifBarangDokumenDalamProvinsiPerKm)
        if (d.tarifBarangDokumenBedaProvinsiPerKm != null) setTarifBarangDokumenBedaProvinsiPerKm(d.tarifBarangDokumenBedaProvinsiPerKm)
        if (d.tarifBarangDokumenLebihDari1ProvinsiPerKm != null) setTarifBarangDokumenLebihDari1ProvinsiPerKm(d.tarifBarangDokumenLebihDari1ProvinsiPerKm)
        setNavPremiumDistEnabled(d.driverNavPremiumDistancePricingEnabled === true)
        if (d.driverNavPremiumFeeDalamProvinsiRupiah != null) setNavPremiumFeeDalam(Number(d.driverNavPremiumFeeDalamProvinsiRupiah))
        if (d.driverNavPremiumFeeAntarProvinsiRupiah != null) setNavPremiumFeeAntar(Number(d.driverNavPremiumFeeAntarProvinsiRupiah))
        if (d.driverNavPremiumFeeNasionalRupiah != null) setNavPremiumFeeNasional(Number(d.driverNavPremiumFeeNasionalRupiah))
        const npex = d.driverNavPremiumExemptPhones
        setNavPremiumExemptPhones(Array.isArray(npex) ? npex.map((p) => String(p).trim()).filter(Boolean) : [])
        setLoginSloganTitleId(d.loginSloganTitleId != null ? String(d.loginSloganTitleId) : '')
        setLoginSloganSubtitleId(d.loginSloganSubtitleId != null ? String(d.loginSloganSubtitleId) : '')
        setLoginSloganTitleEn(d.loginSloganTitleEn != null ? String(d.loginSloganTitleEn) : '')
        setLoginSloganSubtitleEn(d.loginSloganSubtitleEn != null ? String(d.loginSloganSubtitleEn) : '')
        if (Array.isArray(d.loginHeroPills) && d.loginHeroPills.length > 0) {
          const merged = DEFAULT_LOGIN_HERO_PILLS.map((def, i) => {
            const p = d.loginHeroPills[i]
            if (!p || typeof p !== 'object') return { ...def }
            const icon = LOGIN_HERO_ICON_KEYS.includes(String(p.icon || ''))
              ? String(p.icon)
              : def.icon
            return {
              icon,
              labelId: p.labelId != null ? String(p.labelId) : '',
              labelEn: p.labelEn != null ? String(p.labelEn) : '',
            }
          })
          setLoginHeroPills(merged)
        } else {
          setLoginHeroPills(DEFAULT_LOGIN_HERO_PILLS.map((p) => ({ ...p })))
        }
      }

      if (contactSnap.exists() && contactSnap.data()) {
        const d = contactSnap.data()
        setAdminEmail(d.adminEmail ?? '')
        setAdminWhatsApp(d.adminWhatsApp ?? '')
        setAdminInstagram(d.adminInstagram ?? '')
      } else {
        setAdminEmail('CodeAnalytic9@gmail.com')
        setAdminWhatsApp('6282218115551')
      }

      if (minVersionSnap.exists() && minVersionSnap.data()) {
        setMinVersion(minVersionSnap.data().minVersion ?? '')
      }

      if (exemptSnap.exists() && exemptSnap.data()) {
        const uids = exemptSnap.data().driverUids
        setExemptDriverUids(Array.isArray(uids) ? uids : [])
      }

      if (maintenanceSnap.exists() && maintenanceSnap.data()) {
        const d = maintenanceSnap.data()
        setMaintenanceEnabled(d.enabled === true)
        setMaintenanceMessage(d.message ?? '')
      }

      if (lacakExemptSnap.exists() && lacakExemptSnap.data()) {
        const uids = lacakExemptSnap.data().userUids
        setLacakExemptUserUids(Array.isArray(uids) ? uids : [])
      }
      if (fakeGpsSnap.exists() && fakeGpsSnap.data()) {
        const uids = fakeGpsSnap.data().userUids
        setFakeGpsAllowedUserUids(Array.isArray(uids) ? uids : [])
      }
    } catch (err) {
      console.error('Settings load error:', err)
      setMessage('Gagal memuat: ' + err.message)
      setMessageType('error')
    } finally {
      setLoading(false)
    }
  }

  const handleSave = async () => {
    setMessage('')
    if (adminEmail.trim() && !isValidEmail(adminEmail)) {
      setMessage('Format email tidak valid.')
      setMessageType('error')
      return
    }
    if (adminWhatsApp.trim() && !isValidWhatsApp(adminWhatsApp)) {
      setMessage('Format WhatsApp tidak valid. Gunakan format: 6282218115551')
      setMessageType('error')
      return
    }
    if (minVersion.trim() && !isValidVersion(minVersion)) {
      setMessage('Format versi tidak valid. Contoh: 1.0.5')
      setMessageType('error')
      return
    }
    const sloganMax = 400
    const slogans = [
      loginSloganTitleId,
      loginSloganSubtitleId,
      loginSloganTitleEn,
      loginSloganSubtitleEn,
    ]
    if (slogans.some((s) => s.length > sloganMax)) {
      setMessage(`Slogan login maksimal ${sloganMax} karakter per field.`)
      setMessageType('error')
      return
    }
    for (const p of loginHeroPills) {
      if ((p.labelId || '').length > 32 || (p.labelEn || '').length > 32) {
        setMessage('Label chip halaman login maksimal 32 karakter.')
        setMessageType('error')
        return
      }
    }
    setSaving(true)
    try {
      const v = Math.min(85, Math.max(70, Number(tarifPerKm)))
      const vf = Math.max(5000, Number(violationFeeRupiah) || 5000)
      const lf = Math.max(3000, Number(lacakDriverFeeRupiah) || 3000)
      const lb1 = Math.max(10000, Number(lacakBarangDalamProvinsiRupiah) || 10000)
      const lb2 = Math.max(15000, Number(lacakBarangBedaProvinsiRupiah) || 15000)
      const lb3 = Math.max(25000, Number(lacakBarangLebihDari1ProvinsiRupiah) || 25000)
      const mkt = Math.max(0, Number(minKontribusiTravelRupiah) || 5000)
      const maxRute = Math.max(0, Number(maxKontribusiTravelPerRuteRupiah) || 30000)
      const tkt1 = Math.max(0, Number(tarifKontribusiTravelDalamProvinsiPerKm) || 90)
      const tkt2 = Math.max(0, Number(tarifKontribusiTravelBedaProvinsiPerKm) || 110)
      const tkt3 = Math.max(0, Number(tarifKontribusiTravelBedaPulauPerKm) || 140)
      const tb1 = Math.max(10, Number(tarifBarangDalamProvinsiPerKm) || 15)
      const tb2 = Math.max(10, Number(tarifBarangBedaProvinsiPerKm) || 35)
      const tb3 = Math.max(10, Number(tarifBarangLebihDari1ProvinsiPerKm) || 50)
      const td1 = Math.max(5, Number(tarifBarangDokumenDalamProvinsiPerKm) || 10)
      const td2 = Math.max(5, Number(tarifBarangDokumenBedaProvinsiPerKm) || 25)
      const td3 = Math.max(5, Number(tarifBarangDokumenLebihDari1ProvinsiPerKm) || 35)

      await setDoc(
        doc(db, 'app_config', 'settings'),
        {
          tarifPerKm: v,
          violationFeeRupiah: vf,
          lacakDriverFeeRupiah: lf,
          lacakBarangDalamProvinsiRupiah: lb1,
          lacakBarangBedaProvinsiRupiah: lb2,
          lacakBarangLebihDari1ProvinsiRupiah: lb3,
          minKontribusiTravelRupiah: mkt,
          maxKontribusiTravelPerRuteRupiah: maxRute,
          tarifKontribusiTravelDalamProvinsiPerKm: tkt1,
          tarifKontribusiTravelBedaProvinsiPerKm: tkt2,
          tarifKontribusiTravelBedaPulauPerKm: tkt3,
          contributionPriceRupiah: deleteField(), // Hapus legacy (kontribusi sekarang = jarak × tarif)
          tarifBarangDalamProvinsiPerKm: tb1,
          tarifBarangBedaProvinsiPerKm: tb2,
          tarifBarangLebihDari1ProvinsiPerKm: tb3,
          tarifBarangDokumenDalamProvinsiPerKm: td1,
          tarifBarangDokumenBedaProvinsiPerKm: td2,
          tarifBarangDokumenLebihDari1ProvinsiPerKm: td3,
          driverNavPremiumDistancePricingEnabled: navPremiumDistEnabled,
          driverNavPremiumFeeDalamProvinsiRupiah: Math.max(3000, Number(navPremiumFeeDalam) || 50000),
          driverNavPremiumFeeAntarProvinsiRupiah: Math.max(3000, Number(navPremiumFeeAntar) || 75000),
          driverNavPremiumFeeNasionalRupiah: Math.max(3000, Number(navPremiumFeeNasional) || 100000),
          driverNavPremiumExemptPhones: navPremiumExemptPhones,
          loginSloganTitleId: loginSloganTitleId.trim() || null,
          loginSloganSubtitleId: loginSloganSubtitleId.trim() || null,
          loginSloganTitleEn: loginSloganTitleEn.trim() || null,
          loginSloganSubtitleEn: loginSloganSubtitleEn.trim() || null,
          loginHeroPills: DEFAULT_LOGIN_HERO_PILLS.map((def, i) => {
            const p = loginHeroPills[i] || def
            return {
              icon: LOGIN_HERO_ICON_KEYS.includes(p.icon) ? p.icon : def.icon,
              labelId: (p.labelId || '').trim() || null,
              labelEn: (p.labelEn || '').trim() || null,
            }
          }),
        },
        { merge: true }
      )

      await setDoc(
        doc(db, 'app_config', 'admin_contact'),
        {
          adminEmail: (adminEmail || '').trim() || 'CodeAnalytic9@gmail.com',
          adminWhatsApp: (adminWhatsApp || '').trim().replace(/\D/g, '').replace(/^0/, '62') || '6282218115551',
          adminInstagram: (adminInstagram || '').trim() || null,
        },
        { merge: true }
      )

      const mv = (minVersion || '').trim()
      if (mv) {
        await setDoc(doc(db, 'app_config', 'min_version'), { minVersion: mv }, { merge: true })
      }

      await setDoc(
        doc(db, 'app_config', 'contribution_exempt_drivers'),
        { driverUids: exemptDriverUids },
        { merge: true }
      )

      await setDoc(
        doc(db, 'app_config', 'maintenance'),
        { enabled: maintenanceEnabled, message: (maintenanceMessage || '').trim() || null },
        { merge: true }
      )

      await setDoc(
        doc(db, 'app_config', 'lacak_exempt_users'),
        { userUids: lacakExemptUserUids },
        { merge: true }
      )
      await setDoc(
        doc(db, 'app_config', 'fake_gps_allowed_users'),
        { userUids: fakeGpsAllowedUserUids },
        { merge: true }
      )

      setTarifPerKm(v)
      setViolationFeeRupiah(vf)
      setLacakDriverFeeRupiah(lf)
      setLacakBarangDalamProvinsiRupiah(lb1)
      setLacakBarangBedaProvinsiRupiah(lb2)
      setLacakBarangLebihDari1ProvinsiRupiah(lb3)
      setMinKontribusiTravelRupiah(mkt)
      setTarifKontribusiTravelDalamProvinsiPerKm(tkt1)
      setTarifKontribusiTravelBedaProvinsiPerKm(tkt2)
      setTarifKontribusiTravelBedaPulauPerKm(tkt3)
      setTarifBarangDalamProvinsiPerKm(tb1)
      setTarifBarangBedaProvinsiPerKm(tb2)
      setTarifBarangLebihDari1ProvinsiPerKm(tb3)
      setTarifBarangDokumenDalamProvinsiPerKm(td1)
      setTarifBarangDokumenBedaProvinsiPerKm(td2)
      setTarifBarangDokumenLebihDari1ProvinsiPerKm(td3)
      await logAudit('settings_save', { maintenanceEnabled })
      setMessage('Berhasil disimpan.')
      setMessageType('success')
    } catch (err) {
      setMessage('Gagal: ' + err.message)
      setMessageType('error')
    } finally {
      setSaving(false)
    }
  }

  const addExemptDriver = async () => {
    const input = newExemptInput.trim()
    if (!input) return
    let uid = input
    if (looksLikePhone(input)) {
      const phoneE164 = toE164(input)
      if (!phoneE164) {
        setMessage('Format nomor telepon tidak valid.')
        setMessageType('error')
        return
      }
      const q = query(collection(db, 'users'), where('phoneNumber', '==', phoneE164))
      const snap = await getDocs(q)
      if (snap.empty) {
        setMessage('Nomor telepon tidak ditemukan.')
        setMessageType('error')
        return
      }
      uid = snap.docs[0].id
    } else {
      const userSnap = await getDoc(doc(db, 'users', uid))
      if (!userSnap.exists()) {
        setMessage('UID tidak ditemukan.')
        setMessageType('error')
        return
      }
    }
    const userSnap = await getDoc(doc(db, 'users', uid))
    if (!userSnap.exists() || userSnap.data()?.role !== 'driver') {
      setMessage('UID/No.telepon bukan driver.')
      setMessageType('error')
      return
    }
    if (exemptDriverUids.includes(uid)) {
      setMessage('Driver sudah ada di daftar.')
      setMessageType('error')
      return
    }
    setExemptDriverUids([...exemptDriverUids, uid])
    setNewExemptInput('')
    setMessage('Driver ditambahkan. Klik Simpan untuk menyimpan.')
    setMessageType('success')
  }

  const normalizeNavPremiumPhone = (raw) => {
    const e164 = toE164(String(raw || '').trim())
    return e164 ? e164.replace(/\D/g, '') : ''
  }

  const addNavPremiumExemptPhone = () => {
    const norm = normalizeNavPremiumPhone(newNavPremiumExemptPhone)
    if (!norm || norm.length < 10) {
      setMessage('Nomor tidak valid. Contoh: 6282218115551')
      setMessageType('error')
      return
    }
    if (navPremiumExemptPhones.includes(norm)) {
      setMessage('Nomor sudah ada di daftar.')
      setMessageType('error')
      return
    }
    setNavPremiumExemptPhones([...navPremiumExemptPhones, norm])
    setNewNavPremiumExemptPhone('')
    setMessage('Nomor ditambahkan. Klik Simpan untuk menyimpan ke Firestore.')
    setMessageType('success')
  }

  const removeNavPremiumExemptPhone = (phone) => {
    setNavPremiumExemptPhones(navPremiumExemptPhones.filter((p) => p !== phone))
  }

  const removeExemptDriver = async (uid) => {
    const newList = exemptDriverUids.filter((u) => u !== uid)
    setExemptDriverUids(newList)
    try {
      await setDoc(doc(db, 'app_config', 'contribution_exempt_drivers'), { driverUids: newList }, { merge: true })
      setMessage('Driver dihapus dari daftar.')
      setMessageType('success')
    } catch (err) {
      setMessage('Gagal menyimpan: ' + err.message)
      setMessageType('error')
      setExemptDriverUids(exemptDriverUids)
    }
  }

  const addUserByUidOrPhone = async (input, list, setList, setInput) => {
    if (!input.trim()) return
    let uid = input.trim()
    if (looksLikePhone(input)) {
      const phoneE164 = toE164(input)
      if (!phoneE164) {
        setMessage('Format nomor telepon tidak valid.')
        setMessageType('error')
        return
      }
      const q = query(collection(db, 'users'), where('phoneNumber', '==', phoneE164))
      const snap = await getDocs(q)
      if (snap.empty) {
        setMessage('Nomor telepon tidak ditemukan.')
        setMessageType('error')
        return
      }
      uid = snap.docs[0].id
    } else {
      const userSnap = await getDoc(doc(db, 'users', uid))
      if (!userSnap.exists()) {
        setMessage('UID tidak ditemukan.')
        setMessageType('error')
        return
      }
    }
    if (list.includes(uid)) {
      setMessage('Pengguna sudah ada di daftar.')
      setMessageType('error')
      return
    }
    setList([...list, uid])
    setInput('')
    setMessage('Pengguna ditambahkan. Klik Simpan untuk menyimpan.')
    setMessageType('success')
  }

  const addLacakExempt = () => addUserByUidOrPhone(newLacakExemptInput, lacakExemptUserUids, setLacakExemptUserUids, setNewLacakExemptInput)
  const removeLacakExempt = async (uid) => {
    const newList = lacakExemptUserUids.filter((u) => u !== uid)
    setLacakExemptUserUids(newList)
    try {
      await setDoc(doc(db, 'app_config', 'lacak_exempt_users'), { userUids: newList }, { merge: true })
      setMessage('Pengguna dihapus dari daftar.')
      setMessageType('success')
    } catch (err) {
      setMessage('Gagal menyimpan: ' + err.message)
      setMessageType('error')
      setLacakExemptUserUids(lacakExemptUserUids)
    }
  }

  const addFakeGpsAllowed = () => addUserByUidOrPhone(newFakeGpsInput, fakeGpsAllowedUserUids, setFakeGpsAllowedUserUids, setNewFakeGpsInput)
  const removeFakeGpsAllowed = async (uid) => {
    const newList = fakeGpsAllowedUserUids.filter((u) => u !== uid)
    setFakeGpsAllowedUserUids(newList)
    try {
      await setDoc(doc(db, 'app_config', 'fake_gps_allowed_users'), { userUids: newList }, { merge: true })
      setMessage('Pengguna dihapus dari daftar.')
      setMessageType('success')
    } catch (err) {
      setMessage('Gagal menyimpan: ' + err.message)
      setMessageType('error')
      setFakeGpsAllowedUserUids(fakeGpsAllowedUserUids)
    }
  }

  if (loading) {
    return (
      <div className="space-y-6">
        <div className="h-48 bg-gray-100 rounded-xl animate-pulse" />
        <div className="h-64 bg-gray-100 rounded-xl animate-pulse" />
        <div className="h-40 bg-gray-100 rounded-xl animate-pulse" />
      </div>
    )
  }

  return (
    <div className="max-w-4xl space-y-8">
      {/* Header */}
      <div className="mb-2">
        <h1 className="text-2xl font-bold text-slate-800">Pengaturan Aplikasi</h1>
        <p className="text-sm text-slate-500 mt-1">
          Konfigurasi tarif, kontak admin, dan pengecualian. Simpan setelah mengubah.
        </p>
      </div>

      {/* 1. Sistem */}
      <div className="space-y-4">
        <h2 className="text-sm font-semibold text-slate-600 uppercase tracking-wide">Sistem</h2>
        <div className="space-y-4">
      <SettingsCard title="Mode pemeliharaan" icon="🔧">
        <p className="text-sm text-gray-600 mb-4">
          Saat aktif, semua pengguna akan melihat layar pemeliharaan dan tidak bisa menggunakan aplikasi.
        </p>
        <div className="flex items-center gap-3 mb-4">
          <input
            type="checkbox"
            id="maintenanceEnabled"
            checked={maintenanceEnabled}
            onChange={(e) => setMaintenanceEnabled(e.target.checked)}
            className="rounded border-gray-300 text-orange-500 focus:ring-orange-500 h-5 w-5"
          />
          <label htmlFor="maintenanceEnabled" className="text-sm font-medium text-gray-700">
            Aktifkan mode pemeliharaan
          </label>
        </div>
        <InputField
          label="Pesan (opsional)"
          value={maintenanceMessage}
          onChange={(e) => setMaintenanceMessage(e.target.value)}
          placeholder="Aplikasi sedang dalam perbaikan. Coba lagi nanti."
          hint="Ditampilkan di layar maintenance"
        />
      </SettingsCard>

      <SettingsCard title="Versi Minimum Aplikasi" icon="📱">
        <p className="text-sm text-gray-600 mb-4">
          Pengguna dengan versi app di bawah nilai ini akan diminta update wajib sebelum menggunakan aplikasi.
        </p>
        <InputField
          label="Versi Minimum (contoh: 1.0.5)"
          value={minVersion}
          onChange={(e) => setMinVersion(e.target.value)}
          placeholder="1.0.5"
          hint="Kosongkan = tidak ada paksaan update"
        />
      </SettingsCard>

      <SettingsCard title="Slogan halaman login" icon="✨">
        <p className="text-sm text-gray-600 mb-4">
          Tampil di app (area hero di atas form login). Ganti kapan saja; kosongkan field untuk pakai teks bawaan aplikasi.
        </p>
        <div className="grid gap-4 sm:grid-cols-2">
          <TextAreaField
            label="Judul (Bahasa Indonesia)"
            rows={2}
            maxLength={400}
            value={loginSloganTitleId}
            onChange={(e) => setLoginSloganTitleId(e.target.value)}
            placeholder="Contoh: Travel & kirim barang, tanpa tebak harga."
            hint="Ton sales, singkat & meyakinkan"
          />
          <TextAreaField
            label="Judul (English)"
            rows={2}
            maxLength={400}
            value={loginSloganTitleEn}
            onChange={(e) => setLoginSloganTitleEn(e.target.value)}
            placeholder="Example: Rides & delivery with clear, fair pricing."
          />
          <TextAreaField
            label="Deskripsi (Bahasa Indonesia)"
            rows={3}
            maxLength={400}
            value={loginSloganSubtitleId}
            onChange={(e) => setLoginSloganSubtitleId(e.target.value)}
            placeholder="Satu kalimat padat: keuntungan + ajakan."
          />
          <TextAreaField
            label="Deskripsi (English)"
            rows={3}
            maxLength={400}
            value={loginSloganSubtitleEn}
            onChange={(e) => setLoginSloganSubtitleEn(e.target.value)}
            placeholder="One tight line: benefits + call to action."
          />
        </div>
        <div className="mt-6 pt-6 border-t border-slate-100">
          <p className="text-sm font-medium text-slate-700 mb-1">Chip bergaya (3) — ikon + teks</p>
          <p className="text-sm text-gray-600 mb-4">
            Di bawah deskripsi di app. Teks kosong = pakai bawaan (Travel / Lacak / Barang atau EN). Ikon sesuai tema.
          </p>
          <div className="space-y-4">
            {loginHeroPills.map((pill, i) => (
              <div
                key={i}
                className="p-4 rounded-xl bg-slate-50 border border-slate-100 grid gap-3 sm:grid-cols-3"
              >
                <div>
                  <label className="block text-xs font-medium text-gray-600 mb-1">Ikon {i + 1}</label>
                  <select
                    value={pill.icon}
                    onChange={(e) => {
                      const next = [...loginHeroPills]
                      next[i] = { ...next[i], icon: e.target.value }
                      setLoginHeroPills(next)
                    }}
                    className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white"
                  >
                    {LOGIN_HERO_ICON_OPTIONS.map((o) => (
                      <option key={o.value} value={o.value}>
                        {o.label}
                      </option>
                    ))}
                  </select>
                </div>
                <InputField
                  label={`Teks ID (chip ${i + 1})`}
                  maxLength={32}
                  value={pill.labelId}
                  onChange={(e) => {
                    const next = [...loginHeroPills]
                    next[i] = { ...next[i], labelId: e.target.value }
                    setLoginHeroPills(next)
                  }}
                  placeholder="Opsional"
                />
                <InputField
                  label={`Teks EN (chip ${i + 1})`}
                  maxLength={32}
                  value={pill.labelEn}
                  onChange={(e) => {
                    const next = [...loginHeroPills]
                    next[i] = { ...next[i], labelEn: e.target.value }
                    setLoginHeroPills(next)
                  }}
                  placeholder="Optional"
                />
              </div>
            ))}
          </div>
        </div>
      </SettingsCard>
        </div>
      </div>

      {/* 2. Bayar Pengguna (Penumpang/Pengirim) */}
      <div className="space-y-4">
        <h2 className="text-sm font-semibold text-slate-600 uppercase tracking-wide">Bayar Pengguna (Penumpang/Pengirim)</h2>
        <p className="text-sm text-slate-500 -mt-2">
          Biaya yang dibayar penumpang atau pengirim via Google Play untuk menggunakan fitur.
        </p>
        <div className="space-y-4">
      <SettingsCard title="Lacak Driver & Pelanggaran" icon="📍">
        <div className="grid gap-4 sm:grid-cols-2">
          <InputField
            label="Lacak Driver (Rp)"
            type="number"
            min={3000}
            value={lacakDriverFeeRupiah}
            onChange={(e) => setLacakDriverFeeRupiah(Number(e.target.value))}
            hint="Bayar penumpang untuk lacak posisi driver di peta. Min Rp 3.000 (batas Google Play)."
          />
          <InputField
            label="Biaya Pelanggaran (Rp)"
            type="number"
            min={5000}
            value={violationFeeRupiah}
            onChange={(e) => setViolationFeeRupiah(Number(e.target.value))}
            hint="Denda jika tidak scan barcode. Dibayar penumpang/driver via Google Play."
          />
        </div>
      </SettingsCard>

      <SettingsCard title="Lacak Barang – biaya per pesanan" icon="📦">
        <p className="text-sm text-gray-600 mb-4">
          Bayar pengirim/penerima untuk fitur Lacak Barang. Tier berdasarkan jarak (dalam provinsi / beda provinsi / lintas provinsi).
        </p>
        <div className="grid gap-4 sm:grid-cols-3">
          <InputField
            label="Dalam provinsi (Rp)"
            type="number"
            min={10000}
            value={lacakBarangDalamProvinsiRupiah}
            onChange={(e) => setLacakBarangDalamProvinsiRupiah(Number(e.target.value))}
            hint="Biaya Lacak Barang"
          />
          <InputField
            label="Beda provinsi (Rp)"
            type="number"
            min={15000}
            value={lacakBarangBedaProvinsiRupiah}
            onChange={(e) => setLacakBarangBedaProvinsiRupiah(Number(e.target.value))}
          />
          <InputField
            label="Lebih dari 1 provinsi (Rp)"
            type="number"
            min={25000}
            value={lacakBarangLebihDari1ProvinsiRupiah}
            onChange={(e) => setLacakBarangLebihDari1ProvinsiRupiah(Number(e.target.value))}
          />
        </div>
      </SettingsCard>
        </div>
      </div>

      {/* 3. Kontribusi Driver */}
      <div className="space-y-4">
        <h2 className="text-sm font-semibold text-slate-600 uppercase tracking-wide">Kontribusi Driver</h2>
        <p className="text-sm text-slate-500 -mt-2">
          Biaya yang dibayar driver ke aplikasi via Google Play. Berdasarkan jarak × tarif per km.
        </p>
        <div className="space-y-4">
      <SettingsCard title="Kontribusi Travel (Rp/km)" icon="🚗">
        <p className="text-sm text-gray-600 mb-4">
          Driver bayar kontribusi per order travel. Rumus: totalPenumpang × max(jarak × tarif/km, min). Max per rute membatasi total agar tidak memberatkan driver.
        </p>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
          <InputField
            label="Minimum per penumpang (Rp)"
            type="number"
            min={0}
            value={minKontribusiTravelRupiah}
            onChange={(e) => setMinKontribusiTravelRupiah(Number(e.target.value))}
            hint="Min kontribusi per penumpang"
          />
          <InputField
            label="Max per rute (Rp)"
            type="number"
            min={0}
            value={maxKontribusiTravelPerRuteRupiah}
            onChange={(e) => setMaxKontribusiTravelPerRuteRupiah(Number(e.target.value))}
            hint="Batas maks per rute (0 = tidak ada batas)"
          />
          <InputField
            label="Dalam provinsi (Rp/km)"
            type="number"
            min={0}
            value={tarifKontribusiTravelDalamProvinsiPerKm}
            onChange={(e) => setTarifKontribusiTravelDalamProvinsiPerKm(Number(e.target.value))}
          />
          <InputField
            label="Beda provinsi sama pulau (Rp/km)"
            type="number"
            min={0}
            value={tarifKontribusiTravelBedaProvinsiPerKm}
            onChange={(e) => setTarifKontribusiTravelBedaProvinsiPerKm(Number(e.target.value))}
          />
          <InputField
            label="Beda pulau (Rp/km)"
            type="number"
            min={0}
            value={tarifKontribusiTravelBedaPulauPerKm}
            onChange={(e) => setTarifKontribusiTravelBedaPulauPerKm(Number(e.target.value))}
          />
        </div>
      </SettingsCard>

      <SettingsCard title="Kontribusi Kirim Barang – Kargo (Rp/km)" icon="📦">
        <p className="text-sm text-gray-600 mb-4">
          Driver bayar kontribusi per km untuk order kirim barang (paket berat/dimensi besar).
        </p>
        <div className="grid gap-4 sm:grid-cols-3">
          <InputField
            label="Dalam provinsi (Rp/km)"
            type="number"
            min={10}
            value={tarifBarangDalamProvinsiPerKm}
            onChange={(e) => setTarifBarangDalamProvinsiPerKm(Number(e.target.value))}
          />
          <InputField
            label="Beda provinsi (Rp/km)"
            type="number"
            min={10}
            value={tarifBarangBedaProvinsiPerKm}
            onChange={(e) => setTarifBarangBedaProvinsiPerKm(Number(e.target.value))}
          />
          <InputField
            label="Lebih dari 1 provinsi (Rp/km)"
            type="number"
            min={10}
            value={tarifBarangLebihDari1ProvinsiPerKm}
            onChange={(e) => setTarifBarangLebihDari1ProvinsiPerKm(Number(e.target.value))}
          />
        </div>
      </SettingsCard>

      <SettingsCard title="Kontribusi Kirim Barang – Dokumen (Rp/km)" icon="📄">
        <p className="text-sm text-gray-600 mb-4">
          Driver bayar kontribusi per km untuk kirim dokumen (surat, amplop, paket kecil). Biasanya lebih murah dari kargo.
        </p>
        <div className="grid gap-4 sm:grid-cols-3">
          <InputField
            label="Dalam provinsi (Rp/km)"
            type="number"
            min={5}
            value={tarifBarangDokumenDalamProvinsiPerKm}
            onChange={(e) => setTarifBarangDokumenDalamProvinsiPerKm(Number(e.target.value))}
          />
          <InputField
            label="Beda provinsi (Rp/km)"
            type="number"
            min={5}
            value={tarifBarangDokumenBedaProvinsiPerKm}
            onChange={(e) => setTarifBarangDokumenBedaProvinsiPerKm(Number(e.target.value))}
          />
          <InputField
            label="Lebih dari 1 provinsi (Rp/km)"
            type="number"
            min={5}
            value={tarifBarangDokumenLebihDari1ProvinsiPerKm}
            onChange={(e) => setTarifBarangDokumenLebihDari1ProvinsiPerKm(Number(e.target.value))}
          />
        </div>
      </SettingsCard>

      {/* Tarif Referensi (untuk tripFareRupiah display) */}
      <SettingsCard title="Tarif Referensi" icon="📋">
        <p className="text-sm text-gray-500 mb-4">
          Tarif Per Km dipakai untuk referensi tripFareRupiah di app. Kontribusi driver dihitung dari jarak × tarif (lihat Kontribusi Travel di atas).
        </p>
        <div className="grid gap-4 sm:grid-cols-1">
          <InputField
            label="Tarif Per Km (Rp)"
            type="number"
            min={70}
            max={85}
            value={tarifPerKm}
            onChange={(e) => setTarifPerKm(Number(e.target.value))}
            hint="Referensi 70–85. Untuk hitung tripFareRupiah display."
          />
        </div>
      </SettingsCard>
        </div>
      </div>

      {/* 4. Kontak & Pengecualian */}
      <div className="space-y-4">
        <h2 className="text-sm font-semibold text-slate-600 uppercase tracking-wide">Kontak & Pengecualian</h2>
        <div className="space-y-4">

      {/* Kontak Admin */}
      <SettingsCard title="Kontak Admin" icon="📞">
        <p className="text-sm text-gray-600 mb-4">
          Ditampilkan di profil driver & penumpang (ikon Email, WhatsApp, Instagram).
        </p>
        <div className="grid gap-4 sm:grid-cols-1">
          <InputField
            label="Email"
            type="email"
            value={adminEmail}
            onChange={(e) => setAdminEmail(e.target.value)}
            placeholder="admin@example.com"
          />
          <InputField
            label="WhatsApp (contoh: 6282218115551)"
            value={adminWhatsApp}
            onChange={(e) => setAdminWhatsApp(e.target.value)}
            placeholder="6282218115551"
          />
          <InputField
            label="Instagram (username tanpa @)"
            value={adminInstagram}
            onChange={(e) => setAdminInstagram(e.target.value)}
            placeholder="traka_official"
          />
        </div>
      </SettingsCard>

      {/* Driver Bebas Kontribusi */}
      <SettingsCard title="Driver Bebas Kontribusi" icon="🎫">
        <p className="text-sm text-gray-600 mb-4">
          Driver dalam daftar ini dibebaskan dari iuran kontribusi. Tambah dengan UID atau No. telepon driver.
        </p>
        <div className="flex gap-2 mb-4">
          <input
            type="text"
            value={newExemptInput}
            onChange={(e) => setNewExemptInput(e.target.value)}
            placeholder="UID atau No. telepon driver"
            className="flex-1 px-4 py-2.5 border border-gray-200 rounded-lg focus:ring-2 focus:ring-orange-500/30 focus:border-orange-500"
            onKeyDown={(e) => e.key === 'Enter' && addExemptDriver()}
          />
          <button
            onClick={addExemptDriver}
            className="px-4 py-2.5 bg-orange-500 text-white rounded-lg hover:bg-orange-600 font-medium transition"
          >
            Tambah
          </button>
        </div>
        {exemptDriverUids.length > 0 ? (
          <ul className="space-y-2">
            {exemptDriverUids.map((uid) => (
              <li
                key={uid}
                className="flex items-center justify-between gap-3 px-4 py-2.5 bg-gray-50 rounded-lg text-sm font-mono"
              >
                <span className="text-gray-700 truncate flex-1 min-w-0">{uid}</span>
                <button
                  type="button"
                  onClick={(e) => { e.stopPropagation(); removeExemptDriver(uid); }}
                  className="shrink-0 px-3 py-1.5 text-red-600 hover:bg-red-50 rounded-lg font-medium transition text-xs"
                  title="Hapus dari daftar"
                >
                  Hapus
                </button>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-sm text-gray-500 py-2">Belum ada driver bebas kontribusi.</p>
        )}
      </SettingsCard>

      <SettingsCard title="Navigasi premium driver" icon="🧭">
        <p className="text-sm text-gray-600 mb-4">
          Tarif IAP per jenis rute (Firestore + app). ID produk Google Play:{' '}
          <code className="text-xs bg-gray-100 px-1 rounded">traka_driver_nav_premium_&lt;nominal&gt;</code>{' '}
          — nominal harus sama dengan yang dihitung app (tersnap ke langkah SKU Anda di Play Console).
        </p>
        <div className="flex items-center gap-3 mb-4">
          <input
            type="checkbox"
            id="navPremiumDistEnabled"
            checked={navPremiumDistEnabled}
            onChange={(e) => setNavPremiumDistEnabled(e.target.checked)}
            className="rounded border-gray-300 text-orange-500 focus:ring-orange-500 h-5 w-5"
          />
          <label htmlFor="navPremiumDistEnabled" className="text-sm font-medium text-gray-700">
            Tarif berdasarkan jarak rute (tier + snap) — aktifkan hanya jika Anda sudah mengatur tier di Firestore / dokumen harga
          </label>
        </div>
        <p className="text-xs text-gray-500 mb-4">
          Jika tidak dicentang, hanya dipakai kolom tarif per jenis rute di bawah (cocok untuk harga tetap seperti sebelumnya).
        </p>
        <div className="grid gap-4 sm:grid-cols-3 mb-6">
          <InputField
            label="Dalam provinsi (Rp)"
            type="number"
            min={3000}
            value={navPremiumFeeDalam}
            onChange={(e) => setNavPremiumFeeDalam(Number(e.target.value))}
          />
          <InputField
            label="Antar provinsi (Rp)"
            type="number"
            min={3000}
            value={navPremiumFeeAntar}
            onChange={(e) => setNavPremiumFeeAntar(Number(e.target.value))}
          />
          <InputField
            label="Nasional / lintas pulau (Rp)"
            type="number"
            min={3000}
            value={navPremiumFeeNasional}
            onChange={(e) => setNavPremiumFeeNasional(Number(e.target.value))}
          />
        </div>
        <p className="text-sm font-medium text-gray-800 mb-2">Pembebasan bayar (nomor HP driver)</p>
        <p className="text-sm text-gray-600 mb-3">
          Dicocokkan dengan <code className="text-xs bg-gray-100 px-1 rounded">phoneNumber</code> di profil user (format 62…).
          Bukan daftar UID &quot;bebas kontribusi&quot; — itu terpisah.
        </p>
        <div className="flex gap-2 mb-4">
          <input
            type="text"
            value={newNavPremiumExemptPhone}
            onChange={(e) => setNewNavPremiumExemptPhone(e.target.value)}
            placeholder="No. HP driver, contoh 6282218115551"
            className="flex-1 px-4 py-2.5 border border-gray-200 rounded-lg focus:ring-2 focus:ring-orange-500/30 focus:border-orange-500"
            onKeyDown={(e) => e.key === 'Enter' && addNavPremiumExemptPhone()}
          />
          <button
            type="button"
            onClick={addNavPremiumExemptPhone}
            className="px-4 py-2.5 bg-orange-500 text-white rounded-lg hover:bg-orange-600 font-medium transition"
          >
            Tambah
          </button>
        </div>
        {navPremiumExemptPhones.length > 0 ? (
          <ul className="space-y-2">
            {navPremiumExemptPhones.map((p) => (
              <li
                key={p}
                className="flex items-center justify-between gap-3 px-4 py-2.5 bg-gray-50 rounded-lg text-sm font-mono"
              >
                <span className="text-gray-700">{p}</span>
                <button
                  type="button"
                  onClick={() => removeNavPremiumExemptPhone(p)}
                  className="shrink-0 px-3 py-1.5 text-red-600 hover:bg-red-50 rounded-lg font-medium transition text-xs"
                >
                  Hapus
                </button>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-sm text-gray-500 py-2">Belum ada nomor pembebasan navigasi premium.</p>
        )}
      </SettingsCard>

      {/* Penumpang Bebas Lacak Driver & Barang */}
      <SettingsCard title="Penumpang Bebas Lacak Driver & Barang" icon="📍">
        <p className="text-sm text-gray-600 mb-4">
          Pengguna dalam daftar ini tidak perlu bayar Lacak Driver dan Lacak Barang. Untuk penumpang, pengirim, atau penerima. Tambah dengan UID atau No. telepon.
        </p>
        <div className="flex gap-2 mb-4">
          <input
            type="text"
            value={newLacakExemptInput}
            onChange={(e) => setNewLacakExemptInput(e.target.value)}
            placeholder="UID atau No. telepon user"
            className="flex-1 px-4 py-2.5 border border-gray-200 rounded-lg focus:ring-2 focus:ring-orange-500/30 focus:border-orange-500"
            onKeyDown={(e) => e.key === 'Enter' && addLacakExempt()}
          />
          <button
            onClick={addLacakExempt}
            className="px-4 py-2.5 bg-orange-500 text-white rounded-lg hover:bg-orange-600 font-medium transition"
          >
            Tambah
          </button>
        </div>
        {lacakExemptUserUids.length > 0 ? (
          <ul className="space-y-2">
            {lacakExemptUserUids.map((uid) => (
              <li
                key={uid}
                className="flex items-center justify-between gap-3 px-4 py-2.5 bg-gray-50 rounded-lg text-sm font-mono"
              >
                <span className="text-gray-700 truncate flex-1 min-w-0">{uid}</span>
                <button
                  type="button"
                  onClick={(e) => { e.stopPropagation(); removeLacakExempt(uid); }}
                  className="shrink-0 px-3 py-1.5 text-red-600 hover:bg-red-50 rounded-lg font-medium transition text-xs"
                  title="Hapus dari daftar"
                >
                  Hapus
                </button>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-sm text-gray-500 py-2">Belum ada user bebas lacak.</p>
        )}
      </SettingsCard>

      {/* Pengguna Diizinkan Fake GPS */}
      <SettingsCard title="Pengguna Diizinkan Fake GPS" icon="🎯">
        <p className="text-sm text-gray-600 mb-4">
          Pengguna dalam daftar ini boleh pakai fake GPS/lokasi palsu (untuk testing atau demo). Tambah dengan UID atau No. telepon.
        </p>
        <div className="flex gap-2 mb-4">
          <input
            type="text"
            value={newFakeGpsInput}
            onChange={(e) => setNewFakeGpsInput(e.target.value)}
            placeholder="UID atau No. telepon user"
            className="flex-1 px-4 py-2.5 border border-gray-200 rounded-lg focus:ring-2 focus:ring-orange-500/30 focus:border-orange-500"
            onKeyDown={(e) => e.key === 'Enter' && addFakeGpsAllowed()}
          />
          <button
            onClick={addFakeGpsAllowed}
            className="px-4 py-2.5 bg-orange-500 text-white rounded-lg hover:bg-orange-600 font-medium transition"
          >
            Tambah
          </button>
        </div>
        {fakeGpsAllowedUserUids.length > 0 ? (
          <ul className="space-y-2">
            {fakeGpsAllowedUserUids.map((uid) => (
              <li
                key={uid}
                className="flex items-center justify-between gap-3 px-4 py-2.5 bg-gray-50 rounded-lg text-sm font-mono"
              >
                <span className="text-gray-700 truncate flex-1 min-w-0">{uid}</span>
                <button
                  type="button"
                  onClick={(e) => { e.stopPropagation(); removeFakeGpsAllowed(uid); }}
                  className="shrink-0 px-3 py-1.5 text-red-600 hover:bg-red-50 rounded-lg font-medium transition text-xs"
                  title="Hapus dari daftar"
                >
                  Hapus
                </button>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-sm text-gray-500 py-2">Belum ada user diizinkan fake GPS.</p>
        )}
      </SettingsCard>

        </div>
      </div>

      {/* Simpan */}
      <div className="flex flex-col sm:flex-row items-start sm:items-center gap-4">
        <button
          onClick={handleSave}
          disabled={saving}
          className="px-8 py-3 bg-orange-500 text-white rounded-xl font-semibold hover:bg-orange-600 disabled:opacity-50 disabled:cursor-not-allowed transition shadow-sm"
        >
          {saving ? 'Menyimpan...' : 'Simpan Semua'}
        </button>
        {message && (
          <p className={`text-sm font-medium ${messageType === 'success' ? 'text-green-600' : 'text-red-600'}`}>
            {message}
          </p>
        )}
      </div>
    </div>
  )
}
