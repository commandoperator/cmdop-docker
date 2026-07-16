# Architecture

The Compose service runs three foreground processes:

```text
Cmdop web console + relay :63141/:63142
                 |
Cmdop machine agent (cwd /workspace/demo)
                 |
writable site + Vite dev server :5173
```

`cmdop server` owns browser sessions, the relay, and the optional public reverse
connection. A separate `cmdop agent` connects to the local relay and works in
`/workspace/demo`. Compose makes that binding explicit with
`CMDOP_AGENT_CWD=/workspace/demo`; Docker's `WORKDIR` alone does not define the
inbound agent's file sandbox. Vite renders the same files and sends hot updates
to the browser. The entrypoint supervises all three; if a required process exits,
the container exits and Compose restarts it.

The host sees the site at `127.0.0.1:8080` and the console at
`127.0.0.1:63141`. Internally, Vite remains on `5173` and the console on
`63141`. The relay gRPC listener on `63142` stays container-local because the
local agent and managed public connection do not need a host mapping.

## Live updates

The host `./demo` directory is bind-mounted at `/workspace/demo`. Agent edits
there are immediately visible to the host and Vite. Normal changes arrive over
Vite HMR; a bounded revision endpoint reloads the page only when HMR misses a
detected change.

## Image

The image uses the official `node:24-bookworm` development base. Cmdop's Linux
release is CGO-free, so gRPC, SQLite, and TLS need no extra shared libraries.
The base provides CA certificates, DNS userspace, Bash, coreutils, curl, Git,
OpenSSH, and procps. Cmdop carries its own pinned file-search runtime.

The Dockerfile installs Cmdop through the unpinned official installer. Compose
sets `pull: true` and disables the layer cache so a build resolves the current
published CLI:

```bash
docker compose build
docker compose up -d
```

Use a published image digest when exact production reproducibility is more
important than automatically receiving the latest release.

The binary is installed under `/opt/cmdop/bin`, outside the persistent
`/home/cmdop` volume. Container state survives recreation; stale executable
bytes do not.
