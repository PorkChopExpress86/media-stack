# Security Audit — Remaining Actions
_Audited: 2026-04-22 | Re-reviewed: 2026-04-23 against modular compose stacks_

---

## 🔴 CRITICAL

- [x] **`homeassistant` — `network_mode: host` researched and retained (compensating controls added)**
  - **Finding**: `network_mode: host` is the **officially documented and recommended** Docker configuration for HomeKit Bridge. HomeKit uses mDNS (UDP multicast `224.0.0.251:5353`) for both initial pairing and ongoing keep-alive with the Apple home hub. Docker bridge networks do not pass multicast. The alternative (`advertise_ip` + avahi reflector) is secondary and has known pairing instability — unacceptable for door lock control.
  - **Decision**: Retain `network_mode: host`. The risk surface is bounded: HA is already the home automation hub; it legitimately needs LAN access.
  - **Compensating controls applied** (in `lan-apps/compose.yml`):
    - Added `security_opt: [no-new-privileges:true]` — prevents privilege escalation from within the container
    - Added service-level `mem_limit`, `mem_reservation`, and `cpus` — memory capped at 2 GB, CPU at 2 cores (bounds blast radius of misbehavior)
    - Added `healthcheck` on `http://localhost:8123` — Docker auto-restarts on failure, keeping locks/lights responsive
    - Added explanatory comment in compose file documenting why host mode is required
  - **Remaining risk**: Container still runs as root. HA does not support `PUID/PGID` env vars. This is a known upstream limitation — see https://github.com/home-assistant/core/issues for non-root progress.
  - **UFW**: `scripts/fix_homekit_firewall.sh` already opens ports 21064/tcp and 5353/udp. Verify these rules survive reboots with `sudo ufw status numbered`.

- [x] **`derbynet`, `actual_server`, `audiobookshelf`, `pinchflat` — running as root**
  - All services now have `user: "1000:1000"` in their respective modular compose files (`proxied-apps/compose.yml`, `lan-apps/compose.yml`). Validated 2026-04-23.

- [x] **`immich-server` and `immich-machine-learning` — running as root**
  - Both services now have `user: "1000:1000"` in `immich/compose.yml`. Validated 2026-04-23.

---

## 🟠 HIGH

- [x] **Direct port bindings on all interfaces — reviewed with user-approved exceptions**
  - Some host bindings are intentionally public or LAN-visible based on how this stack is used. Those are acceptable **as designed**, not accidental exposures:

  | Service | Port | Status |
  |---------|------|--------|
  | `nginx` | `80:80`, `443:443` | public edge proxy (intended) |
  | `nginx` | `127.0.0.1:81:81` | admin UI restricted to localhost / Tailscale |
  | `jellyfin` | `8096:8096`, `7359:7359/udp` | keep LAN-visible for streaming |
  | `plex` | `32400:32400` | keep LAN-visible for streaming / remote Plex |
  | `immich-server` | `2283:2283` | keep on the local network per Immich's documented behavior |
  | `audiobookshelf` | `13378:80` | keep on the local network |
  | `minecraft-survival` / `minecraft-creative` | `19132:19132/udp`, `19133:19133/udp` | intentionally exposed for LAN and external access |
  | `vpn` | `7878`, `8989`, `9696`, `8080`, `1080`, `8888`, `6767`, `8388` | mostly for dependent services; minimize only if the access model changes |

  - Still worth localizing if you later decide they should be proxy-only: `actual_server`, `derbynet`, and `pinchflat`.
  - If you want to tighten those later, prefix their host ports with `127.0.0.1:` and route them through nginx.

- [x] **`redis` — no authentication configured**
  - `immich_redis` container now uses `redis-server --requirepass "${REDIS_PASSWORD}"`.
  - `immich-server` and `immich-machine-learning` now receive the documented `REDIS_HOSTNAME` / `REDIS_PASSWORD` environment variables.
- [x] **`Nginx proxy manager root exception`**
- [x] **`DB_PASSWORD` — verified and not the example placeholder**
  - `.env.example` comments "change it to a random password" but the variable is blank. An empty or default Postgres password is exploitable from any container on the compose network.
  - Fix: confirm `.env` has a strong random value (`openssl rand -hex 32`). Rotate if unsure.

- [x] **No `read_only: true` on stateless services**
  - `decluttarr`, `redis`, `immich-machine-learning` are confirmed read-only with `tmpfs` mounts.
  - `flaresolverr` had `tmpfs` entries but `read_only: true` was dropped during the modular migration — **restored 2026-04-23** in `arr-stack/compose.yml`.

- [x] **No resource limits on any service**
  - `homeassistant` now has Compose-enforced CPU and memory caps using service-level `cpus`, `mem_limit`, and `mem_reservation`.
  - Remaining services can be tightened further if desired, but the previously identified Home Assistant exception is now addressed.

- [ ] **`watchtower` — docker.sock access is a container escape vector**
  - Even though `watchtower` is hardened (`user: "1000:1000"`, `group_add: DOCKER_GID`, `--monitor-only`), docker.sock access grants full container-lifecycle control if the process is compromised.
  - `--monitor-only` flag is confirmed present in `monitoring/compose.yml:29`.
  - Action: evaluate switching to Renovate + Dependabot for image updates so docker.sock access can be removed entirely.

---

## 🟡 MEDIUM

- [ ] **`vpn` — `cap_add: NET_ADMIN` is overly broad**
  - `NET_ADMIN` grants network namespace manipulation, routing table changes, and firewall modification. If gluetun is compromised, it can redirect all VPN-routed container traffic.
  - Action: review gluetun changelog for `CAP_NET_ADMIN` decomposition. Pin to the `cap_drop: [ALL]` + minimal caps pattern once gluetun supports it.

- [x] **Missing healthcheck on `pinchflat`**
  - All other services that were missing healthchecks (`derbynet`, `radarr`, `sonarr`, `bazarr`, `prowlarr`, `flaresolverr`, `decluttarr`, `plex`, `homeassistant`, `actual_server`, `audiobookshelf`) now have them. Only `pinchflat` (`lan-apps/compose.yml`) is still missing one.
  - Fix: add an HTTP healthcheck against `http://127.0.0.1:8945`.

- [ ] **`minecraft-creative` — `ALLOW_CHEATS: "true"` on a network-accessible server**
  - Cheats enabled on a server exposed to the LAN (via nginx UDP ports 19133) allows any authenticated player to run game-level commands.
  - Action: confirm this is intentional. If the server is family-only, document the decision. If not, set `ALLOW_CHEATS: "false"`.

- [ ] **`plex` — `plex_claim` token in `.env`**
  - `PLEX_CLAIM` tokens expire in 4 minutes and are single-use, but if an old value lingers in `.env` it could be probed.
  - Fix: after initial claim succeeds, remove `PLEX_CLAIM` from `.env` and the service definition (`lan-apps/compose.yml:54`).

- [ ] **`immich-server` — uses `IMMICH_VERSION=v2` floating tag in `.env`**
  - Floating version tags can pull unexpected breaking changes. `immich/compose.yml` defers to `${IMMICH_VERSION:-release}`, so a `docker compose pull` can advance to an untested release.
  - Fix: pin `IMMICH_VERSION` to a specific release tag (e.g., `v2.3.4`) and update intentionally.

- [ ] **`database` (Postgres) — `DB_USERNAME=postgres` is the default superuser**
  - Running Immich as the `postgres` superuser is unnecessary and widens blast radius if the app is compromised.
  - Fix: create a dedicated limited-privilege Postgres role for Immich (`immich_user` with access only to `immich` DB).

---

## 🔵 LOW / HARDENING

- [ ] **Add `no-new-privileges: true` to all services**
  - Prevents setuid/setgid escalation within containers. Has no runtime impact on the services in this stack. Currently only `homeassistant` (`lan-apps/compose.yml`) has this.
  - Fix: add `security_opt: [no-new-privileges:true]` globally or per-service.

- [ ] **Add `cap_drop: [ALL]` + minimal `cap_add` to non-root services**
  - Services running as UID 1000 still inherit default Linux capabilities (e.g., `NET_BIND_SERVICE`, `SETUID`).
  - Fix: apply `cap_drop: [ALL]` to `watchtower`, `jellyfin`, `radarr`, `sonarr`, `bazarr`, `qbittorrent`, `prowlarr`.

- [ ] **Dependabot schedule is weekly — consider shortening for high-risk images**
  - `nginx`, `vpn` (gluetun), `immich-server`, and `redis` are internet-facing or security-critical.
  - Fix: add a second `updates:` block in `.github/dependabot.yml` for critical services with `interval: daily`.

- [ ] **No centralised security-event log scanning**
  - Logs are capped at 30 MB per service but there is no alerting on suspicious patterns (auth failures, crash loops, OOM kills).
  - Fix: route container logs to Loki (already monitoring stack exists via Grafana/Prometheus) and add alert rules for restart-count spikes and error-rate thresholds.

- [ ] **`minecraft-survival` and `minecraft-creative` — `stdin_open: true` + `tty: true`**
  - These flags keep a TTY attached to the container, which allows `docker attach` to drop into a server console as the container user.
  - Action: review whether remote `docker attach` access is gated. If the daemon socket is reachable from non-admin users, this is a lateral movement path.

---

## ✅ Already Hardened (no action needed)

- [x] **Monitoring stack and qBittorrent/VPN dashboard added**
  - Prometheus, node-exporter, cAdvisor, and Grafana are deployed and healthy.
  - A qBittorrent metrics sidecar now writes Prometheus textfile metrics for download speed, upload speed, torrent queue state, and Gluetun health.
  - Grafana provisions the media overview dashboard plus a dedicated qBittorrent/VPN dashboard.

- [x] **`proxied-apps/data/` secret files gitignored** — `proxied-apps/data/**/*` is excluded; only `.gitkeep` is tracked. DerbyNet credential files are not committed.

- `watchtower` — non-root (`user: "1000:1000"`, `group_add: DOCKER_GID`), `--monitor-only`
- `jellyfin` — non-root (`user: "1000:1000"`, `group_add` for render/video devices)
- All image references pinned by SHA256 digest
- Log rotation configured globally (`max-size: 10m`, `max-file: 3`)
- `.env` and `data/` excluded from git via `.gitignore`
- Dependabot configured for weekly Docker digest updates
- nginx admin port bound to `127.0.0.1:81` only
- VPN namespace regression tests validate routing isolation for all *arr services
- Socket-mount-validation skill + probe script for watchtower docker.sock regression
