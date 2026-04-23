#!/usr/bin/env bash
# test-socket-access.sh — Functional Unix socket validation for hardened containers.
#
# Works against any container including minimal/distroless images that have no shell.
# All checks run host-side or via a throwaway alpine helper container.
#
# Checks:
#   1. Socket presence  — host stat confirms the source socket is a Unix socket.
#   2. Identity         — user/group/group_add parsed from docker inspect.
#   3. Docker API probe — /_ping via unix socket transport using alpine helper container.
#   4. Log probe        — scans recent container logs for Docker API error patterns.
#
# Usage:
#   bash test-socket-access.sh [--container <name>] [--socket <path>]
#
# Env overrides:
#   CONTAINER        — compose service name or container name (default: watchtower)
#   SOCKET_PATH      — path to the Unix socket on the HOST (default: /var/run/docker.sock)
#   LOG_PATH         — path to write results (default: socket-access.log in project root)
#   HELPER_IMAGE     — image for the API ping helper container (default: alpine:latest)
#
# Exit codes:
#   0  all checks passed
#   1  one or more checks failed
#   2  missing required tooling or container not running

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../../" && pwd)"
LOG_PATH="${LOG_PATH:-${PROJECT_ROOT}/socket-access.log}"

CONTAINER="${CONTAINER:-watchtower}"
SOCKET_PATH="${SOCKET_PATH:-/var/run/docker.sock}"
HELPER_IMAGE="${HELPER_IMAGE:-alpine:latest}"

# ─── parse arguments ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --container) CONTAINER="$2"; shift 2 ;;
    --socket)    SOCKET_PATH="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

# ─── helpers ─────────────────────────────────────────────────────────────────
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

log_line() {
  local line="$1"
  mkdir -p "$(dirname "$LOG_PATH")"
  printf '%s\n' "$line" | tee -a "$LOG_PATH"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_line "[$(timestamp)] ERROR missing required command: $1"
    exit 2
  fi
}

# ─── checks ──────────────────────────────────────────────────────────────────
fail_count=0

# 1) Confirm the source socket path on the HOST is actually a Unix socket.
check_socket_present() {
  if [[ -S "$SOCKET_PATH" ]]; then
    log_line "[$(timestamp)] PASS container=${CONTAINER} check=socket-present path=${SOCKET_PATH} method=host-stat"
  elif [[ -e "$SOCKET_PATH" ]]; then
    log_line "[$(timestamp)] FAIL container=${CONTAINER} check=socket-present path=${SOCKET_PATH} reason=exists-but-not-a-socket method=host-stat"
    fail_count=$((fail_count + 1))
  else
    log_line "[$(timestamp)] FAIL container=${CONTAINER} check=socket-present path=${SOCKET_PATH} reason=path-missing method=host-stat"
    fail_count=$((fail_count + 1))
  fi
}

# 2) Report configured user/group from docker inspect (host-side, no shell needed).
check_identity() {
  local cfg_user cfg_group_add
  cfg_user="$(docker inspect "$CONTAINER" --format '{{.Config.User}}' 2>/dev/null || true)"
  cfg_group_add="$(docker inspect "$CONTAINER" --format '{{join .HostConfig.GroupAdd ","}}' 2>/dev/null || true)"
  [[ -z "$cfg_user" ]] && cfg_user="(default/root)"
  [[ -z "$cfg_group_add" ]] && cfg_group_add="(none)"
  log_line "[$(timestamp)] INFO container=${CONTAINER} check=identity configured_user=${cfg_user} group_add=${cfg_group_add}"
}

# 3) Probe Docker API /_ping via a throwaway alpine container with socket bind-mounted.
#    This mirrors what the target service does, without needing a shell in it.
check_docker_api() {
  local http_body exit_code

  set +e
  http_body="$(docker run --rm \
    -v "${SOCKET_PATH}:${SOCKET_PATH}" \
    --entrypoint sh \
    "$HELPER_IMAGE" \
    -c "apk add --quiet --no-cache curl >/dev/null 2>&1 && curl -sf --unix-socket '${SOCKET_PATH}' http://localhost/_ping 2>&1")"
  exit_code=$?
  set -e

  if [[ $exit_code -eq 0 && "$http_body" == "OK" ]]; then
    log_line "[$(timestamp)] PASS container=${CONTAINER} check=docker-api-ping response=OK method=helper-container"
  elif echo "$http_body" | grep -qi "permission denied\|cannot connect\|connection refused"; then
    log_line "[$(timestamp)] FAIL container=${CONTAINER} check=docker-api-ping reason=permission-denied method=helper-container body=${http_body}"
    fail_count=$((fail_count + 1))
  else
    log_line "[$(timestamp)] FAIL container=${CONTAINER} check=docker-api-ping reason=unexpected-response exit=${exit_code} method=helper-container body=${http_body}"
    fail_count=$((fail_count + 1))
  fi
}

# 4) Scan recent container logs for Docker API error patterns.
check_logs_for_errors() {
  local error_lines
  error_lines="$(docker logs --tail 50 "$CONTAINER" 2>&1 \
    | grep -iE "permission denied|cannot connect to docker|dial unix.*socket|error talking to docker" \
    | head -5 || true)"

  if [[ -z "$error_lines" ]]; then
    log_line "[$(timestamp)] PASS container=${CONTAINER} check=log-scan reason=no-docker-api-errors-in-recent-50-lines"
  else
    log_line "[$(timestamp)] WARN container=${CONTAINER} check=log-scan reason=docker-api-errors-found"
    while IFS= read -r line; do
      log_line "[$(timestamp)] WARN container=${CONTAINER} log=${line}"
    done <<< "$error_lines"
    fail_count=$((fail_count + 1))
  fi
}

# ─── main ────────────────────────────────────────────────────────────────────
main() {
  require_command docker

  : > "$LOG_PATH"

  log_line "[$(timestamp)] START socket-access test container=${CONTAINER} socket=${SOCKET_PATH}"

  if ! docker inspect "$CONTAINER" --format '{{.State.Running}}' 2>/dev/null | grep -q "true"; then
    log_line "[$(timestamp)] ERROR container=${CONTAINER} is not running"
    exit 2
  fi

  check_socket_present
  check_identity
  check_docker_api
  check_logs_for_errors

  if [[ $fail_count -eq 0 ]]; then
    log_line "[$(timestamp)] SUMMARY result=PASS failures=0"
    exit 0
  else
    log_line "[$(timestamp)] SUMMARY result=FAIL failures=${fail_count}"
    exit 1
  fi
}

main "$@"
