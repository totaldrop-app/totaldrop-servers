# TotalDrop Servers (`totaldrop-servers`)

Standalone server and edge-worker repository for [TotalDrop](https://totaldrop.app), synced with upstream commit `ebe2b19`. This repository packages both production Cloudflare Workers and self-hostable Rust daemons, together with isolated per-architecture Linux systemd and NAS/Homelab OCI deployment units.

All rendezvous and relay implementations are zero-log, keep state strictly in memory or ephemeral per-transfer objects, reject browser WebSockets carrying an `Origin` header with HTTP `403` (`#450`), and never inspect end-to-end encrypted payloads.

## Architecture and Layout

```text
totaldrop-servers/
  Cargo.toml                           Rust workspace (edition 2024, resolver 3, rust-version 1.99)
  REUSE.toml                           REUSE 3.3 copyright and license annotations
  crates/
    totaldrop-proto/                   Wire framing, CBOR rules, transfer codes, relay framing, STUN/PCP/PMP
  cloudflare-rendezvous/               Cloudflare Worker + Directory & Mailbox Durable Objects
  cloudflare-relay/                    Cloudflare Worker + Hibernatable Pair Durable Object
  rust-shared/
    totaldrop-rendezvous/              Self-hosted Rust rendezvous server (WebSocket mailbox service)
    totaldrop-relay/                   Self-hosted Rust relay server (WebSocket datagram relay + UDP discovery)
    tools/probe.mjs                    Post-deploy health probe for rendezvous, relay, and site
  tools/
    check-spdx.sh                      Verifies SPDX headers on all tracked source files
  target-linux-x86_64/
    build.sh                           Builds x86_64-unknown-linux-gnu / x86_64-unknown-linux-musl binaries
    totaldrop-rendezvous.service       Hardened x86_64 systemd unit (DynamicUser, ProtectSystem=strict)
    totaldrop-relay.service            Hardened x86_64 systemd unit (CAP_NET_BIND_SERVICE for UDP 443)
    oci-homelab/
      Containerfile                    Multi-stage musl build -> scratch & distroless non-root images
      Caddyfile                        TLS 1.3 reverse proxy config (HTTP/1.1 + HTTP/2; UDP 443 free for relay)
      compose.yaml                     Compose stack for Synology DSM, Unraid, TrueNAS SCALE, x86_64 Homelab
  target-linux-arm64/
    build.sh                           Builds aarch64-unknown-linux-gnu / aarch64-unknown-linux-musl binaries
    totaldrop-rendezvous.service       Hardened ARM64 systemd unit (SystemCallArchitectures=aarch64)
    totaldrop-relay.service            Hardened ARM64 systemd unit (SystemCallArchitectures=aarch64)
    oci-homelab/
      Containerfile                    Multi-stage ARM64 musl build -> scratch & distroless non-root images
      Caddyfile                        TLS 1.3 reverse proxy config for ARM64 Homelab
      compose.yaml                     Compose stack for Raspberry Pi 5, ARM64 NAS, and Ampere Homelab
```

## Protocol Endpoints and Security Invariants

### Rendezvous (`totaldrop-rendezvous` and `cloudflare-rendezvous`)

| Endpoint | Purpose |
| --- | --- |
| `GET /v0/allocate` | Upgrades to WebSocket, accepts one `allocate` CBOR frame, returns `allocated` with nameplate and 16-byte allocation token |
| `GET /v0/mailbox/<n>` | Upgrades to WebSocket for `claim`, `add`, and `close` on mailbox `<n>` |

- **Origin header rejection (`#450`):** Any WebSocket upgrade request carrying an `Origin` header (sent by every browser, never by TotalDrop native apps or CLI) receives HTTP `403` before any rate-limit token is spent.
- **Per-client rate limiting:** Keyed by IPv4 `/32` or IPv6 `/64` under an in-memory random key; allows a burst of 60 allocations/mailbox openings and replenishes 1 per second. Refused lookups are not counted.
- **Ephemeral lifecycle:** Unclaimed mailboxes expire after 15 minutes; claimed mailboxes live at most 1 hour and are erased as soon as both sides close. Failed nameplates rest 24 hours before reuse; cleanly closed nameplates rest 10 minutes.

### Relay (`totaldrop-relay` and `cloudflare-relay`)

| Endpoint | Purpose |
| --- | --- |
| `GET /v0/relay/<key A>-<key B>` | Upgrades to WebSocket; both peers prove possession of their single-use Ed25519 endpoint keys over a fresh 32-byte challenge and exchange encrypted QUIC datagrams |
| `UDP :443` (Rust relay) | Authenticated STUN-style address discovery so peers learn their reflexive UDP address |

- **Origin header rejection (`#450`):** Browser WebSocket upgrades with an `Origin` header are refused with HTTP `403`.
- **Flow control and quotas:** Connections are bounded to 6 hours and 32 GiB; backpressure probes every 4 MiB bound unacknowledged buffered data per socket (32 MiB) and per key (64 MiB).

## Development and Verification

### Rust Workspace

Requires Rust `1.99` or newer (`edition = "2024"`, `unsafe_code = "forbid"`):

```bash
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo test --workspace --locked
./tools/check-spdx.sh
```

### Cloudflare Workers

Requires Node.js `22.18+` (`24 LTS` in CI with native TypeScript test execution):

```bash
(cd cloudflare-rendezvous && npm ci --ignore-scripts && npm run check && npm test)
(cd cloudflare-relay && npm ci --ignore-scripts && npm run check && npm test)
node --check rust-shared/tools/probe.mjs
```

## Building Native Linux Binaries

Each architecture unit provides an isolated `build.sh` that compiles locked release binaries (`lto = true`, `codegen-units = 1`, `strip = true`) and writes `SHA256SUMS` under `dist/`:

```bash
# x86_64 Linux (glibc or static musl)
./target-linux-x86_64/build.sh --gnu
./target-linux-x86_64/build.sh --musl

# ARM64 / aarch64 Linux (glibc or static musl)
./target-linux-arm64/build.sh --gnu
./target-linux-arm64/build.sh --musl
```

## Self-Hosting Deployment Options

### 1. Hardened `systemd` Services (Debian / Ubuntu / Fedora / Arch)

Install the compiled binaries to `/usr/local/bin/` and copy the matching architecture's `.service` files into `/etc/systemd/system/`:

- [`target-linux-x86_64/totaldrop-rendezvous.service`](target-linux-x86_64/totaldrop-rendezvous.service) / [`target-linux-arm64/totaldrop-rendezvous.service`](target-linux-arm64/totaldrop-rendezvous.service)
- [`target-linux-x86_64/totaldrop-relay.service`](target-linux-x86_64/totaldrop-relay.service) / [`target-linux-arm64/totaldrop-relay.service`](target-linux-arm64/totaldrop-relay.service)

Every service runs under `DynamicUser=yes`, `NoNewPrivileges=yes`, `ProtectSystem=strict`, `ProtectHome=yes`, `MemoryDenyWriteExecute=yes`, `SystemCallFilter=@system-service`, and architecture-locked syscall filters (`x86-64` or `aarch64`). Place a TLS 1.3 reverse proxy (see [`rust-shared/totaldrop-relay/deploy/Caddyfile`](rust-shared/totaldrop-relay/deploy/Caddyfile)) in front of loopback ports `127.0.0.1:4000` (rendezvous) and `127.0.0.1:4100` (relay).

### 2. Homelab & NAS OCI Containers (`x86_64` and `arm64`)

Multi-stage `Containerfile`s compile static `musl` binaries and package them into zero-shell `FROM scratch` per-service targets (`rendezvous` and `relay`) as well as a combined `distroless/static-debian12:nonroot` runtime image (`UID/GID 65532:65532`, `read_only: true`, `cap_drop: [ALL]`, `no-new-privileges:true`):

```bash
# Synology DSM / Unraid / TrueNAS SCALE / x86_64 Homelab
RENDEZVOUS_HOST=rendezvous.example.org RELAY_HOST=relay.example.org \
  docker compose -f target-linux-x86_64/oci-homelab/compose.yaml up -d --build

# Raspberry Pi 5 / ARM64 NAS / Ampere Homelab
RENDEZVOUS_HOST=rendezvous.example.org RELAY_HOST=relay.example.org \
  docker compose -f target-linux-arm64/oci-homelab/compose.yaml up -d --build
```

## Licensing

- `rust-shared/totaldrop-rendezvous`, `rust-shared/totaldrop-relay`, `cloudflare-rendezvous`, `cloudflare-relay`, and deployment units: **AGPL-3.0-or-later** ([`LICENSES/AGPL-3.0-or-later.txt`](LICENSES/AGPL-3.0-or-later.txt)).
- `crates/totaldrop-proto`: **MIT OR Apache-2.0** ([`LICENSES/MIT.txt`](LICENSES/MIT.txt), [`LICENSES/Apache-2.0.txt`](LICENSES/Apache-2.0.txt)).
