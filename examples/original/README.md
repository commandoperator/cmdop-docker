# original — everything by hand, without a registry

**Coding agents edit, preview, and commit a real project.**

[Live demo](https://demo.cmdop.com) | [Run it](#run-it) | [Documentation](https://docs.cmdop.com/docs/deployment/docker)

The full loop on your machine. One Compose service starts the Cmdop server, a
scoped machine agent, an editable project, live browser preview, and persistent
Git history.

> **This is the opposite end from [`../simple`](../simple), in two ways.**
>
> *Where the binary comes from:* here it is fetched at build time with
> `curl https://install.cmdop.com` — **no registry involved**, which is the
> point. `simple` copies it out of the published Docker Hub image in two lines,
> fetches nothing during the build, and gets a cacheable layer. Use this form
> when you cannot, or will not, depend on a registry.
>
> *What the container does:* there the agent rides along beside an app you
> already own. Here it **hosts its own relay** and drives a project — three
> supervised processes and an entrypoint script to match.
>
> If you came to put Cmdop in your own container, start with `../simple`.

Use Claude Code, Codex, or another coding agent to request a change. Watch the
result appear in the browser, inspect the files, and keep the finished work as a
normal Git commit.

- **A real workspace.** The agent edits the same files you can inspect on the host.
- **Immediate feedback.** Vite HMR updates the browser as the project changes.
- **Bounded access.** The machine agent works inside the configured project directory.
- **Durable history.** Finished changes survive container recreation.
- **Agents included.** Claude Code and Codex ship in the image, ready to sign in.

**See it running first:** [demo.cmdop.com](https://demo.cmdop.com) is this
repository deployed as-is — the page you land on is the demo project below,
edited by an agent through the same loop you are about to run locally.

## Run it

You need Docker Engine with Compose v2 and a [CMDOP API key](https://my.cmdop.com).

```bash
git clone https://github.com/commandoperator/cmdop-docker.git
cd cmdop-docker/examples/original
cp .env.example .env
```

Add the required values to `.env`:

```dotenv
CMDOP_API_KEY=your_api_key
CMDOP_ADMIN_PASSWORD=choose_at_least_12_characters
```

Start the workspace:

```bash
docker compose up --build
```

| Open | Address |
|---|---|
| Live site | [localhost:8080](http://localhost:8080) |
| CMDOP console | [localhost:63141](http://localhost:63141) |

Select the connected machine in the console and try:

```text
Change the hero accent to cobalt blue and rewrite the headline for a robotics
studio. Keep it responsive.
```

## How it works

Three supervised processes form one feedback loop:

| Process | Responsibility |
|---|---|
| CMDOP server | Browser console, authenticated sessions, and relay |
| CMDOP machine agent | Agent access scoped to `/workspace/demo` |
| Vite | Immediate preview of the same writable files |

The host `./demo` directory is mounted at `/workspace/demo`. CMDOP state, Git
history, and `node_modules` use named volumes. Recreating the container keeps
that working state — but it does replace everything the image owns, the CMDOP
binary included, which is why a version moves forward on a rebuild and can move
backward on a bare recreate ([updating](#updating)).

The relay listener stays container-local by default. The site and console bind
to `127.0.0.1`, and the machine agent connects outbound. The working directory
is set explicitly with `CMDOP_AGENT_CWD`.

To adapt the stack for another project or public deployment, start with
[configuration and persistence](../../docs/configuration.md) and
[deployment and firewall guidance](../../docs/deployment.md).

## Ask from somewhere other than the console

The agent in this container is reachable from every CMDOP surface, not only the
browser console:

- **The web console** on port 63141 — included, no setup.
- **Telegram, Slack, or Discord** — connect a private bot under **Server → Bots**
  in the console, pair yourself once, then message it directly. See
  [messenger bots](https://docs.cmdop.com/docs/deployment/docker/messaging).
- **The terminal** — `docker compose exec demo cmdop chat`.

## Coding agents

Claude Code and Codex are already installed in the image. Sign in once, with
the subscription you already have — there is no API key to configure, and no
credential of yours goes into this repository:

```bash
make claude-login
make codex-login
```

Each opens its own device-code flow: approve in your browser, paste the code
back. The token is written to the git-ignored `./agents` directory on the host,
which is mounted into the container — so a login survives image rebuilds and
volume resets. Details, including how Codex's sandbox is resolved inside a
container, are in [coding agents](../../docs/coding-agents.md).

## Updating

Cmdop can update itself in place, from the console's update button or `cmdop
update`. **In a container that update is temporary.** The binary lives at
`/opt/cmdop/bin`, which is image content rather than a volume, so a self-update
is written to the container's writable layer — and the next
`up --force-recreate` discards that layer along with it. The version then reads
older than the one you installed, and nothing reports an error.

Make it stick with a build:

```bash
docker compose build demo
docker compose up -d --force-recreate demo
docker compose exec demo cmdop version
```

The build is the part that matters. `up --force-recreate` never rebuilds, so
repeating it cannot move the version forward. Compose sets `pull: true`, which
refreshes the images the build copies from — including the one carrying the
Cmdop binary — so a build resolves the current release.

Nothing of yours is at risk either way — the console password, machine identity
and your `./agents` logins live in volumes or on the host, not in the layer that
is replaced. The same applies to the coding agents, whose own auto-updaters are
deliberately off; see [coding agents](../../docs/coding-agents.md#updates).

## Add Cmdop to your own container

You do not need this stand for that — it is two lines in your own Dockerfile.
See [`../simple`](../simple), or the [repository README](../../README.md).

## Documentation

Published documentation for this stack lives at
**[docs.cmdop.com/docs/deployment/docker](https://docs.cmdop.com/docs/deployment/docker)**.
The pages in this repository are the operator-level detail behind it:

- [Architecture and process supervision](../../docs/architecture.md)
- [Configuration and persistence](../../docs/configuration.md)
- [Claude Code and Codex: login, storage, sandboxing](../../docs/coding-agents.md)
- [Agent commits and optional GitHub publishing](../../docs/git-and-github.md)
- [Public deployment, ports, and firewall](../../docs/deployment.md)
- [Troubleshooting and safe support bundle](../../docs/troubleshooting.md)

For programmatic Python and Node integrations, see
[`commandoperator/cmdop-sdk`](https://github.com/commandoperator/cmdop-sdk).

## CMDOP ecosystem

[Product](https://cmdop.com) | [Live demo](https://demo.cmdop.com) | [CMDOP for Docker](https://cmdop.com/products/docker) | [Documentation](https://docs.cmdop.com) | [SDK](https://github.com/commandoperator/cmdop-sdk) | [Download](https://cmdop.com/download)

## License

The Docker setup and demo project in this repository are licensed under the
[Apache License 2.0](../../LICENSE). CMDOP itself is distributed under its own product
terms.
