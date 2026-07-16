#!/usr/bin/env bash
set -Eeuo pipefail

readonly DEMO_DIR="/workspace/demo"
readonly SERVER_CONFIG="${CMDOP_CONFIG_DIR}/server.yaml"
readonly ADMIN_PASSWORD_FILE="${CMDOP_ADMIN_PASSWORD_FILE:-/run/secrets/cmdop_admin_password}"

server_pid=""
vite_pid=""

log() {
  printf '[cmdop-demo] %s\n' "$*"
}

stop_children() {
  trap - TERM INT EXIT
  local pid
  for pid in "${vite_pid}" "${server_pid}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill -TERM "${pid}" 2>/dev/null || true
    fi
  done
  wait 2>/dev/null || true
}

trap stop_children TERM INT EXIT

ensure_node_modules() {
  local wanted current
  wanted="$(sha256sum package-lock.json | cut -d' ' -f1)"
  current="$(cat node_modules/.cmdop-package-lock.sha256 2>/dev/null || true)"
  if [[ ! -x node_modules/.bin/vite || "${wanted}" != "${current}" ]]; then
    log "Synchronizing Node dependencies with package-lock.json."
    npm ci --ignore-scripts
    printf '%s\n' "${wanted}" >node_modules/.cmdop-package-lock.sha256
  fi
}

configure_relay() {
  local desired_mode
  case "${CMDOP_RELAY_MODE:-auto}" in
    auto)
      if [[ -n "${CMDOP_PUBLIC_SUBDOMAIN:-}" ]]; then
        desired_mode="public"
      else
        desired_mode="lan"
      fi
      ;;
    lan|public)
      desired_mode="${CMDOP_RELAY_MODE}"
      ;;
    *)
      log "CMDOP_RELAY_MODE must be auto, lan, or public."
      return 1
      ;;
  esac

  if [[ "${desired_mode}" == "public" ]]; then
    if [[ -z "${CMDOP_PUBLIC_SUBDOMAIN:-}" ]]; then
      log "CMDOP_PUBLIC_SUBDOMAIN is required when CMDOP_RELAY_MODE=public."
      return 1
    fi
    if [[ ! "${CMDOP_PUBLIC_SUBDOMAIN}" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
      log "CMDOP_PUBLIC_SUBDOMAIN must be a lowercase DNS label."
      return 1
    fi
    if [[ -z "${CMDOP_ROUTER_API_KEY:-}" ]]; then
      log "CMDOP_API_KEY is required for public relay registration."
      return 1
    fi
  fi

  if [[ ! -f "${SERVER_CONFIG}" ]]; then
    log "Generating the current Cmdop server config for ${desired_mode} mode."
    if [[ "${desired_mode}" == "public" ]]; then
      # The current CLI owns the YAML schema. Keep the platform key out of the
      # file; cmdop server resolves CMDOP_ROUTER_API_KEY in memory at runtime.
      cmdop server create \
        --mode public \
        --subdomain "${CMDOP_PUBLIC_SUBDOMAIN}" \
        --no-prompt \
        --name "${CMDOP_MACHINE_NAME:-cmdop-live-demo}" >/dev/null
    else
      cmdop server create \
        --mode lan \
        --no-prompt \
        --name "${CMDOP_MACHINE_NAME:-cmdop-live-demo}" >/dev/null
    fi
  fi

  if [[ ! -r "${ADMIN_PASSWORD_FILE}" ]]; then
    log "Initial admin password secret is not readable at ${ADMIN_PASSWORD_FILE}."
    return 1
  fi
}

configure_permissions() {
  case "${CMDOP_PERMISSIONS_MODE:-default}" in
    default|strict|bypass)
      cmdop permissions mode "${CMDOP_PERMISSIONS_MODE:-default}" >/dev/null
      ;;
    *)
      log "CMDOP_PERMISSIONS_MODE must be default, strict, or bypass."
      return 1
      ;;
  esac
}

cd "${DEMO_DIR}"
ensure_node_modules
configure_relay
configure_permissions

if [[ -z "${CMDOP_ROUTER_API_KEY:-}" ]]; then
  log "Warning: CMDOP_ROUTER_API_KEY is empty. The UI starts, but agent inference may be unavailable."
fi

log "Starting Cmdop relay and browser console on port ${CMDOP_HTTP_PORT:-63141}."
cmdop server \
  --cwd "${DEMO_DIR}" \
  --initial-admin-password-file "${ADMIN_PASSWORD_FILE}" \
  --no-banner \
  --no-open &
server_pid=$!

log "Starting Vite on port ${DEMO_PORT:-5173}."
npm run dev -- --host 0.0.0.0 --port "${DEMO_PORT:-5173}" &
vite_pid=$!

log "Demo site: http://localhost:${DEMO_PORT:-5173}"
log "Cmdop console: http://localhost:${CMDOP_HTTP_PORT:-63141}"
if [[ -n "${CMDOP_PUBLIC_SUBDOMAIN:-}" && "${CMDOP_RELAY_MODE:-auto}" != "lan" ]]; then
  log "Public Cmdop relay: https://${CMDOP_PUBLIC_SUBDOMAIN}.cmdop.dev"
fi

if wait -n "${server_pid}" "${vite_pid}"; then
  status=0
else
  status=$?
fi
log "A required process exited with status ${status}; stopping the container."
exit "${status}"
