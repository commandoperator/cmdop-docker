# Documentation

Operator-level detail behind the two examples. Start with the
[repository README](../README.md) — the two lines and where to put them — then
come here when you need to understand or change one part.

**Which example a page belongs to matters**, because the two are opposite ends:

| | [`examples/simple`](../examples/simple) | [`examples/original`](../examples/original) |
|---|---|---|
| the agent | rides along beside your app | drives a project |
| the relay | somewhere else — you join it | **hosted by this container** |
| in the image | the `cmdop` binary, nothing more | Node, Vite, Chromium, two coding CLIs |
| the binary | `COPY --from` the Docker Hub image | `curl install.cmdop.com` — **no registry** |

Pages tagged **original** below describe that stand, and most of what they document
(Vite, `/workspace/demo`, `docker compose exec demo`) exists only there. If you
came to put Cmdop in a container you already own, you need almost none of it —
[`examples/simple`](../examples/simple) and the three pages tagged **both**.
Read [Agent updates](agent-updates.md) before you ship an image with a `USER`
line: the two-line form is written for an image that stays root, and in one that
does not, the agent runs fine and silently stops updating.

| Page | Applies to | Use it for |
|---|---|---|
| [Configuration](configuration.md) | **both** | Environment variables, volumes, resets, permissions |
| [Coding agents](coding-agents.md) | **both** | Claude Code and Codex: signing in, where the login lives, sandboxing |
| [Agent updates](agent-updates.md) | **both** | How the in-place update works, why a `USER` line breaks it, pinning a version |
| [Architecture](architecture.md) | original | Processes, ports, workspace binding, image layout |
| [Deployment](deployment.md) | original | Public relay mode, firewall rules, site exposure |
| [Git and GitHub](git-and-github.md) | original | Automatic local commits and optional publishing |
| [Troubleshooting](troubleshooting.md) | original | Copy-paste diagnostics and known failure modes |

## Safe support bundle

These commands report useful runtime facts without printing `.env`, the admin
password, or the Cmdop API key. They assume the demo stand; for another
container, substitute its service name.

```bash
docker compose ps
docker compose logs --tail=200 demo
docker compose exec demo sh -lc \
  'cmdop version; printf "agent_cwd=%s\n" "$CMDOP_AGENT_CWD"; pwd'
docker compose exec demo git status --short
docker compose exec demo sh -lc 'claude --version; codex --version'
curl -fsS http://localhost:8080/ >/dev/null && echo "site: ok"
curl -fsS http://localhost:63141/health >/dev/null && echo "console: ok"
```

When asking for help, include that output, the host OS, Docker runtime and
version, and whether the failure affects the site, the console, or only an agent
response. Never paste `.env`, `docker compose config`, authentication cookies,
private configuration, or complete request headers into an issue. The same goes
for anything under `./agents`, which holds live Claude Code and Codex logins —
`make agents-status` reports sign-in state without printing a credential, but it
does name the signed-in account.
