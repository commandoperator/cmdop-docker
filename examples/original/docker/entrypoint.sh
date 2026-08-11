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
      #
      # No --name on purpose. The CLI derives the relay's own name — an explicit
      # --name, else the public label, else the hostname — so a relay published
      # at <label>.cmdop.dev calls itself <label> and its messenger bot
      # announces "CMDOP <label>". Passing CMDOP_MACHINE_NAME here (as this file
      # did until 2026-08-11) took the ladder's TOP rung and pinned the relay to
      # a name unrelated to its own address.
      cmdop server create \
        --mode public \
        "${subdomain_args[@]}" \
        --no-prompt \
        "${force_args[@]}" >/dev/null
    else
      # LAN has no public label, so the relay's name falls through to the
      # container hostname. Note that is os.Hostname(), NOT CMDOP_MACHINE_NAME —
      # that variable names this box as a fleet MEMBER (its roster row), a
      # different identity from the relay's own name. Set `hostname:` in compose
      # to control this one.
      cmdop server create \
        --mode lan \
        --no-prompt \
        "${force_args[@]}" >/dev/null
    fi
  fi

  if [[ ! -r "${ADMIN_PASSWORD_FILE}" ]]; then
    log "Initial admin password secret is not readable at ${ADMIN_PASSWORD_FILE}."
    return 1
  fi
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

install_coding_agents() {
  # Claude Code and Codex are installed HERE, not in the image: ~770 MB the
  # image does not carry, and a version resolved at boot rather than frozen at
  # build time.
  #
  # NEVER FATAL. The stand is a relay, an agent and a live site; two optional
  # coding CLIs failing to install must not stop any of that. Each failure is
  # named and the boot continues.
  #
  # Skipped entirely when already present, so a restart costs nothing.
  local pkgs=""
  [ "${CMDOP_CLAUDE_CODE:-1}" = "1" ] && ! command -v claude >/dev/null 2>&1 \
    && pkgs="${pkgs} @anthropic-ai/claude-code@latest"
  [ "${CMDOP_CODEX:-1}" = "1" ] && ! command -v codex >/dev/null 2>&1 \
    && pkgs="${pkgs} @openai/codex@latest"

  [ -z "${pkgs}" ] && return 0

  log "Installing coding agents (${pkgs# })…"
  if npm install -g --no-fund --no-audit --loglevel=error ${pkgs} 2>&1 | tail -3; then
    # The contract check the image used to do at build time. It ran as the
    # runtime user on purpose: a global install that landed with the wrong
    # ownership still executes for root and fails for cmdop, which would
    # otherwise surface as "command not found" much later.
    if [ "${CMDOP_CLAUDE_CODE:-1}" = "1" ] && ! claude --version >/dev/null 2>&1; then
      log "Claude Code installed but does not run — check ownership under /opt/cmdop/agents."
    fi
    if [ "${CMDOP_CODEX:-1}" = "1" ] && ! codex --version >/dev/null 2>&1; then
      log "Codex installed but does not run — check ownership under /opt/cmdop/agents."
    fi
    log "Coding agents ready."
  else
    log "Coding agents did not install — continuing without them."
    log "Retry later with: docker compose exec demo npm install -g${pkgs}"
  fi
  npm cache clean --force >/dev/null 2>&1 || true
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


install_coding_agents
configure_coding_agents

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
