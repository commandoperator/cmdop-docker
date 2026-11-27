# CMDOP reference environments

| Target | Entry point | Status |
| --- | --- | --- |
| Linux Docker container | [Report reference](report-app/README.md), existing compose.yaml and connect | Existing Linux reference |
| Windows VM managed by Docker | [Windows reference](windows/README.md) | Preview; native acceptance pending |

Linux embeds CMDOP in an application. Windows supplies a real native installer
and updater acceptance environment, then a two-platform demo. Both share the
release contract, not the binary, kernel, identity or storage.

The existing Linux Compose project, volume, build contexts and entry points
are unchanged. Move Linux into a symmetric linux/ folder in a coordinated
migration with its registry owner and external consumers; do not duplicate
its image definition just to make the directory tree symmetric.
