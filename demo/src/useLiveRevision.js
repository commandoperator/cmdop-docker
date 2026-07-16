import { useEffect, useRef, useState } from 'react'

const POLL_INTERVAL_MS = 1500
const HMR_GRACE_MS = 2500

export function useLiveRevision() {
  const [status, setStatus] = useState('connecting')
  const [lastChange, setLastChange] = useState(null)
  const revisionRef = useRef(null)
  const pendingRef = useRef(null)

  useEffect(() => {
    let active = true

    const acceptHotUpdate = () => {
      pendingRef.current = null
      setStatus('live')
      setLastChange(new Date())
    }

    if (import.meta.hot) {
      import.meta.hot.on('vite:afterUpdate', acceptHotUpdate)
      import.meta.hot.on('vite:error', () => setStatus('reconnecting'))
    }

    const poll = async () => {
      try {
        const response = await fetch('/__demo_revision', { cache: 'no-store' })
        if (!response.ok) throw new Error(`revision endpoint returned ${response.status}`)
        const { revision } = await response.json()
        if (!active) return

        setStatus('live')
        if (revisionRef.current === null) {
          revisionRef.current = revision
          return
        }

        if (revision !== revisionRef.current) {
          const pending = pendingRef.current
          if (!pending || pending.revision !== revision) {
            pendingRef.current = { revision, seenAt: Date.now() }
          } else if (Date.now() - pending.seenAt >= HMR_GRACE_MS) {
            window.location.reload()
          }
          revisionRef.current = revision
        }
      } catch {
        if (active) setStatus('reconnecting')
      }
    }

    poll()
    const timer = window.setInterval(poll, POLL_INTERVAL_MS)
    return () => {
      active = false
      window.clearInterval(timer)
      if (import.meta.hot) {
        import.meta.hot.off('vite:afterUpdate', acceptHotUpdate)
      }
    }
  }, [])

  return { status, lastChange }
}
