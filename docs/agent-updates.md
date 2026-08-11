# Agent updates in a container

**Applies to: both examples.**

Cmdop keeps itself current at runtime. It checks on a schedule, downloads the
new release, and replaces its own binary in place — the bargain Tailscale, the
Datadog agent and `cloudflared` make, and the reason the repository README tells
you not to chase releases.

That default is right for most containers and it is the one you get by doing
nothing. This page is about the two ways it goes wrong quietly, and the switches
for turning it off on purpose.

## The one requirement: the binary's DIRECTORY must be writable

An in-place update is an atomic replace. Cmdop writes the new binary next to the
old one as `<target>.new` and renames it over the top, so the file is never
half-written and a crash mid-update cannot leave you with no `cmdop` at all.

The consequence catches people out, because it is a Unix rule rather than a
Cmdop one:

> Replacing a directory entry is a write on the **directory**, not on the file.

So `chmod +w` on the binary changes nothing. What matters is who owns the
directory it sits in. If your image runs as a non-root user and the binary is in
a root-owned `/usr/local/bin`, the update can download but can never install.

### What that failure looks like

Hourly, forever, in the agent log — and nowhere else, because nothing crashes:

```json
{"level":"warn","component":"update-scheduler","current":"1.1.143","new":"v1.1.148","message":"Update available"}
{"level":"warn","component":"auto-update","version":"v1.1.148","staged":"/state/.cache/cmdop/updates/cmdop-v1.1.148","finish_with":"sudo cmdop update apply","message":"Auto-update: downloaded but not applied — installing into this path needs elevation"}
```

`cmdop version` stays where it was. Each attempt re-downloads ~100 MB, and the
staged binaries sit in the cache under `HOME` — which is usually a volume, so it
is your disk that grows.

The advice in the message — `sudo cmdop update apply` — assumes a workstation.
Most containers have neither `sudo` nor anyone to run it.

### Confirming it in ten seconds

```bash
docker compose exec <svc> sh -lc 'id; ls -ld "$(dirname "$(readlink -f "$(command -v cmdop)")")"'
```

If the uid on the left does not own the directory on the right, this is your
problem.

### The fix

Give the binary a directory the runtime user owns, and symlink it into `PATH`:

```dockerfile
RUN mkdir -p /opt/cmdop/bin \
    && chown -R appuser:appuser /opt/cmdop \
    && ln -s /opt/cmdop/bin/cmdop /usr/local/bin/cmdop

USER appuser
RUN curl -fsSL https://install.cmdop.com | sh -s -- --prefix=/opt/cmdop/bin
```

`/usr/local/bin` stays root-owned and holds only a pointer, which is what you
want — nothing the agent can rewrite lives in a root directory.

Two details worth copying exactly:

- **Create and chown the directory before `USER`.** The installer decides it
  "requires sudo" when the prefix does not exist — even when it is already
  running as uid 0 — then finds no `sudo` and fails the build.
- **Do not make `/opt/cmdop` a volume.** A binary that outlives the image
  means `docker inspect` stops describing what is running, and every host in a
  fleet drifts to a different version.

[`examples/original`](../examples/original) has always been built this way,
which is why the demo stand has never hit this.

> ### `examples/simple` and the `USER` line
>
> [`examples/simple`](../examples/simple) copies the binary straight to
> `/usr/local/bin`, and that is correct **for `simple`**, which never drops
> privileges. It is the shortest thing that works and it keeps the example to two
> lines.
>
> Most real application images do drop privileges. If yours has a `USER` line,
> take the layout above instead of the two-line form — otherwise the agent runs
> fine and silently never updates again.

## `:latest` on Docker Hub is not the latest Cmdop

The other quiet one, and it only bites after you have fixed the first.

`markolofsen/cmdop:latest` is published from its own lane, and that lane is
rebuilt when **it** changes — its Dockerfile, its base image, a CVE. It is
deliberately not republished once per Cmdop release. So the tag means "the image
as of its last build", not "the current release".

The gap is usually invisible, because a container that updates itself reaches
the real latest within a day. Turn auto-update off and the gap becomes your
permanent version.

Measured on 2026-08-11: `COPY --from=markolofsen/cmdop:latest` yielded 1.1.143
while `install.cmdop.com` served 1.1.149 — six releases apart.

| You want | Use |
|---|---|
| a cacheable layer, no build-time network, self-update on | `COPY --from=markolofsen/cmdop:latest /cmdop …` |
| the current release baked in, pinned, reproducible | `RUN curl -fsSL https://install.cmdop.com \| sh -s -- --prefix=…` |

The installer costs you a ~100 MB fetch per cache miss and a build that fails
when `install.cmdop.com` is unreachable. Put it in the **last** layer so nothing
above it is invalidated.

## Turning it off on purpose

Two switches, both read by the binary:

| | |
|---|---|
| `CMDOP_NO_AUTO_UPDATE=1` | no background checks, ever. The version is whatever the image shipped. |
| `CMDOP_PIN_VERSION=v1.2.3` | the updater resolves to exactly that version and refuses anything else. Also a rollback switch. |

With the first set you will see this once at startup, and nothing further:

```
WRN Update scheduler skipped: CMDOP_NO_AUTO_UPDATE is set component=update-scheduler
```

**Explicit still works.** `cmdop update` and `cmdop update check` are operator
commands and ignore the switch by design — it governs the background scheduler,
not you. That is worth knowing in both directions: a hand-run update succeeds
even with auto-update off, and it lands in the container's writable layer, so
the next `--force-recreate` silently reverts it. Move the image, not the
container.

### When to turn it off

Turn it off when the image is your unit of deployment and something else already
gates changes — a review, a pipeline, a maintenance window. An agent that swaps
its own binary underneath a production service is routing around that gate, and
`docker inspect` stops being able to tell you what is running.

Leave it on for a demo stand, a workstation container, or anything where being
current matters more than being reproducible.

If you turn it off, read the section above first: a pinned image that lags the
release channel is not the version you thought you pinned.

### Root containers are not exempt

A container running as root **can** replace its own binary, so it never logs a
warning — it just drifts. On 2026-08-11 two production containers built from an
image carrying 1.1.143 were found executing 1.1.148: they had updated
themselves, and the next recreate would have reverted them with no message
either way. Same behaviour as the failure at the top of this page, minus the
symptom.

```bash
# what the image ships
docker run --rm --entrypoint cmdop <image> --version
# what is actually executing
docker compose exec <svc> cmdop --version
```

Those two agreeing is the property you are actually after.
