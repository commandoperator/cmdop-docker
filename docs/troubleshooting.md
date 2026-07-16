# Troubleshooting

## Symptom map

| Symptom | Most likely layer | Start here |
|---|---|---|
| `localhost:8080` does not load | Vite or its host port | `docker compose ps` and site logs |
| Console loads but no machine is online | Cmdop agent enrollment | current container logs and machine ID |
| Agent says it cannot find `src/` | workspace binding or stale CLI | `CMDOP_AGENT_CWD`, instructions, and CLI version |
| `router.cmdop.com ... i/o timeout` | container egress, DNS, VPN, or router | router connectivity checks below |
| Public `*.cmdop.dev` address fails | provisioning or outbound tunnel | public relay checks below |
| Changes exist but no local commit appears | instructions or failed verification | isolated Git history and `AGENTS.md` |

## First checks

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

## Colima loses outbound networking

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

## Agent is offline or stale after recreation

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

## Agent does not see project instructions

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

## Agent sees the project but a turn still fails

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

## Warnings that are usually non-fatal

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

## Agent changed the site but did not commit

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

## Linux bind-mount permissions

Set `HOST_UID` and `HOST_GID` in `.env` to the output of `id -u` and `id -g`,
then rebuild the image.

## Local commits work but GitHub push does not

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

## Public relay does not connect

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
