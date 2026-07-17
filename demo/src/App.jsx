import { useState } from 'react'
import { siteContent } from './content'
import { useLiveRevision } from './useLiveRevision'

function cmdopConsoleURL() {
  const port = import.meta.env.VITE_CMDOP_CONSOLE_PORT || '63141'
  return `${window.location.protocol}//${window.location.hostname}:${port}`
}

function LiveStatus() {
  const { status, lastChange } = useLiveRevision()
  const label = status === 'live' ? 'Live updates connected' : 'Reconnecting updates'
  const detail = lastChange
    ? `Last change ${lastChange.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`
    : 'Watching the workspace'

  return (
    <div className={`live-status live-status--${status}`} role="status" aria-live="polite">
      <span className="live-status__signal" aria-hidden="true" />
      <span>
        <strong>{label}</strong>
        <small>{detail}</small>
      </span>
    </div>
  )
}

function PromptButton({ prompt }) {
  const [copied, setCopied] = useState(false)

  async function copyPrompt() {
    try {
      await navigator.clipboard.writeText(prompt)
      setCopied(true)
      window.setTimeout(() => setCopied(false), 1800)
    } catch {
      setCopied(false)
    }
  }

  return (
    <button className="prompt" type="button" onClick={copyPrompt}>
      <span>{prompt}</span>
      <strong>{copied ? 'Copied' : 'Copy'}</strong>
    </button>
  )
}

export default function App() {
  return (
    <main>
      <header className="nav shell">
        <a className="brand" href="#top" aria-label="Cmdop Live Canvas home">
          {siteContent.brand}
        </a>
        <div className="nav__actions">
          <LiveStatus />
          <a className="console-action" href={cmdopConsoleURL()} target="_blank" rel="noreferrer">
            Open Cmdop Console
          </a>
        </div>
      </header>

      <section className="hero shell" id="top">
        <div className="hero__copy">
          <h1>{siteContent.headline} {siteContent.headlineCount > 0 && <span className="headline-count">#{siteContent.headlineCount}</span>}</h1>
          <p>{siteContent.intro}</p>
          <a className="primary-action" href="#prompts">
            {siteContent.primaryAction}
          </a>
        </div>
        <figure className="hero__visual">
          <img src="/hero-live-system.png" alt={siteContent.imageAlt} />
        </figure>
      </section>

      <section className="prompt-section shell" id="prompts">
        <div className="prompt-section__heading">
          <h2>{siteContent.sectionTitle}</h2>
          <p>{siteContent.sectionIntro}</p>
        </div>
        <div className="prompt-grid">
          {siteContent.prompts.map((prompt) => (
            <PromptButton key={prompt} prompt={prompt} />
          ))}
        </div>
      </section>

      <footer className="footer shell">
        <span>{siteContent.brand}</span>
        <p>{siteContent.footer}</p>
      </footer>
    </main>
  )
}
