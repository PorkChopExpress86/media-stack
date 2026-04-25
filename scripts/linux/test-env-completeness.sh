#!/usr/bin/env bash
# test-env-completeness.sh — verify every ${VAR} in compose.yml is defined in .env.example.
# Tier 1: no containers required.
#
# Exit codes:
#   0 — all stacks complete
#   1 — one or more vars missing from .env.example

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_PATH="${ENV_COMPLETENESS_LOG_PATH:-${PROJECT_ROOT}/env-completeness.log}"

# shellcheck source=media-stack-compose.sh
source "${SCRIPT_DIR}/media-stack-compose.sh"

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
  require_command grep
  : > "$LOG_PATH"

  local failures=0 stacks_checked=0
  local stack compose_file env_example defined referenced missing var

  while IFS= read -r stack; do
    compose_file="$(compose_file_for_stack "$stack")" || {
      log_line "[$(timestamp)] WARN stack=${stack} check=env-completeness reason=unknown-stack"
      continue
    }

    env_example="${PROJECT_ROOT}/${stack}/.env.example"
    if [[ ! -f "$env_example" ]]; then
      log_line "[$(timestamp)] WARN stack=${stack} check=env-completeness reason=no-.env.example"
      continue
    fi

    stacks_checked=$((stacks_checked + 1))

    # Vars defined in .env.example: lines matching KEY= at start (uppercase/digits/underscore)
    defined=$(grep -oP '^[A-Z_][A-Z0-9_]*(?==)' "$env_example" 2>/dev/null | sort -u || true)

    # Vars referenced in compose.yml via ${VAR} but NOT $${VAR} (double-dollar = shell escape)
    # Negative lookbehind (?<!\$) skips $${VAR} used in healthcheck CMD-SHELL strings
    referenced=$(grep -oP '(?<!\$)\$\{[A-Z_][A-Z0-9_]*(?::-[^}]*)?\}' "$compose_file" 2>/dev/null \
                   | grep -oP '(?<=\$\{)[A-Z_][A-Z0-9_]*' \
                   | sort -u || true)

    if [[ -z "$referenced" ]]; then
      log_line "[$(timestamp)] PASS stack=${stack} check=env-completeness reason=no-vars-referenced"
      continue
    fi

    # Vars in compose but not in .env.example
    missing=$(comm -23 <(echo "$referenced") <(echo "$defined") 2>/dev/null || true)

    if [[ -z "$missing" ]]; then
      log_line "[$(timestamp)] PASS stack=${stack} check=env-completeness"
    else
      while IFS= read -r var; do
        [[ -n "$var" ]] || continue
        log_line "[$(timestamp)] FAIL stack=${stack} check=env-completeness var=${var} reason=missing-from-.env.example"
        failures=$((failures + 1))
      done <<< "$missing"
    fi

  done < <(active_stack_names)

  log_line "[$(timestamp)] SUMMARY stacks=${stacks_checked} failures=${failures}"
  [[ "$failures" -eq 0 ]]
}

main "$@"
