// One place where this app resolves its runtime settings.
//
// Values come from `import.meta.env`, which Vite populates from `.env` files AND
// from the process environment — but only for names carrying the `VITE_` prefix.
// Drop the prefix and the value simply never arrives: no error, no warning, just
// an app behaving as if it were unconfigured. Compose passes these under
// `environment:`; the prefix is what makes that work.
//
// Everything below has a default, so the app runs with no configuration at all.

/** Absolute URL of the Cmdop web console, or '' to derive it from the page. */
const CONSOLE_URL = import.meta.env.VITE_CMDOP_CONSOLE_URL || ''

/** Port the console listens on, used only when no absolute URL is given. */
const CONSOLE_PORT = import.meta.env.VITE_CMDOP_CONSOLE_PORT || '63141'

/**
 * Where "Open Cmdop Console" points.
 *
 * An absolute URL wins. Otherwise the console is assumed to sit on this page's
 * host at CONSOLE_PORT — true on a laptop, where site and console are both
 * localhost and differ only by port.
 *
 * That assumption breaks behind a reverse proxy, where the console usually has
 * its own hostname on 443, and it cannot be repaired by choosing a nicer port:
 * proxies forward a fixed set (Cloudflare's HTTPS list is 443, 2053, 2083,
 * 2087, 2096, 8443) and 63141 is in none of them. Deployments like that set
 * VITE_CMDOP_CONSOLE_URL.
 */
export function consoleURL() {
  if (CONSOLE_URL) return CONSOLE_URL
  return `${window.location.protocol}//${window.location.hostname}:${CONSOLE_PORT}`
}

export const config = {
  consoleURL,
}
