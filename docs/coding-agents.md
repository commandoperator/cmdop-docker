# Claude Code and Codex

The image ships both CLIs, so a container has a coding agent the moment it
boots. You sign in once, from inside the container, with the subscription you
already have. No API key is involved and none belongs in this repository.

| CLI | Command | Executable | State directory |
|---|---|---|---|
| Claude Code | `claude` | `/usr/local/bin/claude` | `/home/cmdop/agents/claude` |
| Codex | `codex` | `/usr/local/bin/codex` | `/home/cmdop/agents/codex` |

Both are installed from npm rather than from each vendor's own installer. The
official installers are hard-wired to `$HOME`, which here is a Docker volume —
a binary installed there is seeded once, at first container creation, and then
outlives every later image build. That is the same stale-executable trap this
image already unwound for Cmdop itself. Under `/usr/local` the executables
belong to the image and a rebuild replaces them.

## Sign in

```bash
make claude-login          # docker compose exec demo claude auth login
make codex-login           # docker compose exec demo codex login --device-auth
```

Both print a URL and wait. Open it on your own machine, approve, and paste the
code back into the terminal — which is exactly the flow you want when the
container has no browser. `--device-auth` is Codex's explicit headless mode;
Claude Code falls back to the same paste-the-code prompt on its own when its
local callback server is unreachable.

Check the result at any time:

```bash
make agents-status
```

The container also says so itself. Until each CLI has a credential, every start
logs one line:

```text
[cmdop-demo] Claude Code is installed and not signed in yet — run: make claude-login
```

The agent-mode service uses the same targets with the service named:

```bash
make codex-login SERVICE=agent
```

Both services mount the same host directory, so signing in once covers both.

## Where the login lives

Everything either CLI owns is redirected into one host directory, `./agents`,
which Compose bind-mounts at `/home/cmdop/agents`:

```text
agents/
  claude/     CLAUDE_CONFIG_DIR — .credentials.json, .claude.json, sessions, projects
  codex/      CODEX_HOME        — auth.json, config.toml
```

Left alone, each CLI scatters that state across `$HOME` — Claude Code writes
`~/.claude` *and* a sibling `~/.claude.json` — and none of it would be
separable from the rest of the home volume. Both accept a redirect, so the
layout is ours to choose, and one directory per agent makes the whole thing a
single path to mount, back up, or reset.

A login therefore survives an image rebuild, a `docker compose down`, and even
`down --volumes`, which resets Cmdop's identity but does not touch a bind
mount. To sign out for real, run `claude auth logout` / `codex logout`, or
delete the subdirectory.

> **`./agents` is key material.** It holds live OAuth tokens plus your session
> transcripts. It is git-ignored, the repository's pre-commit hook rejects any
> staged path under it, and `.dockerignore` keeps it out of image layers. Do
> not copy, zip, or share the directory — including to a colleague who wants
> "your working setup".

Enable the hook once per clone:

```bash
git config core.hooksPath .githooks
```

## The Codex sandbox

Codex sandboxes every command it runs, using bubblewrap on Linux, and
bubblewrap needs an unprivileged user namespace. A container frequently cannot
create one — Docker's default seccomp and AppArmor profiles, Docker Desktop's
LinuxKit kernel, or a host with unprivileged user namespaces disabled will all
prevent it. The failure is total rather than graceful: `bwrap` refuses and
every shell command Codex attempts fails.

`CMDOP_CODEX_SANDBOX=auto`, the default, resolves this by asking bubblewrap
directly at startup instead of guessing from a kernel version:

| Probe result | `sandbox_mode` written |
|---|---|
| bubblewrap runs | `workspace-write` |
| bubblewrap refuses | `danger-full-access` |

Full access inside the container is the honest configuration when the sandbox
is unavailable: the container is already the isolation boundary, and it is the
same boundary Cmdop's own agent works inside. It is not a reason to relax the
container — never combine it with a mounted Docker socket, broad host mounts,
or personal SSH keys.

Pin the value to decide yourself:

```dotenv
CMDOP_CODEX_SANDBOX=workspace-write
```

The result is written to `agents/codex/config.toml` **only when that file does
not exist**. Edits you make there are never overwritten; delete the file to
have the container regenerate it.

## Updates

Both CLIs auto-update themselves by default. That is disabled here
(`DISABLE_AUTOUPDATER=1`), because the executables live in a root-owned image
path the runtime user cannot write — leaving it on produces a permanent
"can't auto-update" warning and no updates. Rebuild instead:

```bash
docker compose build --no-cache demo
docker compose up -d --force-recreate demo
```

> **This setting is about Claude Code and Codex only.** It has no effect on
> cmdop, which keeps auto-updating itself: its binary lives in the writable
> `/opt/cmdop/bin` and its own switch is `CMDOP_NO_AUTO_UPDATE`. The name is
> easy to read as a global kill switch — it is not.

Compose already builds with `no_cache`, so a build resolves whatever version is
current. Your login is in `./agents` and is unaffected.

Cmdop itself updates on the same principle but with one extra trap: it CAN
update in place, and a container recreate then throws that update away. See
[updating](../README.md#updating).

## Leaving one out

Both are build-time options. Set either to `0` for a smaller image; the
container runs normally without it.

```dotenv
CMDOP_CLAUDE_CODE=1
CMDOP_CODEX=1
```

The build verifies whatever it installed — version plus the login subcommand
each flow depends on — so a broken install fails the build rather than
surfacing as `command not found` weeks later.
