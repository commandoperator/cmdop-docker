# NO registry: the cmdop binary is fetched by the official installer during the
# build (see the RUN below). The registry-based form — two lines, cacheable — is
# ../simple.
FROM node:24-bookworm

ARG HOST_UID=1000
ARG HOST_GID=1000
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

# Claude Code and Codex are installed at FIRST BOOT, not baked in — ~770 MB the
# image does not carry for two CLIs a stand may never open, and they are current
# on every start instead of frozen at build time.
#
# Where they land is load-bearing: /opt/cmdop/agents, owned by the runtime user
# and NOT under /home/cmdop, which is a volume — a binary installed into a
# volume is seeded once and then outlives every image rebuild. The rest
# (npm vs the vendors' installers, the CLAUDE_CONFIG_DIR/CODEX_HOME redirect) is
# in docs/coding-agents.md § "Why the image installs them this way".
# Nothing is installed here — see the entrypoint. The image only reserves the
# directory they land in, owned by the runtime user so a non-root start can
# write it, and NOT under /home/cmdop, which is a volume.
RUN mkdir -p /opt/cmdop/agents/bin && chown -R cmdop:cmdop /opt/cmdop/agents
ENV PATH=/opt/cmdop/agents/bin:${PATH} \
    NPM_CONFIG_PREFIX=/opt/cmdop/agents

WORKDIR /workspace/demo

USER cmdop

# The binary, fetched by the official installer at build time — NO registry
# involved. That independence is what this example is for: everything here is
# reachable with curl and a shell, so it works behind a proxy, on an air-gapped
# mirror, or anywhere pulling from Docker Hub is not an option.
#
# The elegant path is the opposite one, and it is ../simple: two lines,
# `COPY --from=markolofsen/cmdop:latest`, no fetch inside the build and a
# cacheable layer. Use this form when you cannot, or will not, depend on a
# registry.
#
# The installer picks the architecture itself and verifies the download against
# the release SHA256SUMS.
RUN curl -fsSL https://install.cmdop.com | sh -s -- --prefix=/opt/cmdop/bin

# Fail at build time when the selected distribution predates the container
# runtime contract this image relies on. This is clearer than boot-looping on an
# unknown flag after Compose has already created state volumes.
RUN cmdop server --help | grep -q -- '--cwd' \
    && cmdop server --help | grep -q -- '--initial-admin-password-file' \
    && cmdop server --help | grep -q -- '--no-banner'

# The coding agents have no build-time contract check any more: they are not
# installed here. install_coding_agents in the entrypoint verifies each one
# after it lands, which is the only place that can now be true.

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
