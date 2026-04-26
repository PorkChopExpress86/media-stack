#!/usr/bin/env bash
# test-secret-scan.sh - catch committed secret-looking assignments in tracked files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
LOG_PATH="${SECRET_SCAN_LOG_PATH:-${PROJECT_ROOT}/secret-scan.log}"

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
  require_command git
  require_command python3

  : > "$LOG_PATH"

  local findings
  findings="$(
    cd "$PROJECT_ROOT"
    git grep -I -n -E '^[[:space:]]*[A-Z0-9_]*(PASSWORD|TOKEN|API_KEY|SECRET|CLAIM)[A-Z0-9_]*[[:space:]]*[:=][[:space:]]*[^[:space:]#]+' -- \
      '*.md' \
      '*.yml' \
      '*.yaml' \
      ':!*.env.example' \
      ':!security-audit.md' \
      ':!todo-security-audit.md' \
      2>/dev/null || true
  )"

  if [[ -z "$findings" ]]; then
    log_line "[$(timestamp)] SUMMARY result=PASS findings=0"
    return 0
  fi

  local filtered
  filtered="$(python3 - <<'PY' "$findings"
import re
import sys

safe_values = {
    "",
    "admin",
    "change-me",
    "false",
    "postgres",
    "scheduler",
    "super-secret-pass",
    "test-secret-key",
    "true",
}
safe_patterns = [
    re.compile(r"^\$\{[^}]+\}$"),
    re.compile(r"^\$[A-Z0-9_]+$"),
    re.compile(r"^<[^>]+>$"),
    re.compile(r"^<<[^>]+>>$"),
    re.compile(r"^!env_var\s+[A-Z0-9_]+$"),
]
assignment_re = re.compile(
    r"^\s*(?P<key>[A-Z0-9_]*(?:PASSWORD|TOKEN|API_KEY|SECRET|CLAIM)[A-Z0-9_]*)\s*[:=]\s*(?P<value>[^#\s]+)"
)

for line in sys.argv[1].splitlines():
    match = assignment_re.search(line)
    if not match:
        continue
    value = match.group("value").strip().strip("\"'")
    lowered = value.lower()
    if lowered in safe_values:
        continue
    if any(pattern.match(value) for pattern in safe_patterns):
        continue
    redacted = assignment_re.sub(lambda m: f"{m.group('key')}=[REDACTED]", line)
    print(redacted)
PY
)"

  if [[ -z "$filtered" ]]; then
    log_line "[$(timestamp)] SUMMARY result=PASS findings=0"
    return 0
  fi

  local count
  count="$(printf '%s\n' "$filtered" | sed '/^$/d' | wc -l | awk '{print $1}')"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    log_line "[$(timestamp)] FAIL check=secret-scan ${line}"
  done <<< "$filtered"
  log_line "[$(timestamp)] SUMMARY result=FAIL findings=${count}"
  return 1
}

main "$@"
