# Claude Code and Codex

> **Applies to both examples.** Where a setting is demo-only, it says so.

The image ships both CLIs, so a container has a coding agent the moment it
boots. You sign in once, from inside the container, with the subscription you
already have. No API key is involved and none belongs in this repository.

| CLI | Command | Executable | State directory |
|---|---|---|---|
| Claude Code | `claude` | `/opt/cmdop/agents/bin/claude` | `/home/cmdop/agents/claude` |
| Codex | `codex` | `/opt/cmdop/agents/bin/codex` | `/home/cmdop/agents/codex` |

**They are installed at first boot, not baked into the image.** That keeps
~770 MB out of it — measured — and costs about 7 seconds on the first start,
once: a restart finds them already there and skips.

They land in `/opt/cmdop/agents`, owned by the runtime user, and deliberately
**not** under `/home/cmdop`, which is a volume. A binary installed into a volume
is seeded once and then outlives every image rebuild — the stale-executable trap
this image already unwound for Cmdop itself.

If the install fails (no network, npm hiccup) the container still starts: the
stand is a relay, an agent and a live site, and two optional CLIs must not stop
any of it. The entrypoint says what failed and how to retry.

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

Each start installs `@latest`, so a container recreate is the update:

```bash
docker compose up -d --force-recreate demo
```

No rebuild needed — the CLIs are not in the image any more. `DISABLE_AUTOUPDATER=1`
is still set, so neither CLI tries to update itself mid-session; the boot install
is the one place a version changes, which keeps "what am I running" answerable.

> **This setting is about Claude Code and Codex only.** It has no effect on
> cmdop, which keeps auto-updating itself: its binary lives in the writable
> `/opt/cmdop/bin` and its own switch is `CMDOP_NO_AUTO_UPDATE`. The name is
> easy to read as a global kill switch — it is not.

Your login is in `./agents` and a recreate does not touch it.

Cmdop itself updates on the same principle but with one extra trap: it CAN
update in place, and a container recreate then throws that update away. See
[updating](../examples/original/README.md#updating).

## Why they are installed this way

Four decisions in the Dockerfile that look arbitrary until they are not. Each
was paid for once; none is safe to "simplify" back.

### npm, not the vendors' own installers

Both official installers are hard-wired to `$HOME` — `claude.ai/install.sh`
writes `~/.local/bin` and `~/.local/share/claude` with no prefix option — and
`$HOME` here is the persistent `cmdop_state` volume.

A binary installed into a volume is seeded **once**, at first container
creation, and then survives every later image build. That is the stale-executable
trap this image already had to unwind for Cmdop itself, which is why the
entrypoint still carries `remove_legacy_home_binary`.

Installing under `/opt/cmdop/agents` gives the split that actually works: the
executables live with the container and a recreate replaces them; the
credentials live on the host and it does not.

### `@latest`, resolved at boot

The npm packages are thin — each pulls a per-platform native binary through an
optional dependency, so nothing runs on Node at runtime — and both are unpinned.

Because the install happens at start rather than at build, `@latest` means what
it says: every fresh container gets the current release. There is no cached
layer to freeze it and no `--no-cache` rebuild to remember.

This replaced two worse options. Baking them with `no_cache: true` kept them
current but reinstalled *everything* on every build; baking them with the cache
on froze them at whatever the layer first resolved.

### `CLAUDE_CONFIG_DIR` / `CODEX_HOME`

The other half of the executables-vs-credentials split. Left alone, each CLI
scatters state across `HOME` — Claude Code writes `~/.claude` **and** a sibling
`~/.claude.json` — and none of it would be separable from the rest of the home
volume.

Both accept a redirect, so the layout is ours to choose: one directory per
agent, both under `CMDOP_AGENTS_DIR`, which Compose bind-mounts from `./agents`
as a single path. A login then lives on the host, outlives every image rebuild,
and a fourth agent tomorrow is one more subdirectory rather than one more mount.

### The install must stay after `usermod`

Not a caching concern. The `ENV` block sets `HOME=/home/cmdop` for every layer,
so npm running as root would create its cache there — and
`usermod --move-home` refuses to move onto a directory that already exists,
failing the build with a bare `exit 12`. `HOME=/root` on that `RUN` keeps the
cache out of the runtime user's home either way.

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
