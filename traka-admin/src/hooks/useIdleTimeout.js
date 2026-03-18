import { useEffect, useRef, useCallback } from 'react'

/**
 * Hook untuk auto-logout setelah idle (tidak ada aktivitas) selama timeoutMs.
 * @param {Function} onIdle - Callback saat idle (biasanya signOut)
 * @param {number} timeoutMs - Durasi idle dalam ms (default 30 menit)
 * @param {boolean} enabled - Aktifkan idle timeout
 */
export function useIdleTimeout(onIdle, timeoutMs = 30 * 60 * 1000, enabled = true) {
  const timeoutRef = useRef(null)
  const onIdleRef = useRef(onIdle)
  onIdleRef.current = onIdle

  const reset = useCallback(() => {
    if (!enabled) return
    if (timeoutRef.current) clearTimeout(timeoutRef.current)
    timeoutRef.current = setTimeout(() => {
      onIdleRef.current?.()
    }, timeoutMs)
  }, [timeoutMs, enabled])

  useEffect(() => {
    if (!enabled) return
    const events = ['mousedown', 'keydown', 'scroll', 'touchstart']
    reset()
    events.forEach((e) => window.addEventListener(e, reset))
    return () => {
      events.forEach((e) => window.removeEventListener(e, reset))
      if (timeoutRef.current) clearTimeout(timeoutRef.current)
    }
  }, [reset, enabled])
}
