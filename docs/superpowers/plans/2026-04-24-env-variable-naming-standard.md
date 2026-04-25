# .env Variable Naming Standard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename all lowercase `.env` variables to `UPPER_SNAKE_CASE` across every stack, update all `compose.yml` references to match, and add structured container-name comments to every `.env` and `.env.example` file.

**Architecture:** Pure mechanical rename — no logic changes. Every `${lowercase_var}` reference in compose files is updated to `${UPPERCASE_VAR}`. Each `.env` / `.env.example` file is rewritten with variables grouped under container-name comments. CLAUDE.md naming convention table is updated to reflect the new unified standard.

**Tech Stack:** Docker Compose, bash `.env` files

---

## File Map

| File | Change |
|---|---|
| `arr-stack/.env` | Rename vars, add container comments |
| `arr-stack/.env.example` | Rename vars, add container comments |
| `arr-stack/compose.yml` | Update `${lowercase}` refs to `${UPPERCASE}` |
| `jellyfin/.env` | Rename vars, add container comments |
| `jellyfin/.env.example` | Rename vars, add container comments |
| `jellyfin/compose.yml` | Update `${lowercase}` refs to `${UPPERCASE}` |
| `lan-apps/.env` | Rename vars, add container comments |
| `lan-apps/.env.example` | Rename vars, add container comments |
| `lan-apps/compose.yml` | Update `${lowercase}` refs to `${UPPERCASE}` |
| `proxied-apps/.env` | Rename vars, add container comments |
| `proxied-apps/.env.example` | Rename vars, add container comments |
| `proxied-apps/compose.yml` | Update `${audiobooks}`, `${podcasts}` refs |
| `monitoring/.env` | Rename vars, add container comments |
| `monitoring/.env.example` | Add container comments (already empty/minimal) |
| `immich/.env` | Verify all vars already uppercase |
| `immich/.env.example` | Verify all vars already uppercase |
| `.env` (root) | Rename vars, add container comments |
| `.env.example` (root) | Rename vars, add container comments |
| `nginx-proxy/.env` | Verify already uppercase |
| `nginx-proxy/.env.example` | Verify already uppercase |
| `scheduler/.env` | Verify already uppercase |
| `scheduler/.env.example` | Verify already uppercase |
| `CLAUDE.md` | Update naming convention table |

---

## Task 1: arr-stack — rename .env and .env.example

**Files:**
- Modify: `arr-stack/.env`
- Modify: `arr-stack/.env.example`

- [ ] **Step 1: Rewrite `arr-stack/.env`**

Replace the entire file with:

```bash
# ── General ───────────────────────────────────────────────────────────────────
TZ=America/Chicago

# ── Gluetun (VPN) ─────────────────────────────────────────────────────────────
VPN_USERNAME=p4913068
VPN_PASSWORD=

# ── qBittorrent ───────────────────────────────────────────────────────────────
QBITTORRENT_DOWNLOADS=/mnt/wd_hdd_1tb/qbittorrent
QBITTORRENT_USER=admin
QBITTORRENT_PASS=D7iMYyJCUQxSEj

# ── Shared media library paths ────────────────────────────────────────────────
MOVIES=/mnt/media/movies
OTHER_MOVIES=/mnt/media/other_media/movies
TV_SHOWS=/mnt/media/tv_shows
OTHER_SHOWS=/mnt/media/other_media/shows
KIDS_MOVIES=/mnt/media/kids_movies
KIDS_TV_SHOWS=/mnt/media/kids_tv_shows

# ── Radarr / Sonarr / Prowlarr (Decluttarr, Recyclarr) ───────────────────────
RADARR_API_KEY=
SONARR_API_KEY=
PROWLARR_API_KEY=
```

- [ ] **Step 2: Rewrite `arr-stack/.env.example`**

Replace the entire file with:

```bash
# ── General ───────────────────────────────────────────────────────────────────
TZ=America/Chicago

# ── Gluetun (VPN) ─────────────────────────────────────────────────────────────
VPN_USERNAME=
VPN_PASSWORD=

# ── qBittorrent ───────────────────────────────────────────────────────────────
QBITTORRENT_DOWNLOADS=
QBITTORRENT_USER=
QBITTORRENT_PASS=

# ── Shared media library paths ────────────────────────────────────────────────
MOVIES=
OTHER_MOVIES=
TV_SHOWS=
OTHER_SHOWS=
KIDS_MOVIES=
KIDS_TV_SHOWS=

# ── Radarr / Sonarr / Prowlarr (Decluttarr, Recyclarr) ───────────────────────
RADARR_API_KEY=
SONARR_API_KEY=
PROWLARR_API_KEY=
```

- [ ] **Step 3: Commit**

```bash
git add arr-stack/.env arr-stack/.env.example
git commit -m "chore: uppercase all .env variable names in arr-stack"
```

---

## Task 2: arr-stack — update compose.yml references

**Files:**
- Modify: `arr-stack/compose.yml`

- [ ] **Step 1: Replace all lowercase variable references**

In `arr-stack/compose.yml`, make these replacements (exact string substitution):

| Find | Replace |
|---|---|
| `${vpn_username}` | `${VPN_USERNAME}` |
| `${vpn_password}` | `${VPN_PASSWORD}` |
| `${qbittorrent_downloads}` | `${QBITTORRENT_DOWNLOADS}` |
| `${movies}` | `${MOVIES}` |
| `${other_movies}` | `${OTHER_MOVIES}` |
| `${tv_shows}` | `${TV_SHOWS}` |
| `${other_shows}` | `${OTHER_SHOWS}` |
| `${kids_movies}` | `${KIDS_MOVIES}` |
| `${kids_tv_shows}` | `${KIDS_TV_SHOWS}` |

Affected lines (search for each):
- `OPENVPN_USER=${vpn_username}` → `OPENVPN_USER=${VPN_USERNAME}`
- `OPENVPN_PASSWORD=${vpn_password}` → `OPENVPN_PASSWORD=${VPN_PASSWORD}`
- `${qbittorrent_downloads}:/downloads` appears in radarr, sonarr, and qbittorrent services
- `${movies}:/movies` in radarr; `${movies}:/media/movies` would not appear here but check
- `${tv_shows}:/tv_shows` in sonarr
- `${kids_tv_shows}:/kids_tv_shows` in sonarr, bazarr
- `${kids_movies}:/kids_movies` in radarr, bazarr
- `${other_movies}:/other_movies` in radarr
- `${other_shows}:/other_shows` in sonarr
- `QB_WEBUI_USER: ${QBITTORRENT_USER}` — already uppercase, no change
- `QB_WEBUI_PASSWORD: ${QBITTORRENT_PASS}` — already uppercase, no change

- [ ] **Step 2: Verify no lowercase refs remain**

```bash
grep -n '\${[a-z]' arr-stack/compose.yml
```

Expected: no output (empty).

- [ ] **Step 3: Commit**

```bash
git add arr-stack/compose.yml
git commit -m "chore: update arr-stack compose.yml to use UPPER_SNAKE_CASE env vars"
```

---

## Task 3: jellyfin — rename .env and .env.example

**Files:**
- Modify: `jellyfin/.env`
- Modify: `jellyfin/.env.example`

- [ ] **Step 1: Rewrite `jellyfin/.env`**

Replace the entire file with:

```bash
# ── General ───────────────────────────────────────────────────────────────────
TZ=America/Chicago

# ── Jellyfin ──────────────────────────────────────────────────────────────────
JELLYFIN_URL=https://jellyfin.ohmygoshwhatever.com

# ── Shared media library paths ────────────────────────────────────────────────
MOVIES=/mnt/media/movies
OTHER_MOVIES=/mnt/media/other_media/movies
TV_SHOWS=/mnt/media/tv_shows
OTHER_SHOWS=/mnt/media/other_media/shows
KIDS_MOVIES=/mnt/media/kids_movies
KIDS_TV_SHOWS=/mnt/media/kids_tv_shows
PINCHFLAT_DOWNLOADS=/mnt/media/pinchflat
HOME_MOVIES=/mnt/media/home_movies
```

- [ ] **Step 2: Rewrite `jellyfin/.env.example`**

Replace the entire file with:

```bash
# ── General ───────────────────────────────────────────────────────────────────
TZ=America/Chicago

# ── Jellyfin ──────────────────────────────────────────────────────────────────
JELLYFIN_URL=

# ── Shared media library paths ────────────────────────────────────────────────
MOVIES=
OTHER_MOVIES=
TV_SHOWS=
OTHER_SHOWS=
KIDS_MOVIES=
KIDS_TV_SHOWS=
PINCHFLAT_DOWNLOADS=
HOME_MOVIES=
```

- [ ] **Step 3: Commit**

```bash
git add jellyfin/.env jellyfin/.env.example
git commit -m "chore: uppercase all .env variable names in jellyfin"
```

---

## Task 4: jellyfin — update compose.yml references

**Files:**
- Modify: `jellyfin/compose.yml`

- [ ] **Step 1: Replace all lowercase variable references**

In `jellyfin/compose.yml`, make these replacements:

| Find | Replace |
|---|---|
| `${jellyfin_url}` | `${JELLYFIN_URL}` |
| `${movies}` | `${MOVIES}` |
| `${tv_shows}` | `${TV_SHOWS}` |
| `${kids_movies}` | `${KIDS_MOVIES}` |
| `${kids_tv_shows}` | `${KIDS_TV_SHOWS}` |
| `${other_movies}` | `${OTHER_MOVIES}` |
| `${other_shows}` | `${OTHER_SHOWS}` |
| `${pinchflat_downloads}` | `${PINCHFLAT_DOWNLOADS}` |
| `${home_movies}` | `${HOME_MOVIES}` |

- [ ] **Step 2: Verify no lowercase refs remain**

```bash
grep -n '\${[a-z]' jellyfin/compose.yml
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add jellyfin/compose.yml
git commit -m "chore: update jellyfin compose.yml to use UPPER_SNAKE_CASE env vars"
```

---

## Task 5: lan-apps — rename .env and .env.example

**Files:**
- Modify: `lan-apps/.env`
- Modify: `lan-apps/.env.example`

- [ ] **Step 1: Rewrite `lan-apps/.env`**

Replace the entire file with:

```bash
# ── General ───────────────────────────────────────────────────────────────────
TZ=America/Chicago

# ── Pinchflat ─────────────────────────────────────────────────────────────────
PINCHFLAT_DOWNLOADS=/mnt/media/pinchflat

# ── Plex ──────────────────────────────────────────────────────────────────────
PLEX_CLAIM=

# ── Kometa ────────────────────────────────────────────────────────────────────
# Kometa config lives in its /config volume.
# Do not commit real Plex tokens or TMDb API keys.
PLEX_URL=http://plex:32400
PLEX_TOKEN=
TMDB_API_KEY=

# ── Shared media library paths ────────────────────────────────────────────────
MOVIES=/mnt/media/movies
OTHER_MOVIES=/mnt/media/other_media/movies
TV_SHOWS=/mnt/media/tv_shows
OTHER_SHOWS=/mnt/media/other_media/shows
KIDS_MOVIES=/mnt/media/kids_movies
KIDS_TV_SHOWS=/mnt/media/kids_tv_shows
MUSIC=/mnt/media/music
HOME_MOVIES=/mnt/media/home_movies
```

- [ ] **Step 2: Rewrite `lan-apps/.env.example`**

Replace the entire file with:

```bash
# ── General ───────────────────────────────────────────────────────────────────
TZ=America/Chicago

# ── Pinchflat ─────────────────────────────────────────────────────────────────
PINCHFLAT_DOWNLOADS=

# ── Plex ──────────────────────────────────────────────────────────────────────
PLEX_CLAIM=

# ── Kometa ────────────────────────────────────────────────────────────────────
# Kometa config lives in its /config volume.
# Do not commit real Plex tokens or TMDb API keys.
PLEX_URL=http://plex:32400
PLEX_TOKEN=
TMDB_API_KEY=

# ── Shared media library paths ────────────────────────────────────────────────
MOVIES=
OTHER_MOVIES=
TV_SHOWS=
OTHER_SHOWS=
KIDS_MOVIES=
KIDS_TV_SHOWS=
MUSIC=
HOME_MOVIES=
```

- [ ] **Step 3: Commit**

```bash
git add lan-apps/.env lan-apps/.env.example
git commit -m "chore: uppercase all .env variable names in lan-apps"
```

---

## Task 6: lan-apps — update compose.yml references

**Files:**
- Modify: `lan-apps/compose.yml`

- [ ] **Step 1: Replace all lowercase variable references**

In `lan-apps/compose.yml`, make these replacements:

| Find | Replace |
|---|---|
| `${pinchflat_downloads}` | `${PINCHFLAT_DOWNLOADS}` |
| `${plex_claim}` | `${PLEX_CLAIM}` |
| `${movies}` | `${MOVIES}` |
| `${tv_shows}` | `${TV_SHOWS}` |
| `${kids_movies}` | `${KIDS_MOVIES}` |
| `${kids_tv_shows}` | `${KIDS_TV_SHOWS}` |
| `${other_movies}` | `${OTHER_MOVIES}` |
| `${other_shows}` | `${OTHER_SHOWS}` |
| `${music}` | `${MUSIC}` |
| `${home_movies}` | `${HOME_MOVIES}` |

Note: `${PLEX_URL}`, `${PLEX_TOKEN}`, `${TMDB_API_KEY}` are already uppercase — no change needed.

- [ ] **Step 2: Verify no lowercase refs remain**

```bash
grep -n '\${[a-z]' lan-apps/compose.yml
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add lan-apps/compose.yml
git commit -m "chore: update lan-apps compose.yml to use UPPER_SNAKE_CASE env vars"
```

---

## Task 7: proxied-apps — rename .env and .env.example, update compose.yml

**Files:**
- Modify: `proxied-apps/.env`
- Modify: `proxied-apps/.env.example`
- Modify: `proxied-apps/compose.yml`

- [ ] **Step 1: Rewrite `proxied-apps/.env`**

Replace the entire file with:

```bash
# ── General ───────────────────────────────────────────────────────────────────
TZ=America/Chicago

# ── Audiobookshelf ────────────────────────────────────────────────────────────
AUDIOBOOKS=/mnt/media/audiobooks
PODCASTS=/mnt/media/podcasts
```

- [ ] **Step 2: Rewrite `proxied-apps/.env.example`**

Replace the entire file with:

```bash
# ── General ───────────────────────────────────────────────────────────────────
TZ=America/Chicago

# ── Audiobookshelf ────────────────────────────────────────────────────────────
AUDIOBOOKS=
PODCASTS=
```

- [ ] **Step 3: Update `proxied-apps/compose.yml`**

Make these replacements in `proxied-apps/compose.yml`:

| Find | Replace |
|---|---|
| `${audiobooks}` | `${AUDIOBOOKS}` |
| `${podcasts}` | `${PODCASTS}` |

- [ ] **Step 4: Verify no lowercase refs remain**

```bash
grep -n '\${[a-z]' proxied-apps/compose.yml
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add proxied-apps/.env proxied-apps/.env.example proxied-apps/compose.yml
git commit -m "chore: uppercase all .env variable names in proxied-apps"
```

---

## Task 8: monitoring — rename .env and .env.example

**Files:**
- Modify: `monitoring/.env`
- Modify: `monitoring/.env.example`

- [ ] **Step 1: Rewrite `monitoring/.env`**

Replace the entire file with:

```bash
# ── General ───────────────────────────────────────────────────────────────────
DOCKER_GID=986

# ── Watchtower ────────────────────────────────────────────────────────────────
EMAIL=blake.b.8726@gmail.com
GMAIL_APP_PASSWORD=

# ── Grafana ───────────────────────────────────────────────────────────────────
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=
```

- [ ] **Step 2: Rewrite `monitoring/.env.example`**

Replace the entire file with:

```bash
# ── General ───────────────────────────────────────────────────────────────────
DOCKER_GID=

# ── Watchtower ────────────────────────────────────────────────────────────────
EMAIL=
GMAIL_APP_PASSWORD=

# ── Grafana ───────────────────────────────────────────────────────────────────
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=
```

- [ ] **Step 3: Commit**

```bash
git add monitoring/.env monitoring/.env.example
git commit -m "chore: uppercase all .env variable names in monitoring"
```

---

## Task 9: monitoring — update compose.yml references

**Files:**
- Modify: `monitoring/compose.yml`

The monitoring compose currently has no lowercase variable references (Grafana vars are already uppercase). However, Watchtower in the root compose references `email` and `gmail_app_passwd`. Check monitoring compose first.

- [ ] **Step 1: Confirm monitoring/compose.yml has no lowercase refs**

```bash
grep -n '\${[a-z]' monitoring/compose.yml
```

Expected: no output. If any appear, replace them with their uppercase equivalent per the rename map. If the output is empty, skip to the commit.

- [ ] **Step 2: Commit (only if changes were made)**

```bash
git add monitoring/compose.yml
git commit -m "chore: update monitoring compose.yml to use UPPER_SNAKE_CASE env vars"
```

---

## Task 10: root .env and .env.example

**Files:**
- Modify: `.env`
- Modify: `.env.example`

- [ ] **Step 1: Rewrite root `.env`**

Replace the entire file with:

```bash
# ── Docker Compose ────────────────────────────────────────────────────────────
# Keeps volume names consistent if directory is renamed
COMPOSE_PROJECT_NAME=media-stack

# ── General ───────────────────────────────────────────────────────────────────
TZ=America/Chicago
LOCAL_IP=192.168.1.200

# ── Shared media library paths ────────────────────────────────────────────────
MOVIES=/mnt/media/movies
OTHER_MOVIES=/mnt/media/other_media/movies
TV_SHOWS=/mnt/media/tv_shows
OTHER_SHOWS=/mnt/media/other_media/shows
KIDS_MOVIES=/mnt/media/kids_movies
KIDS_TV_SHOWS=/mnt/media/kids_tv_shows
MUSIC=/mnt/media/music
BOOKS=/mnt/media/books
PODCASTS=/mnt/media/podcasts
AUDIOBOOKS=/mnt/media/audiobooks
HOME_MOVIES=/mnt/media/home_movies
MEDIA_PATH=/mnt/media/

# ── qBittorrent ───────────────────────────────────────────────────────────────
QBITTORRENT_DOWNLOADS=/mnt/wd_hdd_1tb/qbittorrent
QBITTORRENT_USER=admin
QBITTORRENT_PASS=D7iMYyJCUQxSEj

# ── Pinchflat ─────────────────────────────────────────────────────────────────
PINCHFLAT_DOWNLOADS=/mnt/media/pinchflat

# ── Gluetun (VPN) ─────────────────────────────────────────────────────────────
VPN_USERNAME=p4913068
VPN_PASSWORD=

# ── Jellyfin ──────────────────────────────────────────────────────────────────
JELLYFIN_URL=https://jellyfin.ohmygoshwhatever.com

# ── Jellyseerr ────────────────────────────────────────────────────────────────
# Configure Jellyseerr from the web UI after first launch.
JELLYSEERR_URL=

# ── Plex ──────────────────────────────────────────────────────────────────────
PLEX_CLAIM=

# ── Kometa ────────────────────────────────────────────────────────────────────
# Do not commit real Plex tokens or TMDb API keys.
PLEX_URL=http://plex:32400
PLEX_TOKEN=
TMDB_API_KEY=

# ── Pi-hole ───────────────────────────────────────────────────────────────────
PIHOLE_PASSWORD=

# ── Radarr / Sonarr / Prowlarr (Decluttarr) ──────────────────────────────────
RADARR_API_KEY=
SONARR_API_KEY=
PROWLARR_API_KEY=

# ── Watchtower ────────────────────────────────────────────────────────────────
DOCKER_GID=986
EMAIL=blake.b.8726@gmail.com
GMAIL_APP_PASSWORD=
WATCHTOWER_NOTIFICATION_EMAIL_FROM=blake.b.8726@gmail.com
WATCHTOWER_NOTIFICATION_EMAIL_TO=blake.b.8726@gmail.com
WATCHTOWER_NOTIFICATION_EMAIL_SERVER=smtp.gmail.com
WATCHTOWER_NOTIFICATION_EMAIL_SERVER_PORT=587
WATCHTOWER_NOTIFICATION_EMAIL_SERVER_USER=blake.b.8726@gmail.com
WATCHTOWER_NOTIFICATION_EMAIL_SERVER_PASSWORD=
WATCHTOWER_NOTIFICATION_EMAIL_DELAY=2

# ── Grafana ───────────────────────────────────────────────────────────────────
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=

# ── Immich ────────────────────────────────────────────────────────────────────
# https://immich.app/docs/install/environment-variables
IMMICH_VERSION=v2
IMMICH_ML_VERSION=v2
UPLOAD_LOCATION=/mnt/immich/Immich/upload
DB_DATA_LOCATION=/mnt/immich/Immich/postgres
REDIS_PASSWORD=
DB_PASSWORD=
DB_USERNAME=postgres
DB_DATABASE_NAME=immich
DB_IMAGE=ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0

# ── Backup tuning ─────────────────────────────────────────────────────────────
# Compression level: 1=fastest/larger, 9=slowest/smaller
BACKUP_GZIP_LEVEL=6
# Compressor: auto, pigz, or gzip
BACKUP_COMPRESSOR=auto
```

- [ ] **Step 2: Rewrite root `.env.example`**

Replace the entire file with:

```bash
# ── Docker Compose ────────────────────────────────────────────────────────────
# Keeps volume names consistent if directory is renamed
COMPOSE_PROJECT_NAME=media-stack

# ── General ───────────────────────────────────────────────────────────────────
TZ=America/Chicago
LOCAL_IP=

# ── Shared media library paths ────────────────────────────────────────────────
MOVIES=
OTHER_MOVIES=
TV_SHOWS=
OTHER_SHOWS=
KIDS_MOVIES=
KIDS_TV_SHOWS=
MUSIC=
BOOKS=
PODCASTS=
AUDIOBOOKS=
HOME_MOVIES=
MEDIA_PATH=

# ── qBittorrent ───────────────────────────────────────────────────────────────
QBITTORRENT_DOWNLOADS=
QBITTORRENT_USER=
QBITTORRENT_PASS=

# ── Pinchflat ─────────────────────────────────────────────────────────────────
PINCHFLAT_DOWNLOADS=

# ── Gluetun (VPN) ─────────────────────────────────────────────────────────────
VPN_USERNAME=
VPN_PASSWORD=

# ── Jellyfin ──────────────────────────────────────────────────────────────────
JELLYFIN_URL=

# ── Jellyseerr ────────────────────────────────────────────────────────────────
# Configure Jellyseerr from the web UI after first launch.
JELLYSEERR_URL=

# ── Plex ──────────────────────────────────────────────────────────────────────
PLEX_CLAIM=

# ── Kometa ────────────────────────────────────────────────────────────────────
# Kometa config lives in its /config volume.
# Do not commit real Plex tokens or TMDb API keys.
PLEX_URL=http://plex:32400
PLEX_TOKEN=
TMDB_API_KEY=

# ── Pi-hole ───────────────────────────────────────────────────────────────────
PIHOLE_PASSWORD=

# ── Radarr / Sonarr / Prowlarr (Decluttarr) ──────────────────────────────────
RADARR_API_KEY=
SONARR_API_KEY=
PROWLARR_API_KEY=

# ── Watchtower ────────────────────────────────────────────────────────────────
DOCKER_GID=
EMAIL=
GMAIL_APP_PASSWORD=
WATCHTOWER_NOTIFICATION_EMAIL_FROM=
WATCHTOWER_NOTIFICATION_EMAIL_TO=
WATCHTOWER_NOTIFICATION_EMAIL_SERVER=smtp.gmail.com
WATCHTOWER_NOTIFICATION_EMAIL_SERVER_PORT=587
WATCHTOWER_NOTIFICATION_EMAIL_SERVER_USER=
WATCHTOWER_NOTIFICATION_EMAIL_SERVER_PASSWORD=
WATCHTOWER_NOTIFICATION_EMAIL_DELAY=2

# ── Grafana ───────────────────────────────────────────────────────────────────
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=

# ── Immich ────────────────────────────────────────────────────────────────────
# https://immich.app/docs/install/environment-variables
IMMICH_VERSION=v2
IMMICH_ML_VERSION=v2
UPLOAD_LOCATION=
DB_DATA_LOCATION=
REDIS_PASSWORD=
DB_PASSWORD=
DB_USERNAME=postgres
DB_DATABASE_NAME=immich
DB_IMAGE=docker.io/tensorchord/pgvecto-rs:pg14-v0.2.0@sha256:90724186f0a3517cf6914295b5ab410db9ce23190a2d9d0b9dd6463e3fa298f0

# ── Backup tuning ─────────────────────────────────────────────────────────────
# Compression level: 1=fastest/larger, 9=slowest/smaller
BACKUP_GZIP_LEVEL=6
# Compressor: auto, pigz, or gzip
BACKUP_COMPRESSOR=auto
```

- [ ] **Step 3: Commit**

```bash
git add .env .env.example
git commit -m "chore: uppercase all .env variable names in root stack"
```

---

## Task 11: Update CLAUDE.md naming convention table

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update the naming convention table**

Find this section in `CLAUDE.md`:

```markdown
| Artifact | Convention | Example |
|----------|-----------|---------|
| Stack-defined `.env` variables | `lower_snake_case` | `qbittorrent_downloads` |
| App-required `.env` variables | `UPPER_SNAKE_CASE` | `RADARR_API_KEY` |
```

Replace with:

```markdown
| Artifact | Convention | Example |
|----------|-----------|---------|
| All `.env` variables | `UPPER_SNAKE_CASE` | `QBITTORRENT_DOWNLOADS` |
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md naming convention to UPPER_SNAKE_CASE for all .env vars"
```

---

## Task 12: Final verification

- [ ] **Step 1: Confirm no lowercase variable references remain in any compose.yml**

```bash
grep -rn '\${[a-z]' \
  jellyfin/compose.yml \
  arr-stack/compose.yml \
  lan-apps/compose.yml \
  proxied-apps/compose.yml \
  monitoring/compose.yml \
  immich/compose.yml \
  nginx-proxy/compose.yml \
  scheduler/compose.yml 2>/dev/null
```

Expected: no output. If any matches appear, fix them using the rename map from the spec.

- [ ] **Step 2: Confirm no lowercase variable definitions remain in any .env or .env.example**

```bash
grep -rn '^[a-z][a-zA-Z_]*=' \
  .env .env.example \
  arr-stack/.env arr-stack/.env.example \
  jellyfin/.env jellyfin/.env.example \
  lan-apps/.env lan-apps/.env.example \
  proxied-apps/.env proxied-apps/.env.example \
  monitoring/.env monitoring/.env.example \
  immich/.env immich/.env.example \
  nginx-proxy/.env nginx-proxy/.env.example \
  scheduler/.env scheduler/.env.example 2>/dev/null
```

Expected: no output (lines starting with `#` are excluded by the `^[a-z]` pattern).

- [ ] **Step 3: Smoke-test one stack config loads correctly**

```bash
docker compose -f arr-stack/compose.yml config --quiet
```

Expected: exits 0 with no errors. This validates Docker Compose can parse all variable substitutions.

- [ ] **Step 4: Final commit if any stragglers were fixed in steps 1-2**

```bash
git add -p
git commit -m "chore: fix remaining lowercase env var references found in final verification"
```
