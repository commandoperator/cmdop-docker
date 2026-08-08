#!/usr/bin/env bash
set -Eeuo pipefail

readonly DEMO_DIR="/workspace/demo"
readonly SERVER_CONFIG="${CMDOP_CONFIG_DIR}/server.yaml"
readonly ADMIN_PASSWORD_FILE="${CMDOP_ADMIN_PASSWORD_FILE:-/run/secrets/cmdop_admin_password}"
readonly JOIN_KEY_FILE="${CMDOP_JOIN_KEY_FILE:-/run/secrets/cmdop_join_key}"
# Pre-rename spellings (the CLI renamed `cmdop enroll` to `cmdop join` and the
# secret's one term is "join key"). Still honored so an existing .env keeps
# working; new deployments should use CMDOP_JOIN_KEY.
readonly LEGACY_ENROLL_PASSWORD_FILE="${CMDOP_ENROLL_PASSWORD_FILE:-/run/secrets/cmdop_enroll_password}"

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

remove_legacy_home_binary() {
  # Images before v1.1.110 installed cmdop under the persistent HOME volume.
  # That file can outlive an image rebuild and win in login-shell PATH order.
  # The image-owned binary now lives under /opt with /usr/local/bin as its
  # stable command path, so remove only the obsolete executable during upgrade.
  if [[ -e "${HOME}/.local/bin/cmdop" ]]; then
    rm -f "${HOME}/.local/bin/cmdop"
    log "Removed legacy Cmdop binary from the persistent home volume."
  fi
}

ensure_git_repository() {
  if [[ -z "${GIT_DIR:-}" || -z "${GIT_WORK_TREE:-}" ]]; then
    log "GIT_DIR and GIT_WORK_TREE are required for the isolated demo repository."
    return 1
  fi

  if [[ ! -f "${GIT_DIR}/HEAD" ]]; then
    log "Initializing the isolated demo Git repository."
    git init --initial-branch=main --quiet
  fi

  git config --local user.name "${CMDOP_GIT_AUTHOR_NAME:-Cmdop Agent}"
  git config --local user.email "${CMDOP_GIT_AUTHOR_EMAIL:-agent@cmdop.local}"

  if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
    git add --all
    git commit --quiet --message "chore: initialize live workspace"
    log "Created the initial demo snapshot."
  fi
}

clear_stale_runtime() {
  # cmdop agent (v1.1.110) exits with ENOENT when the runtime directory is
  # absent, and a freshly created home volume ships without it.
  mkdir -p "${HOME}/.cmdop/run"
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

resolve_join_key() {
  # Resolution order: new name, new secret file, then the pre-rename
  # spellings. Every hit but the first-listed logs where the value came from,
  # so a mixed .env cannot silently surprise.
  if [[ -n "${CMDOP_JOIN_KEY:-}" ]]; then
    printf '%s' "${CMDOP_JOIN_KEY}"
    return 0
  fi
  if [[ -r "${JOIN_KEY_FILE}" ]]; then
    log "Reading the join key from ${JOIN_KEY_FILE}." >&2
    cat "${JOIN_KEY_FILE}"
    return 0
  fi
  if [[ -n "${CMDOP_ENROLL_PASSWORD:-}" ]]; then
    log "CMDOP_ENROLL_PASSWORD is the pre-rename spelling; prefer CMDOP_JOIN_KEY." >&2
    printf '%s' "${CMDOP_ENROLL_PASSWORD}"
    return 0
  fi
  if [[ -r "${LEGACY_ENROLL_PASSWORD_FILE}" ]]; then
    log "${LEGACY_ENROLL_PASSWORD_FILE} is the pre-rename secret path; prefer ${JOIN_KEY_FILE}." >&2
    cat "${LEGACY_ENROLL_PASSWORD_FILE}"
    return 0
  fi
  return 1
}

run_agent_mode() {
  # Agent mode: this container is ONE MORE MACHINE in an existing fleet — no
  # embedded server, no demo project, no Vite. The CLI already supports the
  # whole path; this branch only wires it.
  if [[ -z "${CMDOP_SERVER_URL:-}" ]]; then
    log "CMDOP_SERVER_URL is required when CMDOP_CONTAINER_MODE=agent."
    return 1
  fi

  local join_key
  if ! join_key="$(resolve_join_key)"; then
    log "CMDOP_JOIN_KEY (or a readable ${JOIN_KEY_FILE}) is required when CMDOP_CONTAINER_MODE=agent. Print the fleet's key with 'cmdop server join-key' on the relay host."
    return 1
  fi

  local workdir="${CMDOP_AGENT_CWD:-/workspace}"
  mkdir -p "${workdir}"
  cd "${workdir}"

  local join_args=(--server "${CMDOP_SERVER_URL}" --no-agent)
  if [[ -n "${CMDOP_MACHINE_NAME:-}" ]]; then
    join_args+=(--display-name "${CMDOP_MACHINE_NAME}")
  fi
  if [[ -n "${CMDOP_MACHINE_PIN:-}" ]]; then
    join_args+=(--machine-pin "${CMDOP_MACHINE_PIN}")
  fi
  if [[ "${CMDOP_SERVER_INSECURE:-0}" == "1" ]]; then
    join_args+=(--insecure)
  fi

  # Re-joining on every start is idempotent: the join key is a durable
  # multi-use fleet secret, and a rotated one is picked up automatically.
  cmdop join "${join_key}" "${join_args[@]}" >/dev/null
  log "Joined ${CMDOP_SERVER_URL}; starting the machine agent in ${workdir}."

  # exec: the agent becomes the supervised child of the container init, so
  # signals reach it directly and its exit status is the container's.
  trap - TERM INT EXIT
  exec cmdop agent start --foreground --no-power-blocker
}

resolve_codex_sandbox() {
  # Codex sandboxes every command it runs; on Linux that sandbox is bubblewrap,
  # which needs an unprivileged user namespace. A container usually cannot
  # create one (Docker's default seccomp/AppArmor profiles, Docker Desktop's
  # LinuxKit kernel, or a host with unprivileged userns disabled), and the
  # failure is total: bwrap refuses, so every shell command Codex attempts
  # fails rather than degrading.
  #
  # "auto" asks bubblewrap directly instead of guessing from the kernel
  # version. When it cannot run, the honest configuration is full access —
  # the container is already the isolation boundary, and it is the same
  # boundary Cmdop's own agent works inside.
  case "${CMDOP_CODEX_SANDBOX:-auto}" in
    read-only|workspace-write|danger-full-access)
      printf '%s' "${CMDOP_CODEX_SANDBOX}"
      return 0
      ;;
    auto) ;;
    *)
      log "CMDOP_CODEX_SANDBOX must be auto, read-only, workspace-write, or danger-full-access."
      return 1
      ;;
  esac

  if codex sandbox /bin/true >/dev/null 2>&1; then
    printf 'workspace-write'
  else
    log "Codex's bubblewrap sandbox cannot start in this container; using danger-full-access." >&2
    log "The container boundary applies either way. Pin CMDOP_CODEX_SANDBOX to override." >&2
    printf 'danger-full-access'
  fi
}

configure_coding_agents() {
  # CLAUDE_CONFIG_DIR and CODEX_HOME point both CLIs into ./agents, which
  # Compose bind-mounts from the host — so a login survives image rebuilds and
  # volume resets alike. Nothing here writes a credential: the operator signs
  # in through each CLI's own flow, and that mounted directory is the only
  # place the resulting token ever lands.
  #
  # The subdirectories are created here rather than only in the image, because
  # a bind mount shadows whatever the image put at that path: on a fresh clone
  # ./agents is an empty directory carrying just a .gitkeep.
  local claude_dir="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
  local codex_dir="${CODEX_HOME:-${HOME}/.codex}"
  if ! mkdir -p "${claude_dir}" "${codex_dir}" 2>/dev/null; then
    log "Cannot create ${CMDOP_AGENTS_DIR:-${HOME}/agents} subdirectories."
    log "The host ./agents directory must be writable by UID ${HOST_UID:-$(id -u)}; see docs/coding-agents.md."
    return 1
  fi
  # The tokens are the whole reason this directory exists. On a host bind
  # mount the default mode comes from the host's umask, not from the image.
  chmod 0700 "${CMDOP_AGENTS_DIR:-$(dirname "${claude_dir}")}" 2>/dev/null || true

  if command -v codex >/dev/null 2>&1; then
    local codex_config="${codex_dir}/config.toml"
    if [[ ! -e "${codex_config}" ]]; then
      local sandbox_mode
      sandbox_mode="$(resolve_codex_sandbox)" || return 1
      cat >"${codex_config}" <<EOF
# Written once by cmdop-docker when this file was absent. It is never
# rewritten, so edits here survive container recreation. Delete the file to
# have the container regenerate it.
sandbox_mode = "${sandbox_mode}"
EOF
      log "Wrote ${codex_config} with sandbox_mode=${sandbox_mode}."
    fi
    # The presence of the credential file is the whole test. Asking the CLI
    # itself would mean a network round trip on every container start.
    if [[ ! -e "${codex_dir}/auth.json" ]]; then
      log "Codex is installed and not signed in yet — run: make codex-login"
    fi
  fi

  if command -v claude >/dev/null 2>&1; then
    if [[ ! -e "${claude_dir}/.credentials.json" ]]; then
      log "Claude Code is installed and not signed in yet — run: make claude-login"
    fi
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

case "${CMDOP_CONTAINER_MODE:-workspace}" in
  workspace|agent) ;;
  *)
    log "CMDOP_CONTAINER_MODE must be workspace or agent."
    exit 1
    ;;
esac

remove_legacy_home_binary
clear_stale_runtime
configure_permissions
configure_coding_agents

if [[ "${CMDOP_CONTAINER_MODE:-workspace}" == "agent" ]]; then
  run_agent_mode # never returns (execs the agent)
  exit 1
fi

cd "${DEMO_DIR}"
ensure_node_modules
ensure_git_repository
configure_relay

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
