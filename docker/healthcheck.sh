#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${CMDOP_CONTAINER_MODE:-workspace}" == "agent" ]]; then
  # Agent mode has no HTTP surfaces: healthy = the supervised agent process
  # is alive. The daemon manager maintains the pid file in foreground mode.
  pid="$(cat "${HOME}/.cmdop/run/agent.pid" 2>/dev/null || true)"
  [[ -n "${pid}" ]]
  kill -0 "${pid}"
  exit 0
fi

curl -fsS "http://127.0.0.1:${CMDOP_HTTP_PORT:-63141}/health" >/dev/null
curl -fsS "http://127.0.0.1:${DEMO_PORT:-5173}/" >/dev/null
