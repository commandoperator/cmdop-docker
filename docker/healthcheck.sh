#!/usr/bin/env bash
set -Eeuo pipefail

# The demo stand is healthy when both of its doors answer: the Cmdop console
# and the Vite site. Two HTTP probes, no process-liveness guessing.
#
# The agent-mode branch that used to live here is gone with the agent service
# itself. It was `kill -0` on a pidfile — its own comment said "healthy = the
# supervised agent process is alive" — so a machine the relay had refused for a
# week still reported healthy. A container running the agent now uses
# `cmdop status --check`, which is only healthy when the machine is CONNECTED.
curl -fsS "http://127.0.0.1:${CMDOP_HTTP_PORT:-63141}/health" >/dev/null
curl -fsS "http://127.0.0.1:${DEMO_PORT:-5173}/" >/dev/null
