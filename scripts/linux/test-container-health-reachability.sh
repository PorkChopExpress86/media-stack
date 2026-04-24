#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_PATH="${CONTAINER_HEALTH_LOG_PATH:-${PROJECT_ROOT}/container-health-reachability.log}"

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

run_in_container() {
  local container_name="$1"
  local script="$2"
  shift 2

  local shell_name
  for shell_name in sh /bin/sh bash /bin/bash ash /bin/ash; do
    if docker exec "$container_name" "$shell_name" -lc "$script" "$shell_name" "$@" >/dev/null 2>&1; then
      return 0
    fi
  done

  return 127
}

check_container_state() {
  local stack="$1"
  local service="$2"
  local name="$3"
  local state="$4"
  local health_status="$5"

  if [[ "$state" != "running" ]]; then
    log_line "[$(timestamp)] FAIL stack=${stack} service=${service} container=${name} check=running state=${state}"
    return 1
  fi

  log_line "[$(timestamp)] PASS stack=${stack} service=${service} container=${name} check=running state=running"

  case "$health_status" in
    healthy)
      log_line "[$(timestamp)] PASS stack=${stack} service=${service} container=${name} check=health status=healthy"
      ;;
    "" | none)
      log_line "[$(timestamp)] PASS stack=${stack} service=${service} container=${name} check=health status=not-defined"
      ;;
    *)
      log_line "[$(timestamp)] FAIL stack=${stack} service=${service} container=${name} check=health status=${health_status}"
      return 1
      ;;
  esac
}

check_http_endpoint() {
  local stack="$1"
  local service="$2"
  local name="$3"
  local url="$4"

  if run_in_container "$name" '
url="$1"
if command -v curl >/dev/null 2>&1; then
  curl -fsS -o /dev/null --max-time 15 "$url"
elif command -v wget >/dev/null 2>&1; then
  wget -q -O /dev/null --timeout=15 "$url"
elif command -v python3 >/dev/null 2>&1; then
  python3 - "$url" <<'"'"'PY'"'"'
import sys
import urllib.request

with urllib.request.urlopen(sys.argv[1], timeout=15) as response:
    if response.status >= 400:
        raise SystemExit(1)
PY
elif command -v python >/dev/null 2>&1; then
  python - "$url" <<'"'"'PY'"'"'
import sys
import urllib.request

with urllib.request.urlopen(sys.argv[1], timeout=15) as response:
    if response.status >= 400:
        raise SystemExit(1)
PY
elif command -v node >/dev/null 2>&1; then
  node -e '"'"'
const url = process.argv[1];
const mod = url.startsWith("https:") ? require("https") : require("http");
const req = mod.get(url, { timeout: 15000 }, (res) => {
  res.resume();
  process.exit(res.statusCode < 400 ? 0 : 1);
});
req.on("timeout", () => req.destroy(new Error("timeout")));
req.on("error", () => process.exit(1));
'"'"' "$url"
else
  exit 127
fi
' "$url"; then
    log_line "[$(timestamp)] PASS stack=${stack} service=${service} container=${name} check=reachable url=${url}"
    return 0
  fi

  log_line "[$(timestamp)] FAIL stack=${stack} service=${service} container=${name} check=reachable url=${url}"
  return 1
}

endpoint_for_service() {
  case "$1" in
    actual_server) printf '%s\n' "http://127.0.0.1:5006" ;;
    audiobookshelf) printf '%s\n' "http://127.0.0.1:80" ;;
    bazarr) printf '%s\n' "http://127.0.0.1:6767" ;;
    derbynet) printf '%s\n' "http://127.0.0.1:80" ;;
    flaresolverr) printf '%s\n' "http://127.0.0.1:8191" ;;
    grafana) printf '%s\n' "http://127.0.0.1:3000/api/health" ;;
    homeassistant) printf '%s\n' "http://127.0.0.1:8123" ;;
    immich-machine-learning) printf '%s\n' "http://127.0.0.1:3003/ping" ;;
    immich-server) printf '%s\n' "http://127.0.0.1:2283/api/server/ping" ;;
    jellyfin) printf '%s\n' "http://127.0.0.1:8096/health" ;;
    jellyseerr) printf '%s\n' "http://127.0.0.1:5055" ;;
    nginx) printf '%s\n' "http://127.0.0.1:81" ;;
    pinchflat) printf '%s\n' "http://127.0.0.1:8945" ;;
    plex) printf '%s\n' "http://127.0.0.1:32400/identity" ;;
    prometheus) printf '%s\n' "http://127.0.0.1:9090/-/healthy" ;;
    node-exporter) printf '%s\n' "http://127.0.0.1:9100/metrics" ;;
    cadvisor) printf '%s\n' "http://127.0.0.1:8080/containers/" ;;
    prowlarr) printf '%s\n' "http://127.0.0.1:9696/ping" ;;
    qbittorrent) printf '%s\n' "http://127.0.0.1:8080" ;;
    radarr) printf '%s\n' "http://127.0.0.1:7878/ping" ;;
    scrutiny) printf '%s\n' "http://127.0.0.1:8080/api/health" ;;
    sonarr) printf '%s\n' "http://127.0.0.1:8989/ping" ;;
    vpn) printf '%s\n' "http://127.0.0.1:9999" ;;
  esac
}

collect_containers() {
  local stack="$1"

  compose_cmd_for_stack "$stack" ps --format json | python3 -c '
import json
import sys

stack = sys.argv[1]
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    item = json.loads(line)
    print("\t".join([
        stack,
        item.get("Service", ""),
        item.get("Name") or item.get("Names", ""),
        item.get("State", ""),
        item.get("Health", ""),
    ]))
' "$stack"
}

main() {
  require_command docker
  require_command python3

  : > "$LOG_PATH"

  local failures=0
  local checked=0
  log_line "[$(timestamp)] START container health/reachability regression run"

  local stack service name state health endpoint containers
  while IFS= read -r stack; do
    [[ -n "$stack" ]] || continue
    if ! containers="$(collect_containers "$stack")"; then
      log_line "[$(timestamp)] FAIL stack=${stack} check=collect-containers reason=compose-ps-failed"
      failures=$((failures + 1))
      continue
    fi
    if [[ -z "$containers" ]]; then
      log_line "[$(timestamp)] PASS stack=${stack} check=collect-containers status=no-running-containers"
      continue
    fi
    while IFS=$'\t' read -r stack service name state health; do
      [[ -n "$service" ]] || continue
      checked=$((checked + 1))

      if [[ -z "$name" ]]; then
        log_line "[$(timestamp)] FAIL stack=${stack} service=${service} check=running state=container-name-missing"
        failures=$((failures + 1))
        continue
      fi

      check_container_state "$stack" "$service" "$name" "$state" "$health" || failures=$((failures + 1))

      endpoint="$(endpoint_for_service "$service" || true)"
      if [[ -n "$endpoint" ]]; then
        check_http_endpoint "$stack" "$service" "$name" "$endpoint" || failures=$((failures + 1))
      else
        log_line "[$(timestamp)] PASS stack=${stack} service=${service} check=reachable status=not-applicable"
      fi
    done <<< "$containers"
  done < <(active_stack_names)

  if [[ "$checked" -eq 0 ]]; then
    log_line "[$(timestamp)] SUMMARY result=FAIL services=0 failures=1 reason=no-containers-checked"
    exit 1
  fi

  if [[ "$failures" -gt 0 ]]; then
    log_line "[$(timestamp)] SUMMARY result=FAIL services=${checked} failures=${failures}"
    exit 1
  fi

  log_line "[$(timestamp)] SUMMARY result=PASS services=${checked} failures=0"
}

main "$@"
