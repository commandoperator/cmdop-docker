# Architecture

> **Applies to [`examples/original`](../examples/original)** — the stand that hosts its
> own relay and drives a project. An agent riding along beside your own app
> ([`examples/simple`](../examples/simple)) has none of these moving parts.

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

This stand deliberately takes the **no-registry** path: the Dockerfile fetches
the Cmdop binary with the official installer at build time
(`curl -fsSL https://install.cmdop.com | sh -s -- --prefix=/opt/cmdop/bin`),
which picks the architecture itself and verifies the download against the
release `SHA256SUMS`. That is the whole point of this example — the elegant
form is the opposite one, a cacheable
`COPY --from=markolofsen/cmdop:latest` in [`../simple`](../examples/simple).
Use the installer only when you cannot, or will not, depend on a registry:

Until 2026-08-11 this service also set `no_cache: true`. It had to: Cmdop was
installed by a `curl | sh` whose command string never changes, so a cached layer
would pin one release indefinitely while every build still reported success.
The cost was that *everything* rebuilt — Chromium, both coding CLIs, the lot —
on every single build. Copying from a published image removes the reason and
keeps the freshness, because `pull` re-resolves the tag.

Claude Code and Codex are not in the image at all — they install at first boot,
so caching cannot freeze them either. See
[coding agents](coding-agents.md#latest-resolved-at-boot).

```bash
docker compose build
docker compose up -d
```

Use a published image digest when exact production reproducibility is more
important than automatically receiving the latest release.

The binary is installed under `/opt/cmdop/bin`, outside the persistent
`/home/cmdop` volume. Container state survives recreation; stale executable
bytes do not.

## Coding agents

The Claude Code and Codex CLIs are **not** in the image: the entrypoint
installs them from npm on first boot, under `/opt/cmdop/agents`, which keeps
~770 MB out of the image and resolves the version at boot rather than freezing
it at build time. The install is never fatal — two optional coding CLIs must
not stop a relay, an agent and a live site from coming up. npm is used rather
than either vendor's installer because both installers write into `$HOME`,
which here is a volume that would outlive the image. Their state goes the other
way, redirected by `CLAUDE_CONFIG_DIR` and `CODEX_HOME` into `/home/cmdop/agents`,
a bind mount from the host `./agents`. Executables belong to the image and a
rebuild replaces them; logins belong to the host and a rebuild does not touch
them. See [coding agents](coding-agents.md).
