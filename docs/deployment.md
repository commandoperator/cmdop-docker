# Public deployment and networking

## Cmdop public relay

To reuse the managed address provisioned for the organization behind
`CMDOP_API_KEY`:

```dotenv
CMDOP_RELAY_MODE=public
CMDOP_PUBLIC_SUBDOMAIN=
```

To request a specific available label:

```dotenv
CMDOP_RELAY_MODE=public
CMDOP_PUBLIC_SUBDOMAIN=my-live-demo
```

Restart Compose. The installed CLI generates the current server config and the
relay connects outward to the Cmdop edge. The console then becomes available at
an address such as `https://my-live-demo.cmdop.dev`.

`auto` selects public mode when `CMDOP_PUBLIC_SUBDOMAIN` is set and otherwise
uses LAN mode. Explicit `public` with an empty label asks the platform for the
organization's existing address. If none exists, startup stops with an
actionable error. The generated YAML contains the address but not the platform
key; `cmdop server` reads `CMDOP_ROUTER_API_KEY` from process memory.

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

The optional torrent downloader needs outbound TCP and UDP to peers, trackers,
and DHT nodes. No inbound torrent port is published: Cmdop currently uses a
download-only client with uploading, seeding, UPnP, and default port forwarding
disabled, and asks the OS for an ephemeral listen port. A fixed mapping such as
`42069` would not help until Cmdop exposes a stable configurable listen port.

## Site exposure is separate

The managed Cmdop address exposes the relay console, not the Vite site. For a
temporary remote demo, place authenticated TLS reverse proxies in front of the
required ports, forward WebSocket upgrade headers, and set
`VITE_HMR_CLIENT_PORT` if the public WebSocket port differs from the page port.

This Compose stack is a live-editing demo, not a hardened production web
server. For a normal production site, build the Vite application and serve
`demo/dist` from a production web server or static hosting platform.
