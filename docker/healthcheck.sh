#!/usr/bin/env bash
set -Eeuo pipefail

curl -fsS "http://127.0.0.1:${CMDOP_HTTP_PORT:-63141}/health" >/dev/null
curl -fsS "http://127.0.0.1:${DEMO_PORT:-5173}/" >/dev/null
