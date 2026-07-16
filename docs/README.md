# Documentation

Start with the root [README](../README.md). It contains the shortest path from
an empty machine to a live-editing site. Use these pages when you need to
understand or change one part of the setup:

| Page | Use it for |
|---|---|
| [Architecture](architecture.md) | Processes, ports, workspace binding, and the image layout |
| [Configuration](configuration.md) | Environment variables, volumes, resets, and permissions |
| [Git and GitHub](git-and-github.md) | Automatic local commits and optional publishing |
| [Deployment](deployment.md) | Public relay mode, firewall rules, and site exposure |
| [Troubleshooting](troubleshooting.md) | Copy-paste diagnostics and known failure modes |

## Safe support bundle

These commands report useful runtime facts without printing `.env`, the admin
password, or the Cmdop API key:

```bash
docker compose ps
docker compose logs --tail=200 demo
docker compose exec demo sh -lc \
  'cmdop version; printf "agent_cwd=%s\n" "$CMDOP_AGENT_CWD"; pwd'
docker compose exec demo git status --short
curl -fsS http://localhost:8080/ >/dev/null && echo "site: ok"
curl -fsS http://localhost:63141/health >/dev/null && echo "console: ok"
```

When asking for help, include that output, the host OS, Docker runtime and
version, and whether the failure affects the site, the console, or only an agent
response. Never paste `.env`, `docker compose config`, authentication cookies,
private configuration, or complete request headers into an issue.
