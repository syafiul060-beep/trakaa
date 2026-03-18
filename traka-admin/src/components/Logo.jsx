/** Logo Traka Admin - geometric shapes (orange + teal) */
export default function Logo({ className = '', collapsed = false }) {
  if (collapsed) {
    return (
      <div className={`flex items-center justify-center ${className}`} title="Traka Admin">
        <div className="flex -space-x-0.5">
          <div className="w-2.5 h-2.5 rounded-sm bg-orange-500" />
          <div className="w-2.5 h-2.5 rounded-sm bg-teal-500" />
          <div className="w-2.5 h-2.5 rounded-sm bg-orange-400" />
          <div className="w-2.5 h-2.5 rounded-sm bg-teal-400" />
        </div>
      </div>
    )
  }
  return (
    <div className={`flex items-center gap-2 ${className}`}>
      <div className="flex -space-x-1">
        <div className="w-3 h-3 rounded-sm bg-orange-500" />
        <div className="w-3 h-3 rounded-sm bg-teal-500" />
        <div className="w-3 h-3 rounded-sm bg-orange-400" />
        <div className="w-3 h-3 rounded-sm bg-teal-400" />
      </div>
      <div>
        <span className="font-bold text-white text-lg tracking-tight">Traka</span>
        <span className="block text-[10px] text-slate-400 font-medium">Admin Panel</span>
      </div>
    </div>
  )
}
