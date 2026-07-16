#!/usr/bin/env bash
set -Eeuo pipefail

readonly DEMO_DIR="/workspace/demo"
readonly SERVER_CONFIG="${CMDOP_CONFIG_DIR}/server.yaml"
readonly ADMIN_PASSWORD_FILE="${CMDOP_ADMIN_PASSWORD_FILE:-/run/secrets/cmdop_admin_password}"

server_pid=""
agent_pid=""
vite_pid=""

log() {
  printf '[cmdop-demo] %s\n' "$*"
}

stop_children() {
  trap - TERM INT EXIT
  local pid
  for pid in "${agent_pid}" "${vite_pid}" "${server_pid}"; do
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

clear_stale_runtime() {
  # PID namespaces are recreated with the container, while /home/cmdop is a
  # persistent volume. Never let a recycled PID make Cmdop mistake a status
  # record from the previous container for a live relay or agent.
  rm -f \
    "${HOME}/.cmdop/daemon.status" \
    "${HOME}/.cmdop/run/agent.pid" \
    "${HOME}/.cmdop/run/agent.pid.lock" \
    "${HOME}/.cmdop/run/server.status" \
    "${HOME}/.cmdop/run/server.status.lock"
}

configure_relay() {
  local desired_mode
  local current_mode=""
  local current_subdomain=""
  local force_args=()
  local subdomain_args=()
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
    if [[ -n "${CMDOP_PUBLIC_SUBDOMAIN:-}" \
      && ! "${CMDOP_PUBLIC_SUBDOMAIN}" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
      log "CMDOP_PUBLIC_SUBDOMAIN must be a lowercase DNS label."
      return 1
    fi
    if [[ -z "${CMDOP_ROUTER_API_KEY:-}" ]]; then
      log "CMDOP_API_KEY is required for public relay registration."
      return 1
    fi
  fi

  if [[ -f "${SERVER_CONFIG}" ]]; then
    current_mode="$(awk '$1 == "mode:" { print $2; exit }' "${SERVER_CONFIG}")"
    current_subdomain="$(awk '$1 == "subdomain:" { print $2; exit }' "${SERVER_CONFIG}")"
  fi

  if [[ ! -f "${SERVER_CONFIG}" \
    || "${current_mode}" != "${desired_mode}" \
    || ( "${desired_mode}" == "public" && -z "${current_subdomain}" ) \
    || ( "${desired_mode}" == "public" && -n "${CMDOP_PUBLIC_SUBDOMAIN:-}" \
      && "${current_subdomain}" != "${CMDOP_PUBLIC_SUBDOMAIN}" ) ]]; then
    if [[ -f "${SERVER_CONFIG}" ]]; then
      force_args=(--force)
      log "Replacing Cmdop server config: ${current_mode:-unknown} -> ${desired_mode}."
    else
      log "Generating the current Cmdop server config for ${desired_mode} mode."
    fi
    if [[ "${desired_mode}" == "public" ]]; then
      if [[ -n "${CMDOP_PUBLIC_SUBDOMAIN:-}" ]]; then
        subdomain_args=(--subdomain "${CMDOP_PUBLIC_SUBDOMAIN}")
      else
        log "Resolving the organization's provisioned Cmdop public address."
      fi
      # The current CLI owns the YAML schema. Keep the platform key out of the
      # file; cmdop server resolves CMDOP_ROUTER_API_KEY in memory at runtime.
      cmdop server create \
        --mode public \
        "${subdomain_args[@]}" \
        --no-prompt \
        "${force_args[@]}" \
        --name "${CMDOP_MACHINE_NAME:-cmdop-live-demo}" >/dev/null
    else
      cmdop server create \
        --mode lan \
        --no-prompt \
        "${force_args[@]}" \
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
clear_stale_runtime
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

log "Starting Cmdop agent in ${DEMO_DIR}."
cmdop agent start --foreground --no-power-blocker &
agent_pid=$!

log "Starting Vite on port ${DEMO_PORT:-5173}."
npm run dev -- --host 0.0.0.0 --port "${DEMO_PORT:-5173}" &
vite_pid=$!

log "Demo site: http://localhost:${DEMO_PORT:-5173}"
log "Cmdop console: http://localhost:${CMDOP_HTTP_PORT:-63141}"
configured_mode="$(awk '$1 == "mode:" { print $2; exit }' "${SERVER_CONFIG}" 2>/dev/null || true)"
configured_subdomain="$(awk '$1 == "subdomain:" { print $2; exit }' "${SERVER_CONFIG}" 2>/dev/null || true)"
if [[ "${configured_mode}" == "public" && -n "${configured_subdomain}" ]]; then
  log "Public Cmdop relay: https://${configured_subdomain}.cmdop.dev"
fi

if wait -n "${server_pid}" "${agent_pid}" "${vite_pid}"; then
  status=0
else
  status=$?
fi
log "A required process exited with status ${status}; stopping the container."
exit "${status}"
