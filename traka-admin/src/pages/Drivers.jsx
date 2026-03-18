import { useState, useEffect } from 'react'
import { collection, getDocs, doc, getDoc } from 'firebase/firestore'
import { db } from '../firebase'
import { isApiEnabled } from '../config/apiConfig'
import { getDriverStatusList } from '../services/trakaApi'

export default function Drivers() {
  const [drivers, setDrivers] = useState([])
  const [usersMap, setUsersMap] = useState({})
  const [exemptUids, setExemptUids] = useState([])
  const [loading, setLoading] = useState(true)
  const [searchQuery, setSearchQuery] = useState('')

  useEffect(() => {
    async function load() {
      try {
        let driverList = []
        if (isApiEnabled) {
          const apiDrivers = await getDriverStatusList()
          driverList = apiDrivers.map((d) => ({ ...d, id: d.uid || d.id }))
        } else {
          const statusSnap = await getDocs(collection(db, 'driver_status'))
          driverList = statusSnap.docs.map((d) => ({ id: d.id, ...d.data() }))
        }

        const exemptSnap = await getDoc(doc(db, 'app_config', 'contribution_exempt_drivers'))
        const uids = [...new Set(driverList.map((d) => d.id || d.uid))]
        const exemptData = exemptSnap.exists() ? exemptSnap.data() : {}
        setExemptUids(Array.isArray(exemptData.driverUids) ? exemptData.driverUids : [])

        const usersSnap = await getDocs(collection(db, 'users'))
        const map = {}
        usersSnap.docs.forEach((d) => {
          map[d.id] = d.data()
        })
        setUsersMap(map)
        setDrivers(driverList)
      } catch (err) {
        console.error(err)
      } finally {
        setLoading(false)
      }
    }
    load()
  }, [])

  const searchLower = searchQuery.trim().toLowerCase()
  const filteredDrivers = searchLower
    ? drivers.filter((d) => {
        const u = usersMap[d.id] || {}
        const name = (u.displayName || '').toLowerCase()
        const email = (u.email || '').toLowerCase()
        const route = ((d.routeOriginText || '') + (d.routeDestText || '')).toLowerCase()
        return name.includes(searchLower) || email.includes(searchLower) || route.includes(searchLower)
      })
    : drivers

  return (
    <div className="space-y-6">
      <div className="flex justify-end">
        <input
          type="text"
          placeholder="Cari nama, email, rute..."
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="px-4 py-2 border border-gray-200 rounded-lg text-sm focus:ring-2 focus:ring-orange-500/30 focus:border-orange-500 w-full sm:w-72"
        />
      </div>
      <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="overflow-x-auto">
        <table className="w-full min-w-[500px]">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Driver</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Rute</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Kontribusi</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {filteredDrivers.map((d) => {
              const u = usersMap[d.id] || {}
              const isExempt = exemptUids.includes(d.id)
              return (
                <tr key={d.id} className="hover:bg-gray-50/50 transition">
                  <td className="px-6 py-4">
                    <div>
                      <p className="font-medium text-gray-800">{u.displayName || '-'}</p>
                      <p className="text-xs text-gray-500 truncate max-w-[200px]">{u.email || d.id}</p>
                    </div>
                  </td>
                  <td className="px-6 py-4">
                    <span
                      className={`inline-flex px-2.5 py-1 text-xs font-medium rounded-full ${
                        d.status === 'siap_kerja' ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-600'
                      }`}
                    >
                      {d.status === 'siap_kerja' ? 'Siap Kerja' : d.status || 'Tidak Aktif'}
                    </span>
                  </td>
                  <td className="px-6 py-4 text-sm text-gray-600">
                    {d.routeOriginText || '-'} → {d.routeDestText || '-'}
                  </td>
                  <td className="px-6 py-4">
                    {isExempt ? (
                      <span className="inline-flex px-2.5 py-1 text-xs font-medium bg-amber-100 text-amber-800 rounded-full">
                        Bebas
                      </span>
                    ) : (
                      <span className="text-gray-400 text-sm">-</span>
                    )}
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
        {loading && (
          <div className="p-8 text-center">
            <div className="inline-block h-8 w-8 animate-spin rounded-full border-2 border-orange-500 border-t-transparent" />
            <p className="text-sm text-gray-500 mt-2">Memuat...</p>
          </div>
        )}
        {!loading && filteredDrivers.length === 0 && (
          <p className="p-8 text-center text-gray-500">
            {searchQuery.trim() ? 'Tidak ada hasil pencarian' : 'Belum ada driver'}
          </p>
        )}
        </div>
      </div>
    </div>
  )
}
