// Every string this page renders. The page itself is the demo — its whole job
// is to be rewritten by an agent, so the copy lives in one file that is easy to
// find, read, and replace without touching layout.

export const links = {
  product: 'https://cmdop.com',
  docs: 'https://docs.cmdop.com/docs/deployment/docker',
  github: 'https://github.com/commandoperator/cmdop-docker',
}

export const siteContent = {
  brand: 'CMDOP',
  badge: 'Demo project',

  headline: 'This page is the demo.',
  intro:
    'A plain React and Vite app running inside the cmdop-docker container, next to a CMDOP agent that can edit it. Ask for a change and it lands here — no deploy, no restart, no editor.',

  primaryAction: 'Open the console',
  secondaryAction: 'View on GitHub',

  channelsTitle: 'Ask from wherever you are',
  channelsIntro:
    'The agent watching this directory is the same one on every surface. Any of these reaches it.',
  channels: [
    {
      name: 'The web console',
      body: 'Pick this machine, open a chat, describe the change. The console ships with the container.',
    },
    {
      name: 'Telegram, Slack, or Discord',
      body: 'Connect a private bot under Server → Bots in the console, pair yourself once, then message it like a person.',
    },
    {
      name: 'The terminal',
      body: 'Run cmdop chat on the host for the same agent, without leaving your shell.',
    },
  ],

  promptsTitle: 'Try one of these',
  promptsIntro:
    'Copy one, paste it into any of the channels above, and watch this page change.',
  prompts: [
    'Make the accent cobalt blue and tighten the hero spacing.',
    'Turn this into a launch page for a small robotics studio.',
    'Add a three-item pricing table under the prompts.',
    'Rewrite this page in Russian, keeping the layout.',
  ],

  sourceNote:
    'Everything you see comes from demo/src in the repository below. The copy is in content.js, the layout in App.jsx.',

  footer: 'A writable Vite project running beside CMDOP in Docker.',
  footerLinks: [
    { label: 'cmdop.com', href: links.product },
    { label: 'Docker docs', href: links.docs },
    { label: 'GitHub', href: links.github },
  ],
}
