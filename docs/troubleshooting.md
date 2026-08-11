# Troubleshooting

Every failure on this page belongs to **this demo stand** — the Vite site, the
Docker host, the two coding CLIs, or this container's relay. They are the moving
parts a stand has and a plain agent does not.

If you added Cmdop to a container you already own (`cmdop sidecar`, two lines in
your own `Dockerfile`), you have none of these parts and will meet none of these
symptoms. The one page you want is
[`examples/simple`](../examples/simple).

The symptom map's middle column names the layer, and the sections below are
grouped the same way — check the layer first, then the section.

## Symptom map

| Symptom | Most likely layer | Start here |
|---|---|---|
| `localhost:8080` does not load | Vite or its host port | `docker compose ps` and site logs |
| Console loads but no machine is online | Cmdop agent enrollment | current container logs and machine ID |
| Agent says it cannot find `src/` | workspace binding or stale CLI | `CMDOP_AGENT_CWD`, instructions, and CLI version |
| Cmdop reports an older version than you expect, especially right after a recreate | an in-place update lives in the container layer, so a recreate reverts to the image's build | `cmdop version` vs the image's; rebuild to make a version durable |
| `Auto-update: ... cannot replace its own binary` every hour (older builds: `downloaded but not applied`) | the binary's directory is not writable by the runtime user | [Agent updates](agent-updates.md) |
| `router.cmdop.com ... i/o timeout` | container egress, DNS, VPN, or router | router connectivity checks below |
| Public `*.cmdop.dev` address fails | provisioning or outbound tunnel | public relay checks below |
| Changes exist but no local commit appears | instructions or failed verification | isolated Git history and `AGENTS.md` |
| `claude` or `codex` asks you to log in again | the `./agents` mount | coding-agent login checks below |
| Codex fails every command with a `bwrap` error | Codex's own sandbox | Codex sandbox checks below |

## The Docker host

### First checks

```bash
docker compose ps
docker compose logs -f demo
curl -fsS http://localhost:8080/
curl -fsS http://localhost:63141/health
```

For an issue report, prefer the
[safe support bundle](README.md#safe-support-bundle). Do not paste `.env` or
`docker compose config`: both may contain expanded credentials.

The site is on host port `8080`, even though Vite reports its internal
container port `5173`. The Cmdop console is on `63141`.

| Port | Meaning | Published by default |
|---|---|---|
| `8080` | host URL for the live site | yes, loopback |
| `5173` | Vite inside the container | mapped through `8080` |
| `63141` | Cmdop browser console and HTTP API | yes, loopback |
| `63142` | Cmdop relay gRPC listener | no, container-local |

A Vite URL with another port usually belongs to a separate host-side Vite
process, not this Compose service. Use `docker compose ps` as the authority for
the active host mappings.

If dependencies changed, restart the service. The entrypoint compares
`package-lock.json` with the dependency volume and runs `npm ci` only when
needed.

### Colima loses outbound networking

After a Mac wakes or changes Wi-Fi/VPN routes, Colima can retain stale VM
network state. Typical symptoms are:

- `docker compose build` hangs at `npm ci` or Docker image metadata;
- the macOS host can reach a URL but a container times out;
- DNS resolves inside the VM, yet outbound TCP to Docker Hub, npm, or
  `proxy.cmdop.dev:4443` cannot connect.

Compare the host and container paths:

```bash
curl -I --connect-timeout 5 https://registry-1.docker.io/v2/
docker compose exec demo curl -I --connect-timeout 5 \
  https://registry.npmjs.org/react
```

If the host works and the container times out, restart the Colima VM and retry:

```bash
colima restart
docker compose build
docker compose up -d
```

This recreates the VM network and port forwards; it does not delete Docker
volumes or the demo's Git history. Do not run `colima delete` for this symptom.

The default Compose network name and a private address such as `172.19.0.2` are
normal Docker bridge networking. Colima supplies the Linux VM on macOS; Compose
still supplies the per-project bridge inside that VM. Neither is a Cmdop public
relay address.

Docker Hub can occasionally resolve to an edge IP that is unreachable from the
VM even after npm connectivity returns. Confirm with:

```bash
colima ssh -- curl -I --connect-timeout 5 https://registry-1.docker.io/v2/
```

Retry after the route is healthy. If the problem repeatedly returns after every
sleep or network switch, update Colima/Lima or use another Docker runtime rather
than changing this project's Dockerfile.

### Linux bind-mount permissions

Set `HOST_UID` and `HOST_GID` in `.env` to the output of `id -u` and `id -g`,
then rebuild the image. This governs every bind mount, `./agents` included —
the container has to create and write its login directories there.

## This container's relay and agent

### Agent is offline or stale after recreation

The entrypoint clears persisted PID and status files before it starts Cmdop.
Check current logs and health rather than trusting an old machine row in the
console. A newly recreated container may appear with a new machine ID.

```bash
docker compose restart demo
docker compose logs --tail=200 demo
```

The console intentionally preserves offline rows as history. Compare the online
row's display name with the current container ID:

```bash
docker compose ps -q demo | cut -c1-12
```

Selecting an older offline row opens that older machine's conversation but
cannot execute a new turn.

### Cmdop version goes backwards after a recreate

Cmdop updates itself in place — from the console's update button or `cmdop
update` — and writes the new binary to `/opt/cmdop/bin`. That path is **image
content, not a volume**, so the update lives in the container's writable layer.
`--force-recreate` discards that layer, and the container comes back on
whatever release the image was built with. Nothing reports an error; the
version simply reads older than the one you installed.

```bash
docker compose exec demo cmdop version
```

Rebuild to move the image forward, then recreate:

```bash
docker compose build demo
docker compose up -d --force-recreate demo
```

The build is what matters here. `up --force-recreate` on its own never
rebuilds, so repeating it cannot fix this. Compose sets `pull: true`, which
refreshes the published image the binary is copied from, so the build picks up
the current release.

Your state is unaffected either way — the console password, machine identity
and the `./agents` logins are all in volumes or on the host, not in the layer
that was discarded. Left alone the container also self-updates again on its
own; rebuilding just stops the next recreate from undoing it.

### Public relay does not connect

Public mode requires a valid `CMDOP_API_KEY`, an organization-provisioned or
available subdomain, DNS, and outbound TCP access to
`proxy.cmdop.dev:4443`. The public edge uses HTTPS `443`; the origin container
does not need an inbound `443` mapping.

Check the requested topology and the non-secret generated fields:

```bash
docker compose exec demo sh -lc \
  'sed -n -E "/^[[:space:]]*(mode|subdomain):/p" \
  /home/cmdop/.config/cmdop/server.yaml'
docker compose exec demo getent hosts proxy.cmdop.dev
docker compose exec demo bash -lc \
  'timeout 10 bash -c "</dev/tcp/proxy.cmdop.dev/4443"'
```

Explicit `CMDOP_RELAY_MODE=public` with an empty
`CMDOP_PUBLIC_SUBDOMAIN` resolves the already-provisioned address for the
organization that issued `CMDOP_API_KEY`. A key from another account cannot
resolve or authorize that address. The free managed plan currently provides one
address per organization; recreating Docker reuses it instead of allocating a
new hostname.

The managed address exposes the Cmdop console, not the Vite site on `8080`.
Publishing the site is a separate reverse-proxy or hosting decision described
in [Deployment](deployment.md#site-exposure-is-separate).

### Warnings that are usually non-fatal

- `dbus-launch` or OS keyring unavailable: expected in a headless Linux
  container. Cmdop falls back to its encrypted file store in the persistent
  home volume.
- `Not signed in — starting locally`: the local relay and UI can run without an
  interactive account login. Agent inference still requires `CMDOP_API_KEY`.
- An old machine-key decrypt warning after recreating containers: verify that
  the current machine enrolls and becomes online. Reset volumes only if you
  deliberately want a new identity and accept losing local state.

Treat an unhealthy container, an absent online machine, repeated process exits,
or a failed `/health` request as fatal even if one of these warnings is also
present.

## The agent's view of the demo project

### Agent does not see project instructions

Confirm both the executable and the explicit workspace binding:

```bash
docker compose exec demo sh -lc 'command -v cmdop; cmdop version'
docker compose exec demo sh -lc 'echo "$CMDOP_AGENT_CWD"; pwd'
```

The command should resolve through `/usr/local/bin/cmdop` to the image-owned
`/opt/cmdop/bin/cmdop`, and the workspace should be `/workspace/demo`. An
executable under `/home/cmdop` is stale state from an old image layout; the
current entrypoint removes it when the service is recreated.

```bash
docker compose exec demo cmdop instructions --show-content
```

The output should include `/workspace/demo/AGENTS.md`. Also verify the isolated
repository:

```bash
docker compose exec demo git rev-parse --show-toplevel
docker compose exec demo git status --short
```

This behavior requires Cmdop `1.1.110` or newer. If an older or `dev` build is
reported after rebuilding, recreate the service so the entrypoint can remove
the legacy executable from the persistent home volume:

```bash
docker compose build --no-cache
docker compose up -d --force-recreate
docker compose exec demo cmdop version
```

The current command should resolve through `/usr/local/bin/cmdop` to
`/opt/cmdop/bin/cmdop`, not to `/home/cmdop/.local/bin/cmdop`.

### Agent sees the project but a turn still fails

Workspace discovery and model inference are separate stages. A stream event
such as `Loaded context · AGENTS.md` proves the project was found even if the
turn later ends with:

```text
router stream request: Post "https://router.cmdop.com/v1/chat/completions":
dial tcp ...:443: i/o timeout
```

Check DNS and HTTPS from the same container:

```bash
docker compose exec demo getent hosts router.cmdop.com
docker compose exec demo curl -I --connect-timeout 10 https://router.cmdop.com/
```

Any HTTP response proves DNS, TCP, and TLS reached the router; the status itself
may be non-successful because this probe is not an authenticated chat request.
If it times out while the same command works on the macOS host, restart Colima
or fix the VPN/firewall route. If both paths connect, retry the turn and inspect
the latest logs. Never put the API key on a diagnostic command line.

### Agent changed the site but did not commit

Inspect the isolated repository and loaded instructions:

```bash
docker compose exec demo git status --short
docker compose exec demo git log --oneline --decorate -10
docker compose exec demo cmdop instructions --show-content
```

The agent commits only after `npm run check` succeeds. A failed build, an
interrupted turn, or a router timeout can therefore leave a deliberate dirty
working tree for the next operator to inspect. It never pushes without an
explicit request and a separately configured repository-scoped credential.

### Local commits work but GitHub push does not

This is the secure default. The `demo_git` volume contains an isolated local
repository with no remote and no credentials. Confirm that distinction:

```bash
docker compose exec demo git log --oneline --decorate -10
docker compose exec demo git remote -v
```

An empty remote list does not mean automatic commits failed. Follow
[Agent commits and GitHub](git-and-github.md#optional-github-publishing) only
when the site needs publishing, and use a repository-scoped deploy key or
GitHub App credential. Never mount a personal SSH directory or copy the parent
repository's `.git` directory into the container.

## The coding CLIs

### Coding agent asks you to log in again

A login persists in the host `./agents` directory, so losing it means the
container is not reading the directory you expect. Confirm the redirect and the
mount in one shot:

```bash
docker compose exec demo sh -lc \
  'echo "$CLAUDE_CONFIG_DIR"; echo "$CODEX_HOME"; ls -la /home/cmdop/agents'
ls -la agents/
```

Both paths must sit under `/home/cmdop/agents`, and the two listings must show
the same contents. If the container's copy is empty while the host's is not, the
bind mount is missing — check that you did not remove the `./agents` line from
`compose.yaml`, and recreate the service.

If the container cannot write there, the entrypoint says so and exits:

```text
[cmdop-demo] Cannot create /home/cmdop/agents subdirectories.
```

That is the ownership problem below, applied to `./agents`.

Signing in does not sign you in for a *different project* — a second clone of
this repository has its own `./agents`. `make agents-status` reports the current state.

### Codex fails every command with a `bwrap` error

```text
bwrap: No permissions to create a new namespace, likely because the kernel
does not allow non-privileged user namespaces.
```

Codex sandboxes each command with bubblewrap, which needs an unprivileged user
namespace that most containers cannot create. `CMDOP_CODEX_SANDBOX=auto` tests
for exactly this at startup and writes `sandbox_mode = "danger-full-access"`
when the probe fails — so seeing this error means the probe's answer never
reached the config. The config is written only when absent, which is the usual
cause: an older `agents/codex/config.toml` is still in place.

```bash
docker compose exec demo sh -lc 'codex sandbox /bin/true; echo "probe=$?"'
grep sandbox_mode agents/codex/config.toml
```

A non-zero probe with `workspace-write` in the file is the mismatch. Edit the
value, or delete the file and restart to have it regenerated:

```bash
rm agents/codex/config.toml
docker compose restart demo
```

Do not answer this by loosening the container instead — `--privileged`,
`--security-opt seccomp=unconfined`, or `--cap-add SYS_ADMIN` weaken the real
boundary in order to restore a nested one. Full-access-inside-the-container is
the smaller change. See [coding agents](coding-agents.md#the-codex-sandbox).

## The demo site

### `Cannot read properties of null (reading 'useState')`

Reads like a React bug in the demo application. It is a stale Vite cache.

Vite pre-bundles dependencies into `node_modules/.vite/deps/` and serves each
with a `?v=<hash>` query. If that cache desynchronises, `react.js` and
`react-dom_client.js` arrive under *different* hashes, the page ends up with
**two React copies**, and React DOM asks a dispatcher that its React never
filled in. The dispatcher is `null`, so the first hook call throws.

The metadata answers it directly — more than one hash is the bug:

```bash
docker compose exec demo node -e "
  const m = require('/workspace/demo/node_modules/.vite/deps/_metadata.json');
  const h = new Set(Object.values(m.optimized||{}).map(v => v.browserHash||m.browserHash));
  console.log(h.size, [...h]);"
```

Fix the instance by removing the cache; Vite rebuilds it coherently on the next
start:

```bash
docker compose exec demo rm -rf /workspace/demo/node_modules/.vite
docker compose restart demo
```

**Why it desynchronises is worth knowing before you deploy this anywhere.** The
project's sources and its installed dependencies have to share one lifecycle.
This Compose file gives `node_modules` a volume of its own because `./demo` is a
host bind mount that would otherwise shadow the image's copy — correct here, and
the reason the two can drift: reset the project without the dependency volume
(or replace the image without either) and a pre-bundle cache outlives the
sources it was built from.

A server deployment that mounts the project from the image rather than the host
should **not** copy that volume across. One volume covering both keeps them in
step and makes this failure impossible.
