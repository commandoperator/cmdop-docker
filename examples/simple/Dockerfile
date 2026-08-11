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
#
#    /usr/local/bin is root-owned, which is fine HERE because this image never
#    drops privileges. **If YOUR image has a `USER` line, do not copy this line
#    as-is.** Cmdop updates itself by writing `<target>.new` beside the binary
#    and renaming it over the top — a write on the DIRECTORY, not on the file —
#    so a non-root process cannot install into a root-owned directory. The agent
#    still runs; it just downloads ~100 MB every hour and never applies it, with
#    no failure louder than a log line. Give it a directory the runtime user
#    owns and symlink it into PATH — see ../../docs/agent-updates.md, which has
#    the four lines to use instead.
COPY --from=markolofsen/cmdop:latest /cmdop /usr/local/bin/cmdop

# 2. Start the agent, then exec YOUR command. `sidecar` runs the agent in the
#    background and replaces itself with what follows `--`, so your process
#    keeps PID 1 — docker stop signals it, its exit code is the container's.
ENTRYPOINT ["cmdop", "sidecar", "--"]
# ─────────────────────────────────────────────────────────────────────────────

CMD ["node", "app.js"]
