FROM node:24-bookworm

ARG HOST_UID=1000
ARG HOST_GID=1000
ARG CMDOP_INSTALL_URL=https://install.cmdop.com

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/cmdop \
    PATH=/home/cmdop/.local/bin:${PATH} \
    CMDOP_CONFIG_DIR=/home/cmdop/.config/cmdop \
    CMDOP_ASCII=1 \
    NO_COLOR=1 \
    DEMO_PORT=5173 \
    CMDOP_HTTP_PORT=63141

RUN groupmod --new-name cmdop --gid "${HOST_GID}" node \
    && usermod --login cmdop --uid "${HOST_UID}" --gid "${HOST_GID}" \
        --home /home/cmdop --move-home node \
    && mkdir -p /workspace/demo "${CMDOP_CONFIG_DIR}" /home/cmdop/.local/bin \
    && chown -R cmdop:cmdop /workspace /home/cmdop

WORKDIR /workspace/demo

USER cmdop

# The official installer owns architecture selection and checksum validation.
# Running it unprivileged keeps host service files out of the container.
RUN curl -fsSL "${CMDOP_INSTALL_URL}" \
    | CMDOP_QUIET=1 bash -s -- --prefix=/home/cmdop/.local/bin

# Fail at build time when the selected distribution predates the container
# runtime contract this image relies on. This is clearer than boot-looping on an
# unknown flag after Compose has already created state volumes.
RUN cmdop server --help | grep -q -- '--cwd' \
    && cmdop server --help | grep -q -- '--initial-admin-password-file' \
    && cmdop server --help | grep -q -- '--no-banner'

COPY --chown=cmdop:cmdop demo/package.json demo/package-lock.json ./
RUN npm ci --ignore-scripts \
    && chown -R cmdop:cmdop /workspace/demo/node_modules

COPY --chown=cmdop:cmdop demo/ ./
COPY --chown=root:root --chmod=0755 docker/entrypoint.sh docker/healthcheck.sh /usr/local/bin/

EXPOSE 5173 63141

HEALTHCHECK --interval=10s --timeout=4s --start-period=45s --retries=6 \
    CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
