import { useState } from 'react'
import { siteContent, links } from './siteContent'
import { useLiveRevision } from './useLiveRevision'
import { consoleURL } from './config'
import { BrandMark } from './BrandMark'

function LiveDot() {
  const { status, lastChange } = useLiveRevision()
  const live = status === 'live'
  const title = live
    ? lastChange
      ? `Live — last change ${lastChange.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`
      : 'Live — watching the workspace'
    : 'Reconnecting to the dev server'

  return (
    <span className={`dot dot--${live ? 'live' : 'off'}`} role="status" aria-live="polite">
      <span className="dot__light" aria-hidden="true" />
      <span className="dot__label">{live ? 'Live' : 'Reconnecting'}</span>
      <span className="sr-only">{title}</span>
    </span>
  )
}

function Prompt({ text }) {
  const [copied, setCopied] = useState(false)

  async function copy() {
    try {
      await navigator.clipboard.writeText(text)
      setCopied(true)
      window.setTimeout(() => setCopied(false), 1600)
    } catch {
      setCopied(false)
    }
  }

  return (
    <button className="prompt" type="button" onClick={copy}>
      <span className="prompt__text">{text}</span>
      <span className="prompt__action">{copied ? 'Copied' : 'Copy'}</span>
    </button>
  )
}

export default function App() {
  return (
    <>
      <header className="nav">
        <div className="nav__inner shell">
          <a className="brand" href="#top">
            <span className="brand__mark" aria-hidden="true">
              <BrandMark />
            </span>
            <span className="brand__name">{siteContent.brand}</span>
          </a>
          <nav className="nav__links">
            <LiveDot />
            <a href={links.docs} target="_blank" rel="noreferrer">
              Docs
            </a>
            <a href={links.github} target="_blank" rel="noreferrer">
              GitHub
            </a>
            <a className="btn btn--primary" href={consoleURL()} target="_blank" rel="noreferrer">
              Console
            </a>
          </nav>
        </div>
      </header>

      <main id="top">
        <section className="hero shell">
          <p className="badge">{siteContent.badge}</p>
          <h1>{siteContent.headline}</h1>
          <p className="lede">{siteContent.intro}</p>
          <div className="hero__actions">
            <a className="btn btn--primary btn--lg" href={consoleURL()} target="_blank" rel="noreferrer">
              {siteContent.primaryAction}
            </a>
            <a className="btn btn--lg" href={links.github} target="_blank" rel="noreferrer">
              {siteContent.secondaryAction}
            </a>
          </div>
        </section>

        <section className="block shell">
          <h2>{siteContent.channelsTitle}</h2>
          <p className="block__intro">{siteContent.channelsIntro}</p>
          <ul className="cards">
            {siteContent.channels.map((channel) => (
              <li className="card" key={channel.name}>
                <h3>{channel.name}</h3>
                <p>{channel.body}</p>
              </li>
            ))}
          </ul>
        </section>

        <section className="block shell">
          <h2>{siteContent.promptsTitle}</h2>
          <p className="block__intro">{siteContent.promptsIntro}</p>
          <div className="prompts">
            {siteContent.prompts.map((prompt) => (
              <Prompt key={prompt} text={prompt} />
            ))}
          </div>
          <p className="note">{siteContent.sourceNote}</p>
        </section>
      </main>

      <footer className="footer">
        <div className="footer__inner shell">
          <span className="footer__brand">
            <span className="brand__mark" aria-hidden="true">
              <BrandMark />
            </span>
            {siteContent.footer}
          </span>
          <nav className="footer__links">
            {siteContent.footerLinks.map((link) => (
              <a key={link.href} href={link.href} target="_blank" rel="noreferrer">
                {link.label}
              </a>
            ))}
          </nav>
        </div>
      </footer>
    </>
  )
}
