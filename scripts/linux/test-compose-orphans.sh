#!/usr/bin/env bash
# test-compose-orphans.sh - fail when MediaServer compose projects have services
# running that are no longer declared in the active modular compose files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_PATH="${COMPOSE_ORPHANS_LOG_PATH:-${PROJECT_ROOT}/compose-orphans.log}"

# shellcheck source=media-stack-compose.sh
source "${SCRIPT_DIR}/media-stack-compose.sh"

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log_line() {
  mkdir -p "$(dirname "$LOG_PATH")"
  printf '%s\n' "$1" | tee -a "$LOG_PATH"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_line "[$(timestamp)] ERROR missing required command: $1"
    exit 2
  fi
}

main() {
  require_command docker

  : > "$LOG_PATH"

  local failures=0 projects_checked=0 containers_checked=0
  local stack expected_services actual_rows service name state oneoff

  while IFS= read -r stack; do
    [[ -n "$stack" ]] || continue
    projects_checked=$((projects_checked + 1))

    expected_services="$(compose_cmd_for_stack "$stack" config --services | sort -u)"
    actual_rows="$(docker ps -a \
      --filter "label=com.docker.compose.project=${stack}" \
      --format '{{.Label "com.docker.compose.service"}}	{{.Names}}	{{.State}}	{{.Label "com.docker.compose.oneoff"}}' \
      | sort -u)"

    if [[ -z "$actual_rows" ]]; then
      log_line "[$(timestamp)] PASS project=${stack} check=compose-orphans status=no-containers"
      continue
    fi

    while IFS=$'\t' read -r service name state oneoff; do
      [[ -n "$service" ]] || continue
      [[ "$oneoff" == "True" ]] && continue
      containers_checked=$((containers_checked + 1))
      if grep -Fxq "$service" <<< "$expected_services"; then
        log_line "[$(timestamp)] PASS project=${stack} service=${service} container=${name} check=declared state=${state}"
      else
        log_line "[$(timestamp)] FAIL project=${stack} service=${service} container=${name} check=orphan state=${state}"
        failures=$((failures + 1))
      fi
    done <<< "$actual_rows"
  done < <(active_stack_names)

  if [[ "$failures" -gt 0 ]]; then
    log_line "[$(timestamp)] SUMMARY result=FAIL projects=${projects_checked} containers=${containers_checked} failures=${failures}"
    return 1
  fi

  log_line "[$(timestamp)] SUMMARY result=PASS projects=${projects_checked} containers=${containers_checked} failures=0"
}

main "$@"
