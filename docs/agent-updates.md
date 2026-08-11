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
{"level":"warn","component":"auto-update","version":"v1.1.148","refusal":"dir_not_writable","remedy":"Fix this in the image: give the running user ownership of the cmdop binary AND its directory, or turn auto-update off and ship updates by rebuilding the image.","message":"Auto-update: not downloading — this install cannot replace its own binary and nothing here can change that"}
```

`cmdop version` stays where it was.

Older releases behaved worse here in two ways worth knowing if you are reading
an old log. They advised `sudo cmdop update apply` — a workstation remedy, and
most containers have neither `sudo` nor anyone to run it. And they downloaded
the release before discovering they could not install it, so each hourly attempt
re-fetched ~100 MB into the cache under `HOME` — usually a volume, so it was
your disk that grew. Current releases name the cause, address the remedy to
whoever can act on it, and skip the download entirely when nothing in the
container could install the result.

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
while `install.cmdop.com` served 1.1.149 — six releases apart. Re-measured the
next day: the tag still served 1.1.143 against a channel on 1.1.151, now eight
apart, because that lane had not changed and correctly was not rebuilt. The gap
is not a backlog that someone is behind on; it is what the tag means.

| You want | Use |
|---|---|
| a cacheable layer and no build-time network — **only with self-update on**, since the container boots on the tag's version and needs to catch up | `COPY --from=markolofsen/cmdop:latest /cmdop …` |
| the current release baked in, so the container is current from its first second | `RUN curl -fsSL https://install.cmdop.com \| sh -s -- --prefix=…` |

The pairing that quietly hurts is `COPY --from` **plus** `CMDOP_NO_AUTO_UPDATE`:
nothing then ever moves the version, and the tag's last rebuild becomes your
permanent release. If you turn auto-update off, install from the channel.

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

It also leaves **no trace that distinguishes it from a self-update** — the
versions drift apart exactly the same way. So resist the temptation to upgrade a
container by hand "just this once": you have not moved the deployment, you have
only made its version harder to explain. This has already misled the people who
wrote this page.

### When to turn it off

Turn it off when the image is your unit of deployment and something else already
gates changes — a review, a pipeline, a maintenance window. An agent that swaps
its own binary underneath a production service is routing around that gate, and
`docker inspect` stops being able to tell you what is running.

Leave it on for a demo stand, a workstation container, or anything where being
current matters more than being reproducible.

If you turn it off, read the section above first: a pinned image that lags the
release channel is not the version you thought you pinned.

## A container that CAN update drifts from its image

The failure at the top of this page is loud: the update cannot install, and the
log says so hourly. Its mirror image is quiet. When the update *succeeds* —
because the directory is writable, which is what you get for free in a container
running as root — the binary is now newer than the image that supposedly defines
it. Nothing is broken; the version just stops being described by your image.

Two consequences, and the second is the one that surprises people:

- `docker inspect` and `docker run --entrypoint cmdop <image> --version` report
  the image's version, and are no longer the answer to "what is running".
- The next `--force-recreate`, redeploy or host reboot starts from the image
  again, so **the version goes backwards** — silently, and then climbs back on
  its own within a day.

```bash
# what a recreate would give you
docker run --rm --entrypoint cmdop <image> --version
# what is actually executing right now
docker compose exec <svc> cmdop --version
```

With auto-update on, those two are **allowed to differ, and the running one
wins**. That is the design, not a fault. Requiring them to agree is only
meaningful right after a rebuild — which is the point: a rebuild is how a
version becomes durable here, not how it arrives.

> **Do not diagnose this from the versions alone.** A container that is ahead of
> its image has *either* self-updated *or* been updated by hand — a person
> running `cmdop update` inside it leaves exactly the same evidence. On
> 2026-08-12 three containers on one host were ahead of their images and only
> one of them had done it by itself; the other two had `CMDOP_NO_AUTO_UPDATE=1`
> set the whole time. The log settles it: look for `Update applied successfully`
> (the scheduler) versus `Update scheduler skipped` (something else did it).
