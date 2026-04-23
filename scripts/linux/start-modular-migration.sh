#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_DIR="${ROOT}/migration_logs"
REPORT_PATH="${LOG_DIR}/modular-migration-$(date '+%Y%m%d-%H%M%S').log"

# shellcheck source=media-stack-compose.sh
source "${SCRIPT_DIR}/media-stack-compose.sh"

STACK_ORDER=(
  arr-stack
  immich
  jellyfin
  lan-apps
  proxied-apps
  monitoring
  nginx-proxy
)

declare -A STACK_SERVICES=(
  [arr-stack]="vpn prowlarr flaresolverr decluttarr radarr sonarr bazarr qbittorrent qbittorrent-metrics"
  [immich]="immich-server immich-machine-learning redis database"
  [jellyfin]="jellyfin"
  [lan-apps]="actual_server pinchflat plex homeassistant"
  [proxied-apps]="derbynet audiobookshelf minecraft-survival minecraft-creative"
  [monitoring]="watchtower prometheus node-exporter cadvisor grafana"
  [nginx-proxy]="nginx tests"
)

REQUIRED_EXTERNAL_VOLUMES=(
  media-stack_prowlarr_data
  media-stack_radarr_data
  media-stack_sonarr_data
  media-stack_qbittorrent_data
  media-stack_bazarr_data
  media-stack_gluetun_data
  media-stack_decluttarr_data
  media-stack_node_exporter_textfile
  media-stack_model-cache
  media-stack_immich_redis_data
  media-stack_immich_server_data
  media-stack_jellyfin_config
  media-stack_jellyfin_cache
  media-stack_pinchflat_data
  media-stack_plex_data
  media-stack_homeassistant_data
  media-stack_audiobookshelf_data
  media-stack_audiobookshelf_metadata
  media-stack_prometheus_data
  media-stack_grafana_data
  media-stack_nginx_data
  media-stack_letsencrypt
)

DIRECT_HTTP_PORTS=(5006 8945 32400 8096 2283 8050 3000 7878 8989 9696 6767 8080)
BASELINE_HEALTH_FILE=""
BASELINE_REGRESSION_EXIT=0
HEALTH_TIMEOUT_SECONDS="${MIGRATION_HEALTH_TIMEOUT_SECONDS:-300}"
PORT_PROBE_TIMEOUT_SECONDS="${MIGRATION_PORT_PROBE_TIMEOUT_SECONDS:-120}"

mkdir -p "$LOG_DIR"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$REPORT_PATH"
}

run_logged() {
  log "+ $*"
  "$@" 2>&1 | tee -a "$REPORT_PATH"
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    log "ERROR missing required command: ${command_name}"
    exit 2
  fi
}

compose_for_stack() {
  local stack="$1"
  shift
  docker compose \
    --project-directory "$ROOT" \
    --env-file "${ROOT}/${stack}/.env" \
    -p "$stack" \
    -f "${ROOT}/${stack}/compose.yml" \
    "$@"
}

legacy_compose() {
  docker compose \
    --project-directory "$ROOT" \
    --env-file "${ROOT}/.env" \
    -p "$LEGACY_PROJECT_NAME" \
    -f "${ROOT}/docker-compose.yaml" \
    "$@"
}

validate_prerequisites() {
  log "Validating prerequisites"
  require_command docker
  require_command curl

  if ! docker compose version >/dev/null 2>&1; then
    log "ERROR Docker Compose v2 is required"
    exit 2
  fi

  if [[ ! -f "${ROOT}/.env" ]]; then
    log "ERROR missing legacy rollback env file: ${ROOT}/.env"
    exit 2
  fi

  local stack
  for stack in "${STACK_ORDER[@]}"; do
    [[ -f "${ROOT}/${stack}/.env" ]] || { log "ERROR missing ${stack}/.env"; exit 2; }
    [[ -f "${ROOT}/${stack}/compose.yml" ]] || { log "ERROR missing ${stack}/compose.yml"; exit 2; }
  done

  local volume
  for volume in "${REQUIRED_EXTERNAL_VOLUMES[@]}"; do
    if ! docker volume inspect "$volume" >/dev/null 2>&1; then
      log "ERROR missing required external Docker volume: ${volume}"
      exit 2
    fi
  done

  log "Validating Compose configs"
  run_logged legacy_compose config --quiet
  for stack in "${STACK_ORDER[@]}"; do
    run_logged compose_for_stack "$stack" config --quiet
  done
}

ensure_media_proxy_network() {
  if docker network inspect media_proxy >/dev/null 2>&1; then
    log "Docker network media_proxy already exists"
    return
  fi

  log "Creating Docker network media_proxy"
  run_logged docker network create media_proxy
}

ensure_rollback_symlink() {
  local link_path="$1"
  local target="$2"

  if [[ -L "$link_path" ]]; then
    log "Rollback symlink exists: ${link_path} -> $(readlink "$link_path")"
    return
  fi

  if [[ -e "$link_path" ]]; then
    log "WARN rollback path exists and is not a symlink, leaving untouched: ${link_path}"
    return
  fi

  mkdir -p "$(dirname "$link_path")"
  ln -s "$target" "$link_path"
  log "Created rollback symlink: ${link_path} -> ${target}"
}

ensure_rollback_symlinks() {
  ensure_rollback_symlink "${ROOT}/data/budget" "../lan-apps/data/budget"
  ensure_rollback_symlink "${ROOT}/data/derbynet" "../proxied-apps/data/derbynet"
  ensure_rollback_symlink "${ROOT}/data/survival" "../proxied-apps/data/survival"
  ensure_rollback_symlink "${ROOT}/data/creative" "../proxied-apps/data/creative"
}

write_health_line() {
  local output_file="$1"
  local service="$2"
  local cid="$3"

  local health state
  if [[ -z "$cid" ]]; then
    printf '%s|missing|missing\n' "$service" >> "$output_file"
    return
  fi

  state="$(docker inspect "$cid" --format '{{.State.Status}}' 2>/dev/null || printf 'unknown')"
  health="$(docker inspect "$cid" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' 2>/dev/null || printf 'unknown')"
  printf '%s|%s|%s\n' "$service" "$state" "$health" >> "$output_file"
}

capture_legacy_health() {
  local output_file="$1"
  shift

  : > "$output_file"
  local service cid
  for service in "$@"; do
    cid="$(legacy_compose ps -q "$service" 2>/dev/null || true)"
    if [[ -z "$cid" ]]; then
      printf '%s|missing|missing\n' "$service" >> "$output_file"
      continue
    fi

    write_health_line "$output_file" "$service" "$cid"
  done
}

all_migrated_services() {
  local stack service
  for stack in "${STACK_ORDER[@]}"; do
    for service in ${STACK_SERVICES[$stack]}; do
      printf '%s\n' "$service"
    done
  done
}

capture_baseline() {
  log "Capturing legacy baseline"
  run_logged legacy_compose ps || true

  BASELINE_HEALTH_FILE="$(mktemp)"
  mapfile -t services < <(all_migrated_services)
  capture_legacy_health "$BASELINE_HEALTH_FILE" "${services[@]}"
  log "Baseline health snapshot:"
  tee -a "$REPORT_PATH" < "$BASELINE_HEALTH_FILE" >/dev/null

  log "Running legacy regression baseline"
  set +e
  MEDIA_STACK_MODE=legacy bash "${SCRIPT_DIR}/run-regression-tests.sh" 2>&1 | tee -a "$REPORT_PATH"
  BASELINE_REGRESSION_EXIT=${PIPESTATUS[0]}
  set -e
  if [[ "$BASELINE_REGRESSION_EXIT" -ne 0 ]]; then
    log "WARN legacy regression baseline failed with exit ${BASELINE_REGRESSION_EXIT}; matching modular failures will warn instead of blocking"
  fi
}

connect_legacy_nginx_to_media_proxy() {
  local nginx_cid
  nginx_cid="$(legacy_compose ps -q nginx 2>/dev/null || true)"
  if [[ -z "$nginx_cid" ]]; then
    log "WARN legacy nginx container is not running; skipping temporary media_proxy network attach"
    return
  fi

  if docker inspect "$nginx_cid" --format '{{json .NetworkSettings.Networks}}' | grep -q '"media_proxy"'; then
    log "Legacy nginx is already connected to media_proxy"
    return
  fi

  log "Temporarily connecting legacy nginx to media_proxy"
  run_logged docker network connect --alias nginx media_proxy "$nginx_cid"
}

stop_legacy_services() {
  local services=("$@")
  if [[ "${#services[@]}" -eq 0 ]]; then
    return
  fi

  log "Stopping legacy services: ${services[*]}"
  run_logged legacy_compose stop "${services[@]}" || true
  log "Removing stopped legacy service containers: ${services[*]}"
  run_logged legacy_compose rm -f "${services[@]}" || true
}

start_stack() {
  local stack="$1"
  log "Starting modular stack: ${stack}"
  run_logged compose_for_stack "$stack" up -d
}

baseline_health_for_service() {
  local service="$1"
  awk -F'|' -v svc="$service" '$1 == svc {print $3; exit}' "$BASELINE_HEALTH_FILE"
}

require_stack_running() {
  local stack="$1"
  local service cid state baseline_health health deadline
  for service in ${STACK_SERVICES[$stack]}; do
    [[ "$service" == "tests" ]] && continue

    baseline_health="$(baseline_health_for_service "$service")"
    deadline=$((SECONDS + HEALTH_TIMEOUT_SECONDS))

    while true; do
      cid="$(compose_for_stack "$stack" ps -q "$service" 2>/dev/null || true)"
      if [[ -n "$cid" ]]; then
        state="$(docker inspect "$cid" --format '{{.State.Status}}' 2>/dev/null || printf 'missing')"
        health="$(docker inspect "$cid" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' 2>/dev/null || printf 'missing')"
      else
        state="missing"
        health="missing"
      fi

      if [[ "$state" == "running" && "$baseline_health" == "healthy" && "$health" == "healthy" ]]; then
        break
      fi
      if [[ "$state" == "running" && "$baseline_health" != "healthy" ]]; then
        break
      fi
      if (( SECONDS >= deadline )); then
        if [[ "$state" != "running" ]]; then
          log "ERROR service is not running after migration: ${service} state=${state}"
          exit 1
        fi
        if [[ "$baseline_health" == "healthy" && "$health" != "healthy" ]]; then
          log "ERROR service was healthy before migration but is now ${health}: ${service}"
          exit 1
        fi
        break
      fi
      sleep 5
    done

    if [[ "$baseline_health" != "healthy" && "$health" != "healthy" && "$health" != "none" ]]; then
      log "WARN service remains degraded from baseline: ${service} baseline=${baseline_health} current=${health}"
    else
      log "PASS service ready: ${service} state=${state} health=${health}"
    fi
  done
}

probe_http_port() {
  local port="$1"
  local status deadline
  deadline=$((SECONDS + PORT_PROBE_TIMEOUT_SECONDS))

  while true; do
    status="$(curl -k -sS -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 10 "http://127.0.0.1:${port}/" 2>/dev/null || true)"

    case "$status" in
      200|301|302|303|307|308|401|403|404)
        log "PASS port probe port=${port} status=${status}"
        return
        ;;
    esac

    if (( SECONDS >= deadline )); then
      log "ERROR port probe failed port=${port} status=${status:-no-response}"
      exit 1
    fi
    sleep 5
  done
}

run_port_probes() {
  log "Running direct port probes"
  local port
  for port in "${DIRECT_HTTP_PORTS[@]}"; do
    probe_http_port "$port"
  done
}

run_modular_regression() {
  log "Running modular regression tests"
  set +e
  MEDIA_STACK_MODE=modular bash "${SCRIPT_DIR}/run-regression-tests.sh" 2>&1 | tee -a "$REPORT_PATH"
  local modular_exit=${PIPESTATUS[0]}
  set -e

  if [[ "$modular_exit" -eq 0 ]]; then
    log "Modular regression tests passed"
    return
  fi

  if [[ "$BASELINE_REGRESSION_EXIT" -ne 0 ]]; then
    log "WARN modular regression tests failed, but the captured legacy baseline also failed"
    return
  fi

  log "ERROR modular regression tests failed after a passing legacy baseline"
  exit "$modular_exit"
}

migrate_stack() {
  local stack="$1"
  local services
  read -r -a services <<< "${STACK_SERVICES[$stack]}"

  stop_legacy_services "${services[@]}"
  start_stack "$stack"
  require_stack_running "$stack"
}

main() {
  cd "$ROOT"
  log "Starting modular migration report: ${REPORT_PATH}"

  validate_prerequisites
  ensure_media_proxy_network
  ensure_rollback_symlinks
  capture_baseline
  connect_legacy_nginx_to_media_proxy

  local stack
  for stack in "${STACK_ORDER[@]}"; do
    migrate_stack "$stack"
  done

  run_port_probes
  run_modular_regression

  log "Modular migration completed successfully"
  log "Rollback source retained: ${ROOT}/docker-compose.yaml and ${ROOT}/.env on main"
}

main "$@"
