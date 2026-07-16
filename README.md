# Cmdop Docker Live Demo

![Cmdop Docker — live agent workspace](assets/hero-cmdop-docker.png)

Run Cmdop beside a writable Vite project and watch the browser update while the
agent edits the site. The repository is intentionally small: it is a public demo
for recordings, workshops, and safe experiments inside a container boundary.

## What starts

One Compose service owns three foreground processes:

```text
Cmdop web console + relay :63141/:63142
                 |
Cmdop machine agent (cwd /workspace/demo)
                 |
writable bind mount + Vite dev server :5173
```

`cmdop server` owns browser sessions, the relay, and the optional public reverse
tunnel. A separate foreground `cmdop agent` connects to that local relay with
its working directory set to `/workspace/demo`; its filesystem and shell tools
therefore operate on the bind-mounted site. Vite owns rendering and hot updates.
All three processes are supervised by the container entrypoint, so an unexpected
exit restarts the service instead of leaving a misleading half-working demo.

## Quick start

Requirements: Docker Engine with Compose v2.

```bash
cp .env.example .env
```

Edit `.env` and set:

- `CMDOP_API_KEY` to your Cmdop platform/inference key;
- `CMDOP_ADMIN_PASSWORD` to a private value with at least 12 characters.

Then run:

```bash
docker compose up --build
```

Open:

- demo site: <http://localhost:5173>;
- Cmdop console: <http://localhost:63141>.

Sign in to the console with `CMDOP_ADMIN_PASSWORD`. Select the connected machine
marked `THIS DEVICE` and ask it to update the demo.

Try:

```text
Open /workspace/demo. Change the hero accent from green to cobalt blue and
rewrite the headline for a robotics studio. Keep the layout responsive.
```

Vite HMR applies normal source updates. A revision endpoint provides a bounded
full-page reload fallback only when HMR fails to deliver a detected change.

## Runtime configuration

`.env.example` is the public configuration reference. Compose supplies runtime
values to the image; secrets are never Docker build arguments.

| Variable | Purpose | Default |
|---|---|---|
| `CMDOP_API_KEY` | Cmdop inference and public-edge credential | empty |
| `CMDOP_RELAY_MODE` | `auto`, `lan`, or `public` | `auto` |
| `CMDOP_PUBLIC_SUBDOMAIN` | Optional explicit `<name>.cmdop.dev`; empty in explicit `public` mode resolves the organization's provisioned address | empty |
| `CMDOP_ADMIN_PASSWORD` | Initial browser-console password, mounted as a Compose secret | required |
| `CMDOP_PERMISSIONS_MODE` | `default`, `strict`, or `bypass` | `default` |
| `CMDOP_MACHINE_NAME` | Stable relay name written during first-time config generation | `cmdop-live-demo` |
| `HOST_BIND_ADDRESS` | Host interface for the development site and local console | `127.0.0.1` |
| `DEMO_HOST_PORT` | Host port mapped to Vite | `5173` |
| `CMDOP_HOST_PORT` | Host port mapped to the console | `63141` |
| `HOST_UID`, `HOST_GID` | Runtime user identity for Linux bind mounts | `1000` |
| `VITE_USE_POLLING` | Reliable bind-mount file watching | `true` |
| `VITE_POLL_INTERVAL_MS` | Watch polling interval | `300` |
| `VITE_HMR_CLIENT_PORT` | Optional public HMR WebSocket port | empty |

Compose does not place the admin password in the container environment. It
sources the value from `.env` and mounts it at
`/run/secrets/cmdop_admin_password`. Cmdop reads it only when the durable store
has no admin credential; changing `.env` later does not rotate the password.
Use `cmdop server admin-password` explicitly for rotation.

The container ports `5173` and `63141` are stable internal contracts. Change
host ports instead of forking scripts or Compose service definitions. Both are
bound to host loopback by default. Set `HOST_BIND_ADDRESS=0.0.0.0` only when
other LAN machines deliberately need access, and protect the admin console with
the host firewall and a strong password.

## Container runtime requirements

The image uses the official `node:24-bookworm` development base. Cmdop's Linux
release is CGO-free, so gRPC, SQLite, and TLS do not require extra shared
libraries. The base already supplies the CA bundle, DNS userspace, Bash,
coreutils, curl, Git, OpenSSH, and procps; Cmdop carries its own pinned file
search runtime.

The managed public address accepts browser and agent traffic at
`https://<subdomain>.cmdop.dev` on standard HTTPS port `443`; that port belongs
to the Cmdop edge and is not published by this Compose stack. The container
origin opens an outbound mTLS connection to `proxy.cmdop.dev:4443`, so an
egress-filtering host must allow TCP `4443` in public relay mode. The
optional torrent downloader additionally needs outbound TCP and UDP to public
peers, trackers, and DHT nodes. An egress-filtering host firewall must allow
that traffic for torrent discovery and transfer to work.

No inbound torrent port is published. Cmdop currently runs its embedded
`anacrolix/torrent` client in download-only mode with uploading, seeding, UPnP,
and default port forwarding disabled; it asks the OS for an ephemeral listen
port. Publishing a conventional fixed port such as `42069` would therefore be
misleading and ineffective. If Cmdop later supports inbound peers or seeding,
the application must first expose a stable configurable listen port; Compose
can then map that same port for both TCP and UDP and the host firewall can allow
it deliberately.

The stack publishes the browser console on `63141`, but does not publish the
relay's gRPC listener on `63142`: the container-local agent and the managed
public tunnel do not need a host mapping. If separate machines must enroll
directly over the LAN, add `"63142:63142"` to the service ports and protect that
exposure with the normal Cmdop enrollment and network controls.

## Persistence and reset

The boundaries are deliberate:

- `./demo` is bind-mounted at `/workspace/demo`; agent edits are host-visible
  immediately and Vite watches the same files;
- `./config` is bind-mounted at `/home/cmdop/.config/cmdop`; startup creates
  `config/server.yaml`, which can be inspected on the host;
- `cmdop_state` mounts `/home/cmdop`, persisting the relay database, identity,
  logs, and run state while the nested config bind remains host-visible;
- `demo_node_modules` keeps container dependencies out of the host tree.

Cmdop reads the relay config at process start. Change the supported topology
through `.env`; changing `CMDOP_RELAY_MODE` or an explicitly configured
`CMDOP_PUBLIC_SUBDOMAIN` causes the entrypoint to regenerate `server.yaml` on
the next container start. An empty subdomain preserves a resolved public label.
Container startup removes only transient PID/status files from the persisted
home directory, since processes cannot survive recreation of the PID namespace.

Restart without losing state:

```bash
docker compose down
docker compose up
```

Reset Cmdop identity, generated config, and dependencies while preserving
source files:

```bash
docker compose down --volumes
rm -f config/server.yaml
docker compose up --build
```

Restore the demo source itself with Git after reviewing any changes you want to
keep.

## Updating Cmdop

The Dockerfile installs Cmdop through the unpinned official Linux installer.
Compose disables the build cache and pulls the base image, so every build
resolves the current published CLI automatically:

```bash
docker compose build
docker compose up -d
```

Use an image digest in a deployment system when exact build reproducibility is
required.

## Secret protection

The local `.env` file is ignored by Git. Enable the tracked pre-commit guard in
each clone so staged environment files, private keys, and probable API tokens
are rejected:

```bash
git config core.hooksPath .githooks
```

## Recording mode

For a disposable video environment, you may set:

```dotenv
CMDOP_PERMISSIONS_MODE=bypass
```

This removes normal tool approval prompts. It allows the agent to execute
commands inside the container and modify `./demo`. Do not combine it with extra
host mounts, SSH keys, cloud credentials, or a Docker socket.

## Public deployment

The same container can become a Cmdop public relay. To reuse the managed address
already provisioned for the organization behind `CMDOP_API_KEY`, set:

```dotenv
CMDOP_RELAY_MODE=public
CMDOP_PUBLIC_SUBDOMAIN=
```

The installed Go CLI resolves the address from the platform before writing
`server.yaml`. To request a specific available label instead, set it explicitly:

```dotenv
CMDOP_RELAY_MODE=public
CMDOP_PUBLIC_SUBDOMAIN=my-live-demo
```

Then restart Compose. `cmdop server` creates an outbound connection to the Cmdop
edge and serves its console at the resolved or requested address, for example:

```text
https://my-live-demo.cmdop.dev
```

`auto`, the default, selects public mode whenever `CMDOP_PUBLIC_SUBDOMAIN` is
non-empty and otherwise stays on LAN. The entrypoint calls the installed CLI's
own `cmdop server create --no-prompt`; this keeps generated YAML aligned with
the exact Cmdop version in the image. Explicit `public` mode with an empty label
asks the platform for the organization's existing address. If none has been
provisioned, startup stops with an actionable error instead of inventing a DNS
label. It preserves an existing config while its mode and explicit public
subdomain match `.env`, and regenerates it with `--force` when either requested
value changes.

The generated public config contains the address and subdomain but no platform
key. At runtime `cmdop server` resolves `CMDOP_ROUTER_API_KEY` in memory for both
inference and edge registration.

The Cmdop edge exposes the relay console, not the Vite port. To make the demo
site itself remotely visible, place an authenticated TLS reverse proxy or tunnel
in front of port 5173. For a temporary remote demo:

- place an authenticated TLS reverse proxy in front of both published ports;
- forward WebSocket upgrade headers to Vite;
- set `VITE_HMR_CLIENT_PORT` when the public WebSocket port differs from the
  browser page port;
- keep the Cmdop admin password private;
- keep `.env` and the Cmdop state volume private.

Do not expose this Compose stack as a hardened production website. Build the
Vite application and serve `demo/dist` from a production web server when live
editing is not required.

## Troubleshooting

Inspect both process logs:

```bash
docker compose logs -f demo
```

Check both health surfaces:

```bash
curl -fsS http://localhost:5173/
curl -fsS http://localhost:63141/health
```

If dependencies changed, restart the service. The entrypoint compares
`package-lock.json` with the named volume and runs `npm ci` only when needed.

If Linux bind-mounted files are not writable, set `HOST_UID` and `HOST_GID` in
`.env` to the output of `id -u` and `id -g`, then rebuild.

## License

Apache License 2.0. See [LICENSE](LICENSE).
