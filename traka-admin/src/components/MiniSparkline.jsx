/** Mini sparkline - simple SVG line chart for card trend */
export default function MiniSparkline({ data = [], positive = true, className = '' }) {
  const points = Array.isArray(data) ? data.filter((v) => typeof v === 'number' && !Number.isNaN(v)) : []
  if (!points.length) return null
  const min = Math.min(...points)
  const max = Math.max(...points)
  const range = max - min || 1
  const w = 48
  const h = 24
  const pad = 2
  const path = points
    .map((v, i) => {
      const x = pad + (i / (points.length - 1 || 1)) * (w - pad * 2)
      const y = h - pad - ((v - min) / range) * (h - pad * 2)
      return `${i === 0 ? 'M' : 'L'} ${x} ${y}`
    })
    .join(' ')
  const color = positive ? '#22C55E' : '#EF4444'
  return (
    <svg width={w} height={h} className={className}>
      <path
        d={path}
        fill="none"
        stroke={color}
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}
