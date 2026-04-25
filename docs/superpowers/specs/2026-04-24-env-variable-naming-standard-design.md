# .env Variable Naming Standard

**Date:** 2026-04-24
**Status:** Approved

## Summary

Standardize all `.env` and `.env.example` variable names across every stack to `UPPER_SNAKE_CASE`. Update all `compose.yml` references and `CLAUDE.md` to match. Add structured container-name comments above each variable group.

## The Standard

- **All `.env` variables use `UPPER_SNAKE_CASE`.** No exceptions — path variables, credentials, flags, URLs, and app-required variables all follow the same rule.
- **Group comments** appear above each logical cluster of variables, naming the container(s) they apply to. Format: `# ── ContainerName ───...`
- **Shared variables** (e.g. media library paths used by multiple stacks) use `# ── Shared media library paths ───`.

### Comment style example

```bash
# ── Shared media library paths ────────────────────────────────────────────────
MOVIES=
TV_SHOWS=
KIDS_MOVIES=

# ── Radarr / Sonarr / Prowlarr (Decluttarr) ──────────────────────────────────
RADARR_API_KEY=
SONARR_API_KEY=
PROWLARR_API_KEY=
```

## Variable Rename Map

All variables below are renamed from their old lowercase form to the new uppercase form.

| Old name | New name |
|---|---|
| `qbittorrent_downloads` | `QBITTORRENT_DOWNLOADS` |
| `pinchflat_downloads` | `PINCHFLAT_DOWNLOADS` |
| `movies` | `MOVIES` |
| `other_movies` | `OTHER_MOVIES` |
| `tv_shows` | `TV_SHOWS` |
| `other_shows` | `OTHER_SHOWS` |
| `kids_movies` | `KIDS_MOVIES` |
| `kids_tv_shows` | `KIDS_TV_SHOWS` |
| `music` | `MUSIC` |
| `podcasts` | `PODCASTS` |
| `audiobooks` | `AUDIOBOOKS` |
| `home_movies` | `HOME_MOVIES` |
| `jellyfin_url` | `JELLYFIN_URL` |
| `vpn_username` | `VPN_USERNAME` |
| `vpn_password` | `VPN_PASSWORD` |
| `plex_claim` | `PLEX_CLAIM` |
| `jellyseerr_url` | `JELLYSEERR_URL` |
| `email` | `EMAIL` |
| `gmail_app_passwd` | `GMAIL_APP_PASSWORD` |
| `local_ip` | `LOCAL_IP` |
| `pihole_password` | `PIHOLE_PASSWORD` |
| `media_path` | `MEDIA_PATH` |
| `books` | `BOOKS` |

Variables already in `UPPER_SNAKE_CASE` (e.g. `RADARR_API_KEY`, `GRAFANA_ADMIN_USER`, `TZ`, `DB_PASSWORD`, Django/Postgres/Redis vars) are left unchanged.

## Scope of Changes

### `.env` and `.env.example` files (all stacks)
- `./` (root)
- `arr-stack/`
- `immich/`
- `jellyfin/`
- `lan-apps/`
- `monitoring/`
- `nginx-proxy/`
- `proxied-apps/`
- `scheduler/`

Each file gets:
1. Variable names uppercased per the rename map
2. Variables reorganized into groups with container-name comments

### `compose.yml` files
All `${lowercase_var}` references updated to `${UPPERCASE_VAR}`:
- `jellyfin/compose.yml` — `${movies}`, `${tv_shows}`, `${other_movies}`, `${other_shows}`, `${kids_movies}`, `${kids_tv_shows}`, `${pinchflat_downloads}`, `${home_movies}`, `${jellyfin_url}`
- `arr-stack/compose.yml` — `${vpn_username}`, `${vpn_password}`, `${qbittorrent_downloads}`, `${movies}`, `${other_movies}`, `${tv_shows}`, `${other_shows}`, `${kids_movies}`, `${kids_tv_shows}`
- `lan-apps/compose.yml` — `${pinchflat_downloads}`, `${plex_claim}`, `${movies}`, `${other_movies}`, `${tv_shows}`, `${other_shows}`, `${kids_movies}`, `${kids_tv_shows}`, `${music}`, `${home_movies}`
- `proxied-apps/compose.yml` — `${audiobooks}`, `${podcasts}`
- `monitoring/compose.yml` — `${email}`, `${gmail_app_passwd}`
- `immich/compose.yml` — already mostly uppercase; verify no lowercase refs remain

### `CLAUDE.md`
- Remove the `lower_snake_case` row from the naming convention table for stack-defined `.env` variables
- Replace with a single `UPPER_SNAKE_CASE` rule covering all `.env` variables

### Shell scripts
- Grep `scripts/linux/` for any direct references to old lowercase variable names and update them

## What Does Not Change

- Named volume keys in `compose.yml` (`lower_snake_case + _data` suffix) — these are Docker volume names, not env vars
- Service names and `container_name` values (`kebab-case`)
- Script filenames (`kebab-case`)
- Backup directory naming (`YYYYMMDD-NNN`)
- The `COMPOSE_PROJECT_NAME` variable (already uppercase, stays as-is)
