/**
 * Helper untuk ekspor data ke CSV.
 * @param {Array<Object>} data - Array of objects
 * @param {string} filename - Nama file tanpa .csv
 */
export function downloadCsv(data, filename) {
  if (!data || data.length === 0) {
    alert('Tidak ada data untuk diekspor.')
    return
  }
  const headers = Object.keys(data[0])
  const escape = (v) => {
    if (v == null) return ''
    const s = String(v)
    if (s.includes(',') || s.includes('"') || s.includes('\n')) {
      return `"${s.replace(/"/g, '""')}"`
    }
    return s
  }
  const rows = [
    headers.join(','),
    ...data.map((row) => headers.map((h) => escape(row[h])).join(',')),
  ]
  const csv = rows.join('\n')
  const blob = new Blob(['\ufeff' + csv], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `${filename}_${new Date().toISOString().slice(0, 10)}.csv`
  a.click()
  URL.revokeObjectURL(url)
}
