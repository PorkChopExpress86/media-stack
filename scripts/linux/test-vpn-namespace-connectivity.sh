#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_PATH="${VPN_NAMESPACE_LOG_PATH:-${PROJECT_ROOT}/vpn-namespace-connectivity.log}"

# shellcheck source=media-stack-compose.sh
source "${SCRIPT_DIR}/media-stack-compose.sh"

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log_line() {
  local line="$1"
  mkdir -p "$(dirname "$LOG_PATH")"
  printf '%s\n' "$line" | tee -a "$LOG_PATH"
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    log_line "[$(timestamp)] ERROR missing required command: ${command_name}"
    exit 2
  fi
}

get_service_cid() {
  local service="$1"
  compose_service_id "$service"
}

check_namespace_alignment() {
  local service="$1"
  local vpn_id="$2"
  local cid mode expected

  cid="$(get_service_cid "$service")"
  if [[ -z "$cid" ]]; then
    log_line "[$(timestamp)] FAIL service=${service} check=namespace reason=container-missing"
    return 1
  fi

  mode="$(docker inspect "$cid" --format '{{.HostConfig.NetworkMode}}')"
  expected="container:${vpn_id}"

  if [[ "$mode" == "$expected" ]]; then
    log_line "[$(timestamp)] PASS service=${service} check=namespace network_mode=${mode}"
    return 0
  fi

  log_line "[$(timestamp)] FAIL service=${service} check=namespace network_mode=${mode} expected=${expected}"
  return 1
}

http_status_from_service() {
  local service="$1"
  local url="$2"

  compose_cmd_for_stack arr-stack exec -T "$service" sh -c "curl -sS -I --max-time 15 '$url' | sed -n '1p'" 2>/dev/null | awk '{print $2}'
}

check_http_status() {
  local service="$1"
  local url="$2"
  local expected="$3"
  local label="$4"
  local status

  status="$(http_status_from_service "$service" "$url")"

  if [[ -z "$status" ]]; then
    log_line "[$(timestamp)] FAIL service=${service} check=${label} url=${url} reason=no-response"
    return 1
  fi

  if [[ "$status" == "$expected" ]]; then
    log_line "[$(timestamp)] PASS service=${service} check=${label} url=${url} status=${status}"
    return 0
  fi

  log_line "[$(timestamp)] FAIL service=${service} check=${label} url=${url} status=${status} expected=${expected}"
  return 1
}

extract_section_ip() {
  local section="$1"
  docker exec bazarr sh -c "awk '/^${section}:/{in_section=1;next} /^[a-z_]+:/{if(in_section){exit}} in_section && /^  ip:/{print \$2; exit}' /config/config/config.yaml" 2>/dev/null || true
}

check_bazarr_config_target() {
  local section="$1"
  local expected="$2"
  local actual

  actual="$(extract_section_ip "$section")"

  if [[ "$actual" == "$expected" ]]; then
    log_line "[$(timestamp)] PASS service=bazarr check=config-${section}-ip value=${actual}"
    return 0
  fi

  log_line "[$(timestamp)] FAIL service=bazarr check=config-${section}-ip value=${actual:-missing} expected=${expected}"
  return 1
}

main() {
  require_command docker

  : > "$LOG_PATH"

  local vpn_cid vpn_id
  vpn_cid="$(get_service_cid "vpn")"
  if [[ -z "$vpn_cid" ]]; then
    log_line "[$(timestamp)] ERROR service=vpn reason=container-missing"
    exit 3
  fi

  vpn_id="$(docker inspect "$vpn_cid" --format '{{.Id}}')"
  log_line "[$(timestamp)] START vpn namespace/connectivity regression run: vpn_id=${vpn_id}"

  local failures=0

  local vpn_shared_services=(
    qbittorrent
    prowlarr
    radarr
    sonarr
    bazarr
    flaresolverr
  )

  local service
  for service in "${vpn_shared_services[@]}"; do
    check_namespace_alignment "$service" "$vpn_id" || failures=$((failures + 1))
  done

  # Core service endpoints inside each container
  check_http_status "qbittorrent" "http://127.0.0.1:8080" "200" "ui" || failures=$((failures + 1))
  check_http_status "prowlarr" "http://127.0.0.1:9696" "401" "api-auth" || failures=$((failures + 1))
  check_http_status "radarr" "http://127.0.0.1:7878" "401" "api-auth" || failures=$((failures + 1))
  check_http_status "sonarr" "http://127.0.0.1:8989" "401" "api-auth" || failures=$((failures + 1))
  check_http_status "bazarr" "http://127.0.0.1:6767" "200" "ui" || failures=$((failures + 1))
  check_http_status "flaresolverr" "http://127.0.0.1:8191" "200" "ui" || failures=$((failures + 1))

  # Critical client routing checks for recent regressions
  check_http_status "radarr" "http://127.0.0.1:8080" "200" "qbittorrent-client" || failures=$((failures + 1))
  check_http_status "sonarr" "http://127.0.0.1:8080" "200" "qbittorrent-client" || failures=$((failures + 1))

  # Bazarr integration targets should resolve in the shared namespace.
  check_bazarr_config_target "radarr" "127.0.0.1" || failures=$((failures + 1))
  check_bazarr_config_target "sonarr" "127.0.0.1" || failures=$((failures + 1))

  if [[ "$failures" -gt 0 ]]; then
    log_line "[$(timestamp)] SUMMARY result=FAIL failures=${failures}"
    exit 1
  fi

  log_line "[$(timestamp)] SUMMARY result=PASS failures=0"
}

main "$@"
