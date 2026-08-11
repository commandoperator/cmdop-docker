# simple — an agent beside your own app

The smallest thing that works: your image, unchanged, plus two lines.

```dockerfile
COPY --from=markolofsen/cmdop:latest /cmdop /usr/local/bin/cmdop
ENTRYPOINT ["cmdop", "sidecar", "--"]
```

Everything else in this directory is an ordinary Node app, and it is here only
so the container has something to run. Swap it for Python, Go, Rails — the
agent does not care what it rides along with.

## Run it

```bash
cp .env.example .env      # fill in CMDOP_SERVER_URL + CMDOP_JOIN_KEY
docker compose up --build
```

Your app serves on <http://localhost:3000>; the machine appears in your fleet
with terminal, file access and AI chat.

## What `sidecar` actually does

It starts the agent in the background, then **`exec`s** your command. That word
is the whole design — your process becomes PID 1:

- `docker stop` delivers SIGTERM to **your** app (`app.js` prints it), and your
  graceful shutdown runs unchanged;
- the container's exit code is **your** exit code;
- `restart:` policies behave exactly as before.

Three consequences worth knowing:

- **A failing agent never blocks your app.** Wrong key, unreachable relay, no
  network — it is logged, and your command still starts.
- **No join key, no agent.** With the variables unset, `sidecar` is a plain
  `exec`. The same image runs unchanged where it was never enrolled.
- **Your flags stay yours.** Everything after `--` passes through untouched.

## The two settings that are not optional

| Setting | Why |
|---|---|
| `CMDOP_MACHINE_NAME` | without it the name comes from the container hostname, which Docker regenerates on every recreate — the fleet fills with hex-named strangers |
| `HOME` on a volume | identity, credential and state live there; without it every recreate is honestly a new machine to the relay |

And one rule about that volume: **it is for state, never for executables.** A
binary installed into a volume is seeded once and then outlives every later
image build, so a rebuild silently keeps running the old one. Copy `cmdop` to an
image path, as the Dockerfile above does.

## Any base image

The binary links no libc, so Alpine, Debian, distroless and even `scratch` all
work. This example uses `node:24-slim` only because the sample app is Node.

---

Want to see the agent editing a live project instead of riding along with one?
That is [`../demo`](../demo).
