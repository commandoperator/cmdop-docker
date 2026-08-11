# Public deployment and networking

## Cmdop public relay

To request a specific available label — the right shape for any account that
runs, or may ever run, more than one machine:

```dotenv
CMDOP_RELAY_MODE=public
CMDOP_PUBLIC_SUBDOMAIN=my-live-demo
```

To reuse the managed address provisioned for the organization behind
`CMDOP_API_KEY` — only safe while this container is the org's ONLY public
machine:

```dotenv
CMDOP_RELAY_MODE=public
CMDOP_PUBLIC_SUBDOMAIN=
```

An empty label means "adopt whatever address my organization already owns". If
another machine (a laptop, a second container) already serves that address, the
two will re-register the same hostname at the edge and keep displacing each
other — each looks briefly online and then loses the address to the other. Pin
an explicit label per machine and the conflict cannot exist.

Restart Compose. The installed CLI generates the current server config and the
relay connects outward to the Cmdop edge. The console then becomes available at
an address such as `https://my-live-demo.cmdop.dev`.

`auto` selects public mode when `CMDOP_PUBLIC_SUBDOMAIN` is set and otherwise
uses LAN mode. Explicit `public` with an empty label asks the platform for the
organization's existing address. If none exists, startup stops with an
actionable error. The generated YAML contains the address but not the platform
key; `cmdop server` reads `CMDOP_ROUTER_API_KEY` from process memory.

Managed addresses are metered per plan: the Free plan includes one
`*.cmdop.dev` address per organization, paid plans include several, so one
account can run a laptop and a container each on its own address in parallel.
Several machines may connect through one relay's tunnel without consuming
extra addresses. An empty `CMDOP_PUBLIC_SUBDOMAIN` reuses the organization's
authoritative address; it does not invent a new hostname for every container
recreation.

## Ports and firewall

- `8080 -> 5173/TCP`: local Vite site.
- `63141 -> 63141/TCP`: local Cmdop console.
- `63142/TCP`: internal relay gRPC listener; not published by default.
- `proxy.cmdop.dev:4443/TCP`: required outbound mTLS in public relay mode.
- `<subdomain>.cmdop.dev:443/TCP`: public edge address; this belongs to the
  Cmdop edge, not the Compose container.

Both host mappings bind to loopback by default. Set
`HOST_BIND_ADDRESS=0.0.0.0` only for deliberate LAN access, and then protect the
console with the host firewall and a strong password. Publish `63142` only when
separate LAN machines must enroll directly.

An address such as `172.19.0.2` in logs or the console is the container's
private Compose bridge address. On Colima that bridge lives inside its Linux VM.
It is normal, is not the managed public URL, and should not be opened in a
browser from another machine.

The optional torrent downloader needs outbound TCP and UDP to peers, trackers,
and DHT nodes. No inbound torrent port is published: Cmdop currently uses a
download-only client with uploading, seeding, UPnP, and default port forwarding
disabled, and asks the OS for an ephemeral listen port. A fixed mapping such as
`42069` would not help until Cmdop exposes a stable configurable listen port.

## Site exposure is separate

The managed Cmdop address exposes the relay console, not the Vite site. For a
temporary remote demo, place TLS reverse proxies in front of the required ports,
forward WebSocket upgrade headers, and set `VITE_HMR_CLIENT_PORT` if the public
WebSocket port differs from the page port.

### Two hostnames, not two paths

Give the site and the console a hostname each. Sharing one origin behind path
prefixes does not work without rewriting both applications' internals in the
proxy: Vite serves its client and modules from absolute paths (`/@vite/client`,
`/src/…`, `/@react-refresh`) and the console is an SPA rooted at `/`.

### Vite rejects an unknown Host — plan for it

A proxied request arrives with the public hostname in `Host`, and Vite answers

```
403  Blocked request. This host ("demo.example.com") is not allowed.
```

That check is a DNS-rebinding defence and is worth keeping. Two ways through it:

1. **Declare the hostname** — add it to `server.allowedHosts` in
   `demo/vite.config.js`. Correct when you control this repository.
2. **Rewrite `Host` at the proxy** to `localhost`, which Vite always accepts.
   Correct when you must not fork the image. The page still works because the
   browser derives the HMR WebSocket URL from its own location plus
   `VITE_HMR_CLIENT_PORT`, not from what the proxy forwards.

A Traefik example of the second, for a page published on 443:

```yaml
labels:
  - "traefik.http.middlewares.vitehost.headers.customrequestheaders.Host=localhost"
  - "traefik.http.routers.site.rule=Host(`demo.example.com`)"
  - "traefik.http.routers.site.middlewares=vitehost"
  - "traefik.http.services.site.loadbalancer.server.port=5173"
```

with `VITE_HMR_CLIENT_PORT=443` in the environment. Verify all three, because a
site that loads is not yet a site that live-edits:

```bash
curl -o /dev/null -w '%{http_code}\n' https://demo.example.com/@vite/client
curl -s https://demo.example.com/__demo_revision
curl -o /dev/null -w '%{http_code}\n' -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
     -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
     https://demo.example.com/
```

### What you are publishing when you publish this

This Compose stack is a live-editing demo, not a hardened production web server.
Two consequences deserve a decision rather than a default:

**A Vite dev server is not built to face the internet.** Its file-serving
surface has produced a steady run of advisories — arbitrary file read through
`@fs` handling, `server.fs.deny` bypasses via queries, backslashes, double
slashes, and Windows alternate paths (CVE-2025-30208, CVE-2025-58752,
CVE-2026-39363/39364/39365, CVE-2026-53571). Each was fixed promptly, and each
required the same precondition: the dev server had to be reachable. Running a
current Vite closes the known holes; it does not change the shape of the
surface. Pin an exact version (this repository does), watch the advisories, and
decide deliberately whether the address may be anonymous. If it may not, put
authentication in the proxy — that is one middleware, and it removes the
precondition every one of those advisories needs.

**Whoever reaches the console can rewrite what the site says.** That is the
demo working as designed, and on a public hostname it is also a defacement
path. Keep `CMDOP_PERMISSIONS_MODE=default`; `bypass` on a public address is
not a convenience setting, it is an open shell in the container.

Nothing above applies to a normal production site: build the Vite application
and serve `demo/dist` from a production web server or static hosting platform.
