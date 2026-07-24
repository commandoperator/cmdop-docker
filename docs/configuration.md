# Configuration and persistence

`.env.example` is the public configuration reference. Copy it to `.env`; that
file is ignored by Git. Compose passes runtime settings to the image and never
uses secrets as Docker build arguments.

| Variable | Purpose | Default |
|---|---|---|
| `CMDOP_API_KEY` | Cmdop inference and public-edge credential | empty |
| `CMDOP_RELAY_MODE` | `auto`, `lan`, or `public` | `auto` |
| `CMDOP_PUBLIC_SUBDOMAIN` | Optional explicit `<name>.cmdop.dev`; empty in `public` mode reuses the organization's provisioned address | empty |
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
| `VITE_USE_POLLING` | Reliable bind-mount watching | `true` |
| `VITE_POLL_INTERVAL_MS` | Watch polling interval | `300` |
| `VITE_HMR_CLIENT_PORT` | Optional public HMR WebSocket port | empty |
| `CMDOP_SERVER_URL` | Agent mode: address of the existing Cmdop server to join | empty |
| `CMDOP_ENROLL_PASSWORD` | Agent mode: fleet enrollment password from that server | empty |
| `CMDOP_SERVER_INSECURE` | Agent mode: `1` skips TLS verification for a self-signed self-hosted server | `0` |

## Agent mode

The same image can run as a plain machine agent enrolled into an existing
Cmdop server — no embedded server, no demo project, no published ports:

```bash
docker compose --profile agent up --build agent
```

Set `CMDOP_SERVER_URL` and `CMDOP_ENROLL_PASSWORD` in `.env` first (the
enrollment password comes from the target server's `/admin/enrollment` page or
its startup log). The container re-enrolls on every start — that is idempotent
and picks up a rotated password. Agent state persists in the dedicated
`cmdop_agent_state` volume; the host `./workspace` directory is the agent's
working directory. The default `docker compose up` workspace service is
unaffected.

Compose mounts the admin password as `/run/secrets/cmdop_admin_password`; it is
not placed in the container environment. Cmdop reads it only when its durable
store has no admin credential. Changing `.env` later does not rotate an
existing password. Rotate it explicitly, then restart the service:

```bash
docker compose exec demo cmdop server admin-password --reset
docker compose restart demo
```

The password command stores a hash and invalidates existing browser sessions.
`--reset` generates a value that is displayed once. `--set <value>` is also
available, but putting a real password directly on a command line may retain it
in shell history or a process listing.

## Storage boundaries

- `./demo` is the host-visible editable site.
- `./config` contains the generated Cmdop configuration.
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

## Permissions and secret protection

Keep `CMDOP_PERMISSIONS_MODE=default` for normal approval prompts. For an
isolated recording only, `bypass` removes tool approvals. Never combine bypass
mode with a Docker socket, broad host mounts, personal SSH keys, or cloud
credentials.

Enable the repository's tracked pre-commit secret guard once per clone:

```bash
git config core.hooksPath .githooks
```
