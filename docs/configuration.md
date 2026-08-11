# Configuration and persistence

> **Applies to both examples.** Where a setting is demo-only, it says so.

`.env.example` is the public configuration reference. Copy it to `.env`; that
file is ignored by Git. Compose passes runtime settings to the image and never
uses secrets as Docker build arguments.

| Variable | Purpose | Default |
|---|---|---|
| `CMDOP_API_KEY` | Cmdop inference and public-edge credential | empty |
| `CMDOP_RELAY_MODE` | `auto`, `lan`, or `public` | `auto` |
| `CMDOP_PUBLIC_SUBDOMAIN` | Explicit `<name>.cmdop.dev` label — pin one per machine; empty in `public` mode reuses the organization's provisioned address, which is only safe for the org's single public machine (two machines adopting one address displace each other at the edge) | empty |
| `CMDOP_ADMIN_PASSWORD` | Initial browser-console password | required |
| `CMDOP_PERMISSIONS_MODE` | `default`, `strict`, or `bypass` | `default` |
| `CMDOP_AGENT_CWD` | Mounted workspace used by machine-agent chats | `/workspace/demo` |
| `CMDOP_MACHINE_NAME` | Relay machine name | `cmdop-live-demo` |
| `CMDOP_GIT_AUTHOR_NAME` | Author name for site commits | `Cmdop Agent` |
| `CMDOP_GIT_AUTHOR_EMAIL` | Author email for site commits | `agent@cmdop.local` |
| `HOST_BIND_ADDRESS` | Host interface for site and console | `127.0.0.1` |
| `DEMO_HOST_PORT` | Host port mapped to Vite | `8080` |
| `CMDOP_HOST_PORT` | Host port mapped to the console | `63141` |
| `HOST_UID`, `HOST_GID` | Runtime identity for Linux bind mounts | `1000` |
| `CMDOP_BROWSER` | Build-time: install headless Chromium for the agent's browser tools; `0` builds a slimmer image without them | `1` |
| `CMDOP_CLAUDE_CODE` | Build-time: install the Claude Code CLI; `0` leaves it out | `1` |
| `CMDOP_CODEX` | Build-time: install the Codex CLI; `0` leaves it out | `1` |
| `CMDOP_CODEX_SANDBOX` | `auto` probes bubblewrap at startup and picks `workspace-write` or `danger-full-access`; pin to `read-only`, `workspace-write`, or `danger-full-access` to decide yourself — see [coding agents](coding-agents.md#the-codex-sandbox) | `auto` |
| `VITE_USE_POLLING` | Reliable bind-mount watching | `true` |
| `VITE_POLL_INTERVAL_MS` | Watch polling interval | `300` |
| `VITE_HMR_CLIENT_PORT` | Optional public HMR WebSocket port | empty |

## Adding Cmdop to your own container

This repository no longer carries an agent service. Putting Cmdop in a
container you already have needs nothing from here — two lines in your own
`Dockerfile`:

```dockerfile
COPY --from=markolofsen/cmdop:latest /cmdop /usr/local/bin/cmdop
ENTRYPOINT ["cmdop", "sidecar", "--"]
```

The image is [markolofsen/cmdop](https://hub.docker.com/r/markolofsen/cmdop).
An installer line (`RUN curl -fsSL https://install.cmdop.com | sh -s -- --prefix=/usr/local/bin`)
does the same job without a registry, if you prefer a build-time fetch.

`cmdop sidecar` starts the agent in the background and execs your command, so
your process keeps PID 1. Enrolment reads `CMDOP_JOIN_KEY` (or
`CMDOP_JOIN_KEY_FILE` for a mounted secret) and `CMDOP_SERVER_URL` from that
container's environment; name it with `CMDOP_MACHINE_NAME`. See the
[`examples/simple`](../examples/simple).

## Storage boundaries

- `./demo` is the host-visible editable site.
- `./config` contains the generated Cmdop configuration.
- `./agents` holds the Claude Code and Codex logins — **credential material**,
  git-ignored, shared by both services. See [coding agents](coding-agents.md).
- `cmdop_state` persists the relay database, identity, and logs.
- `demo_git` persists the site's isolated Git history.
- `demo_node_modules` keeps Linux dependencies out of the host tree.

On startup the entrypoint removes only transient PID and status files. Those
files cannot remain valid after Docker recreates the process namespace.
The Cmdop executable lives at `/opt/cmdop/bin/cmdop`, outside `cmdop_state`, so
rebuilding the image cannot be masked by an older binary in the persistent home.
During migration the entrypoint removes only the obsolete
`/home/cmdop/.local/bin/cmdop`; user state and configuration remain untouched.

Restart without losing state:

```bash
docker compose down
docker compose up
```

Reset generated state and Git history while preserving the host source files:

```bash
docker compose down --volumes
rm -f config/server.yaml
docker compose up --build
```

This is destructive for Cmdop identity, chat history, and the isolated demo Git
history. Copy anything you need from the volumes before running it. A normal
`docker compose restart demo` preserves all of that state.

`--volumes` does not reach `./agents`, `./config`, or `./demo`: those are host
directories, not volumes. Your Claude Code and Codex logins therefore survive
the reset above, which is the point of keeping them out of `cmdop_state`.

## Permissions and secret protection

Keep `CMDOP_PERMISSIONS_MODE=default` for normal approval prompts. For an
isolated recording only, `bypass` removes tool approvals. Never combine bypass
mode with a Docker socket, broad host mounts, personal SSH keys, or cloud
credentials.

Enable the repository's tracked pre-commit secret guard once per clone:

```bash
git config core.hooksPath .githooks
```
