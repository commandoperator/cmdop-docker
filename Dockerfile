FROM node:24-bookworm

ARG HOST_UID=1000
ARG HOST_GID=1000
ARG CMDOP_INSTALL_URL=https://install.cmdop.com
ARG CMDOP_BROWSER=1
ARG CMDOP_CLAUDE_CODE=1
ARG CMDOP_CODEX=1

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/cmdop \
    PATH=/opt/cmdop/bin:${PATH} \
    CMDOP_CONFIG_DIR=/home/cmdop/.config/cmdop \
    CMDOP_ASCII=1 \
    NO_COLOR=1 \
    DEMO_PORT=5173 \
    CMDOP_HTTP_PORT=63141 \
    CMDOP_AGENTS_DIR=/home/cmdop/agents \
    CLAUDE_CONFIG_DIR=/home/cmdop/agents/claude \
    CODEX_HOME=/home/cmdop/agents/codex \
    # CLAUDE CODE's variable, not cmdop's — it stops the npm-installed `claude`
    # from trying to replace an executable in a root-owned image path. cmdop's
    # own auto-update is unaffected and stays ON (its switch is
    # CMDOP_NO_AUTO_UPDATE, and it updates /opt/cmdop/bin, which IS writable).
    #
    # Named here because the name does not say whose it is: while diagnosing a
    # delayed cmdop update on 2026-08-10 this line read as the culprit and cost
    # a detour before `grep DISABLE_AUTOUPDATER` over the Go tree came back
    # empty.
    DISABLE_AUTOUPDATER=1

# Chromium powers the agent's headless browser tools (CDP). The agent probes
# for the binary at runtime and silently skips browser tools when it is
# absent, so CMDOP_BROWSER=0 builds a slimmer image with the same contract.
# Debian's chromium tracks the security channel; noto-cjk/emoji fonts keep
# screenshots of non-Latin pages from rendering as tofu.
RUN if [ "${CMDOP_BROWSER}" = "1" ]; then \
        apt-get update \
        && apt-get install -y --no-install-recommends \
            chromium \
            chromium-sandbox \
            fonts-liberation \
            fonts-noto-cjk \
            fonts-noto-color-emoji \
        && rm -rf /var/lib/apt/lists/*; \
    fi

RUN groupmod --new-name cmdop --gid "${HOST_GID}" node \
    && usermod --login cmdop --uid "${HOST_UID}" --gid "${HOST_GID}" \
        --home /home/cmdop --move-home node \
    && mkdir -p /workspace/demo /workspace/.git "${CMDOP_CONFIG_DIR}" \
        "${CLAUDE_CONFIG_DIR}" "${CODEX_HOME}" /opt/cmdop/bin \
    && chmod 0700 "${CMDOP_AGENTS_DIR}" \
    && chown -R cmdop:cmdop /workspace /home/cmdop /opt/cmdop \
    && ln -s /opt/cmdop/bin/cmdop /usr/local/bin/cmdop

# Claude Code and Codex, installed image-side so the container has a coding
# agent the moment it boots.
#
# npm rather than each vendor's own installer, and this is the load-bearing
# decision in the file. Both official installers are hard-wired to $HOME
# (`claude.ai/install.sh` writes ~/.local/bin and ~/.local/share/claude with no
# prefix option), and $HOME here is the persistent `cmdop_state` volume. A
# binary installed into a volume is seeded once, at first container creation,
# and then survives every later image build — the exact stale-executable trap
# this image already had to unwind for Cmdop itself, which is why the
# entrypoint still carries `remove_legacy_home_binary`. Installing under
# /usr/local gives the split we actually want: the executables belong to the
# image and are replaced by a rebuild, the credentials belong to the host and
# are not.
#
# The npm packages are thin: each pulls a per-platform native binary through an
# optional dependency, so nothing here runs on Node at runtime. Unpinned for
# the same reason Cmdop is — Compose builds with no_cache, so a build resolves
# whatever is current.
#
# The other half of that split is CLAUDE_CONFIG_DIR / CODEX_HOME above. Left
# alone, each CLI scatters state across HOME — Claude Code writes ~/.claude
# AND a sibling ~/.claude.json — and none of it would be separable from the
# rest of the home volume. Both accept a redirect, so the layout is ours to
# pick: one directory per agent, both under CMDOP_AGENTS_DIR, which Compose
# bind-mounts from ./agents as a single path. A login then lives on the host,
# outlives every image rebuild, and a fourth agent tomorrow is one more
# subdirectory rather than one more mount.
#
# Order matters, and not for caching: this must stay AFTER the usermod above.
# The ENV block sets HOME=/home/cmdop for every layer, so npm running as root
# would create its cache there — and `usermod --move-home` refuses to move onto
# a directory that already exists, failing the build with a bare `exit 12`.
# HOME=/root keeps the cache out of the runtime user's home either way.
RUN HOME=/root sh -c ' \
        if [ "${CMDOP_CLAUDE_CODE}" = "1" ]; then \
            npm install -g --no-fund --no-audit @anthropic-ai/claude-code@latest; \
        fi \
        && if [ "${CMDOP_CODEX}" = "1" ]; then \
            npm install -g --no-fund --no-audit @openai/codex@latest; \
        fi \
        && npm cache clean --force'

WORKDIR /workspace/demo

USER cmdop

# The official installer owns architecture selection and checksum validation.
# Running it unprivileged keeps host service files out of the container.
RUN curl -fsSL "${CMDOP_INSTALL_URL}" \
    | CMDOP_QUIET=1 bash -s -- --prefix=/opt/cmdop/bin

# Fail at build time when the selected distribution predates the container
# runtime contract this image relies on. This is clearer than boot-looping on an
# unknown flag after Compose has already created state volumes.
RUN cmdop server --help | grep -q -- '--cwd' \
    && cmdop server --help | grep -q -- '--initial-admin-password-file' \
    && cmdop server --help | grep -q -- '--no-banner'

# Same contract check for the coding agents, and deliberately run as cmdop
# rather than root: a global npm install that landed with the wrong ownership
# still executes for root and fails for the runtime user, which would otherwise
# only surface as a "command not found" long after the image shipped.
RUN if [ "${CMDOP_CLAUDE_CODE}" = "1" ]; then \
        claude --version \
        && claude auth --help | grep -q 'login'; \
    fi \
    && if [ "${CMDOP_CODEX}" = "1" ]; then \
        codex --version \
        && codex login --help | grep -q -- '--device-auth'; \
    fi

COPY --chown=cmdop:cmdop demo/package.json demo/package-lock.json ./
RUN npm ci --ignore-scripts \
    && chown -R cmdop:cmdop /workspace/demo/node_modules

COPY --chown=cmdop:cmdop demo/ ./
COPY --chown=root:root --chmod=0755 docker/entrypoint.sh docker/healthcheck.sh /usr/local/bin/

# Cmdop's current torrent client is download-only, uses an ephemeral listen
# port, and disables automatic port forwarding. It needs outbound TCP/UDP but
# intentionally has no stable inbound torrent port to expose here.
EXPOSE 5173 63141

HEALTHCHECK --interval=10s --timeout=4s --start-period=45s --retries=6 \
    CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
