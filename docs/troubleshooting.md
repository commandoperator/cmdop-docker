# Troubleshooting

## First checks

```bash
docker compose ps
docker compose logs -f demo
curl -fsS http://localhost:8080/
curl -fsS http://localhost:63141/health
```

The site is on host port `8080`, even though Vite reports its internal
container port `5173`. The Cmdop console is on `63141`.

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

## Linux bind-mount permissions

Set `HOST_UID` and `HOST_GID` in `.env` to the output of `id -u` and `id -g`,
then rebuild the image.

## Public relay does not connect

Public mode requires a valid `CMDOP_API_KEY`, an organization-provisioned or
available subdomain, DNS, and outbound TCP access to
`proxy.cmdop.dev:4443`. The public edge uses HTTPS `443`; the origin container
does not need an inbound `443` mapping.
