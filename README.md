<div align="center">

# CMDOP for Docker

**A complete live workspace for AI coding agents in one Compose stack.**

[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-2563eb.svg)](LICENSE)
[![Docker Compose](https://img.shields.io/badge/Docker-Compose-2496ed?logo=docker&logoColor=white)](compose.yaml)
[![CMDOP](https://img.shields.io/badge/CMDOP-cmdop.com-111827)](https://cmdop.com/products/docker)

[Run the demo](#quick-start) | [How it works](#how-it-works) | [Documentation](docs/README.md) | [cmdop.com](https://cmdop.com)

</div>

![Claude Code and Codex connect through CMDOP in Docker to machine agents, a writable workspace, live preview and Git commits](assets/cmdop-docker-workflow.png)

`cmdop-docker` is the fastest way to see the full CMDOP loop working locally.
Claude Code, Codex, or another coding agent sends an instruction. CMDOP gives the
agent a bounded writable workspace, streams the result into a live browser
preview, and records the finished change in Git.

The repository contains the Docker setup and the editable demo project. The
CMDOP binary is installed from the official distribution during the image build.

## Quick start

You need Docker Engine with Compose v2 and a [CMDOP API key](https://my.cmdop.com).

```bash
git clone https://github.com/commandoperator/cmdop-docker.git
cd cmdop-docker
cp .env.example .env
```

Set these required values in `.env`:

```dotenv
CMDOP_API_KEY=your_api_key
CMDOP_ADMIN_PASSWORD=choose_at_least_12_characters
```

Start the workspace:

```bash
docker compose up --build
```

Open:

- Live site: [http://localhost:8080](http://localhost:8080)
- CMDOP console: [http://localhost:63141](http://localhost:63141)

Select the connected machine and try:

```text
Change the hero accent to cobalt blue and rewrite the headline for a robotics
studio. Keep it responsive.
```

## How it works

```text
Claude Code / Codex
        |
        v
CMDOP server + relay in Docker
        |
        v
Machine agent in /workspace/demo
        |
        +--> edits files --> Vite HMR --> live browser preview
        |
        +--> records the finished change in local Git history
```

The Compose service runs three supervised processes:

| Process | Responsibility |
|---|---|
| CMDOP server | Browser console, authenticated sessions and relay |
| CMDOP machine agent | Agent access scoped to `/workspace/demo` |
| Vite | Immediate preview of the same writable files |

The demo source is bind-mounted from `./demo`. CMDOP state, Git history and
`node_modules` use named volumes, so normal container recreation does not erase
the workspace state.

![CMDOP editing the bundled live site](assets/hero-cmdop-docker.png)

## What this repository is for

- Evaluate the complete CMDOP workflow without assembling a server and agent by hand.
- Give Claude Code, Codex, and other agents a real project with a live feedback loop.
- Use the bundled site as a template for your own Docker-backed workspace.
- Learn the deployment boundary before connecting additional machines.

For programmatic Python and Node integrations, use
[`commandoperator/cmdop-sdk`](https://github.com/commandoperator/cmdop-sdk).

## Security model

The demo binds the live site and console to `127.0.0.1` by default. The relay
port remains container-local. Machine connections are outbound, and the agent's
working directory is explicitly set with `CMDOP_AGENT_CWD`.

Before exposing the stack publicly, read [deployment and firewall guidance](docs/deployment.md)
and [configuration and persistence](docs/configuration.md). Never commit `.env`.

## Documentation

- [Documentation index and safe support bundle](docs/README.md)
- [Architecture and process supervision](docs/architecture.md)
- [Configuration and persistence](docs/configuration.md)
- [Agent commits and optional GitHub publishing](docs/git-and-github.md)
- [Public deployment, ports and firewall](docs/deployment.md)
- [Troubleshooting](docs/troubleshooting.md)

## CMDOP ecosystem

- [CMDOP product site](https://cmdop.com)
- [CMDOP for Docker](https://cmdop.com/products/docker)
- [Documentation](https://docs.cmdop.com)
- [CMDOP SDK](https://github.com/commandoperator/cmdop-sdk)
- [Download CMDOP](https://cmdop.com/download)

## License

The Docker setup and demo project in this repository are licensed under the
[Apache License 2.0](LICENSE). CMDOP itself is distributed under its own product
terms.
