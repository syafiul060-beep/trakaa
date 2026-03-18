import { useEffect, useRef } from 'react'

/**
 * Trap focus dalam elemen (modal) agar Tab tidak keluar.
 * @param {boolean} active - Aktifkan focus trap
 * @param {React.RefObject} containerRef - Ref ke container modal
 */
export function useFocusTrap(active, containerRef) {
  const previousActiveRef = useRef(null)

  useEffect(() => {
    if (!active || !containerRef?.current) return

    const el = containerRef.current
    const focusable = el.querySelectorAll(
      'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
    )
    const first = focusable[0]
    const last = focusable[focusable.length - 1]

    const handleKeyDown = (e) => {
      if (e.key !== 'Tab') return
      if (e.shiftKey) {
        if (document.activeElement === first) {
          e.preventDefault()
          last?.focus()
        }
      } else {
        if (document.activeElement === last) {
          e.preventDefault()
          first?.focus()
        }
      }
    }

    el.addEventListener('keydown', handleKeyDown)
    first?.focus()
    return () => el.removeEventListener('keydown', handleKeyDown)
  }, [active, containerRef])
}
