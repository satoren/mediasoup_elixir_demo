# MediasoupElixirDemo

A multi-party voice/video chat demo built with [mediasoup-elixir](https://github.com/oviceinc/mediasoup-elixir) and Phoenix LiveView.
Rooms can span several Elixir nodes: each node runs its own mediasoup router and media is piped between routers on demand.

## Requirements

- Elixir 1.14+ (CI uses Elixir 1.16 / OTP 26)
- Node.js (CI uses 22) and Yarn 1.x, used to install [mediasoup-client](https://www.npmjs.com/package/mediasoup-client).
  JavaScript and CSS are built with Phoenix's standard esbuild and Tailwind tooling.
- A platform with a precompiled mediasoup NIF (Linux x86_64/aarch64 gnu/musl, macOS, ...).
  On other platforms the NIF is built from source, which requires Rust.

## Getting started

```sh
mix setup          # deps, esbuild/tailwind, yarn install in assets/, build assets
mix phx.server     # or: iex -S mix phx.server
```

Open [`localhost:4000`](http://localhost:4000) and turn on the microphone or camera with the buttons at the bottom.
In development the endpoint runs esbuild and Tailwind in watch mode.

Join a specific room with the `roomId` query parameter, e.g. `http://localhost:4000/?roomId=myroom` (default: `lobby`).

## Configuration

mediasoup settings live under `MediasoupElixirDemoWeb.SFURouter` in `config/{dev,test,runtime}.exs`:

| Key | Description |
| --- | --- |
| `worker` | mediasoup worker settings (`rtcMinPort` / `rtcMaxPort`, `logLevel`). The RTC port range must be reachable by clients. |
| `webrtc_server.listen_infos` | Where the WebRTC server listens. `announcedIp` must be an address clients can reach. |
| `pipe_transport.announced_ip` | IP announced to routers on **other nodes** for pipe transports. Routers on the same node always use `127.0.0.1`. |

The defaults announce `127.0.0.1`, which only works when the browser runs on the same machine.
Change the announced IPs to reach the server from other machines.

### Production

`config/runtime.exs` reads:

- `SECRET_KEY_BASE` (required, generate with `mix phx.gen.secret`)
- `PHX_HOST`, `PORT`
- `PHX_SERVER=true` to start the HTTP server in a release
- `DNS_CLUSTER_QUERY` to form a cluster with [DNSCluster](https://hexdocs.pm/dns_cluster)

Build the frontend with `mix assets.deploy`. Note that the announced IPs in `config/runtime.exs` are hard-coded to `127.0.0.1` and need to be adjusted for a real deployment.

## Architecture

```
Browser ── LiveView socket ── RoomLive ── SFURouter (per room, per node)
                                                           │  mediasoup Worker / Router / WebRtcServer
                                                           │
                         RouterGroup (:pg) ── PipeTransports between every pair of routers in the room
```

- **`RoomLive`** renders a room: the other users and their microphone/camera from Phoenix Presence (`UserPresence`), and the device toggles.
  It also handles the mediasoup signaling for its user (WebRTC transports, produce/consume, pause/resume and so on).
- **JS hooks** (`assets/js/hooks.js`): the `Room` hook owns the [mediasoup-client](https://mediasoup.org/documentation/v3/mediasoup-client/) device and transports,
  and starts/stops the local microphone and camera when `RoomLive` pushes a `media` event.
  Each remote `<audio>`/`<video>` element has a `Consumer` hook that consumes its producer.
  Signaling goes through `pushEvent` with replies over the LiveView socket.
- **`SFURouter`** is a GenServer owning a mediasoup worker and router.
  Each node normally runs one router per room, which stops about a minute after its last user leaves.
- **`RouterGroup`** (`:pg`) groups the routers of a room across the cluster.
  Every pair of routers in a room is connected by a `PipeTransport`.
- **Producer registry** (`:syn`, scope `:sfu_producers`): each producer is registered with the router that owns it.
  When a user consumes a producer that lives on another router, the local router looks up the source router and pipes the producer directly from it.
  Piped producers are closed again once their last consumer is gone.

## Development

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test

mix assets.build

cd assets
yarn lint
npx @biomejs/biome format ./js ./e2e

# End-to-end tests with Playwright against a running `mix phx.server`.
# Two browsers join a room and check that audio and video are received.
npx playwright install chromium
yarn e2e
```

The same checks, including the end-to-end tests, run in GitHub Actions (`.github/workflows/ci.yml`).
