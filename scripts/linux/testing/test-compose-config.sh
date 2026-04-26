#!/usr/bin/env bash
# test-compose-config.sh — validate all compose.yml files parse correctly.
# Tier 1: no containers required. Uses --no-interpolate to skip env var substitution.
#
# Exit codes:
#   0 — all stacks pass
#   1 — one or more stacks fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
LOG_PATH="${COMPOSE_CONFIG_LOG_PATH:-${PROJECT_ROOT}/compose-config.log}"

# shellcheck source=media-stack-compose.sh
source "${SCRIPT_DIR}/../helpers/media-stack-compose.sh"

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

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

  local failures=0 stacks_checked=0
  local stack compose_file err

  while IFS= read -r stack; do
    compose_file="$(compose_file_for_stack "$stack")" || {
      log_line "[$(timestamp)] WARN stack=${stack} check=compose-config reason=unknown-stack"
      continue
    }

    stacks_checked=$((stacks_checked + 1))

    if err=$(docker compose -f "$compose_file" config --no-interpolate --quiet 2>&1); then
      log_line "[$(timestamp)] PASS stack=${stack} check=compose-config"
    else
      log_line "[$(timestamp)] FAIL stack=${stack} check=compose-config reason=${err}"
      failures=$((failures + 1))
    fi

  done < <(active_stack_names)

  log_line "[$(timestamp)] SUMMARY stacks=${stacks_checked} failures=${failures}"
  [[ "$failures" -eq 0 ]]
}

main "$@"
