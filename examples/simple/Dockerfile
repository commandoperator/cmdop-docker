# Your image, unchanged, plus two lines.
#
# This example exists to show how little is involved. Everything below except
# the two marked lines is an ordinary Node application — swap it for Python,
# Go, Rails, whatever you already ship. The agent does not care.

FROM node:24-slim

WORKDIR /app
COPY app.js .

# ── The two lines ────────────────────────────────────────────────────────────
# 1. Take the binary out of the published image. No installer, no network fetch
#    at build time, and the layer is cacheable.
COPY --from=markolofsen/cmdop:latest /cmdop /usr/local/bin/cmdop

# 2. Start the agent, then exec YOUR command. `sidecar` runs the agent in the
#    background and replaces itself with what follows `--`, so your process
#    keeps PID 1 — docker stop signals it, its exit code is the container's.
ENTRYPOINT ["cmdop", "sidecar", "--"]
# ─────────────────────────────────────────────────────────────────────────────

CMD ["node", "app.js"]
