import { useState, useEffect } from 'react'
import { getAuditLogs } from '../utils/auditLog'

const ACTION_LABELS = {
  user_edit: 'Edit User',
  cancel_deletion: 'Batalkan Penghapusan',
  settings_save: 'Simpan Settings',
  admin_cancel_order: 'Batalkan Pesanan',
  broadcast: 'Broadcast Notifikasi',
  recovery_code_generated: 'Generate Kode Recovery',
}

export default function AuditLog() {
  const [logs, setLogs] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    getAuditLogs(200).then(setLogs).finally(() => setLoading(false))
  }, [])

  if (loading) {
    return (
      <div className="flex justify-center py-12">
        <div className="h-10 w-10 animate-spin rounded-full border-4 border-orange-500 border-t-transparent" />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="px-6 py-4 border-b border-gray-100">
          <h3 className="font-semibold text-gray-800">Audit Log</h3>
          <p className="text-sm text-gray-500 mt-0.5">Riwayat aksi admin</p>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Waktu</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Admin</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Aksi</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Detail</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {logs.map((log) => (
                <tr key={log.id} className="hover:bg-gray-50/50">
                  <td className="px-6 py-4 text-sm text-gray-600">
                    {log.createdAt?.toDate?.()?.toLocaleString('id-ID') || '-'}
                  </td>
                  <td className="px-6 py-4 text-sm">{log.adminEmail || log.adminUid || '-'}</td>
                  <td className="px-6 py-4">
                    <span className="px-2 py-1 text-xs font-medium bg-gray-100 rounded">
                      {ACTION_LABELS[log.action] || log.action}
                    </span>
                  </td>
                  <td className="px-6 py-4 text-sm text-gray-600">
                    {log.details && Object.keys(log.details).length > 0
                      ? JSON.stringify(log.details)
                      : '-'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {logs.length === 0 && (
          <p className="p-8 text-center text-gray-500">Belum ada audit log</p>
        )}
      </div>
    </div>
  )
}
