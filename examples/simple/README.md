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
cp .env.example .env      # fill it in, see below
docker compose up --build
```

Your app serves on <http://localhost:3000>; the machine appears in your fleet
with terminal, file access and AI chat.

### Where is the relay?

`CMDOP_SERVER_URL` points at a **relay** — the thing your machines join and you
connect through. This example is a *member*: it dials out, it never listens.
Something else has to be the relay, and you have three ways to get one:

| The relay is… | `CMDOP_SERVER_URL` | When |
|---|---|---|
| **your own machine** | `http://host.docker.internal:63141` | trying this out — run `cmdop server` on your laptop, the container dials back to it |
| **a machine you host** | `https://<your-host>:63141` | you already run Cmdop on a server |
| **the managed tier** | `https://<your-team>.cmdop.dev` | you want an address without hosting one; the relay registers it for you |

In every case the relay is where `cmdop server join-key` prints the key you put
in `CMDOP_JOIN_KEY` — the two settings always come from the same place.

> **Hosting a relay is a different job from joining one**, which is why this
> example does not do it: a relay listens, holds `server.db`, owns the console
> password, and — on the managed tier — registers a public address. The one in
> this repository that does host a relay is [`../original`](../original).

### Two credentials, and they are not the same thing

This is the part that trips people up: **joining the fleet and paying for
inference are separate.**

| Credential | What it does | Where to get it |
|---|---|---|
| `CMDOP_JOIN_KEY` | lets this machine **join** the fleet | `cmdop server join-key` on the relay host |
| `CMDOP_ROUTER_API_KEY` | pays for **inference** — the AI part | <https://my.cmdop.com> |

With the join key alone the machine connects and the terminal and file access
work fine; AI chat just has nothing to think with. With neither, `sidecar` is a
plain `exec` and your app runs as if Cmdop were not there.

## How it works

`sidecar` starts the agent in the background, then **`exec`s** your command. That word
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

## Settings that are not optional

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
That is [`../original`](../original).
