#!/usr/bin/env bash

set -euo pipefail

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
LOG_PATH="${TEST_LOG_PATH:-${WORKSPACE_DIR}/test.log}"
NPM_DB_PATH="${NPM_DB_PATH:-/npm-data/database.sqlite}"
BASELINE_PATH="${BASELINE_PATH:-${WORKSPACE_DIR}/config/nginx-proxy-regression-baseline.json}"
TEST_TIMEOUT_SECONDS="${TEST_TIMEOUT_SECONDS:-10}"
TEST_DOMAIN="${TEST_DOMAIN:-}"

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log_line() {
  local line="$1"
  mkdir -p "$(dirname "$LOG_PATH")"
  printf '%s\n' "$line" | tee -a "$LOG_PATH"
}

require_file() {
  local file_path="$1"
  local label="$2"
  if [[ ! -f "$file_path" ]]; then
    log_line "[$(timestamp)] ERROR missing ${label}: ${file_path}"
    exit 2
  fi
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    log_line "[$(timestamp)] ERROR missing required command: ${command_name}"
    exit 2
  fi
}

detect_nginx_ip() {
  getent hosts nginx | awk 'NR==1 {print $1}'
}

collect_targets() {
  python3 - <<'PY'
import json
import os
import sqlite3
import sys

db_path = os.environ["NPM_DB_PATH"]
requested_domain = os.environ.get("TEST_DOMAIN", "").strip().lower()

conn = sqlite3.connect(db_path)
cur = conn.cursor()
cur.execute(
    """
    SELECT id, domain_names, ssl_forced, certificate_id, enabled
    FROM proxy_host
    WHERE is_deleted = 0 AND enabled = 1
    ORDER BY id
    """
)

rows = []
for row_id, domain_names_raw, ssl_forced, certificate_id, enabled in cur.fetchall():
    try:
        domain_names = json.loads(domain_names_raw or "[]")
    except json.JSONDecodeError:
        continue
    scheme = "https" if int(ssl_forced or 0) == 1 or int(certificate_id or 0) > 0 else "http"
    for domain in domain_names:
        domain = str(domain).strip()
        if not domain:
            continue
        if requested_domain and domain.lower() != requested_domain:
            continue
        rows.append({"id": row_id, "domain": domain, "scheme": scheme})

if requested_domain and not rows:
    print(json.dumps({"error": f"Requested domain not found among enabled proxy hosts: {requested_domain}"}))
    sys.exit(3)

print(json.dumps(rows))
PY
}

run_probe() {
  local domain="$1"
  local scheme="$2"
  local nginx_ip="$3"
  local port curl_output curl_exit http_code time_total remote_ip errormsg reason status result location header_file

  if [[ "$scheme" == "https" ]]; then
    port=443
  else
    port=80
  fi

  header_file="$(mktemp)"
  set +e
  curl_output=$(curl \
    --silent \
    --show-error \
    --output /dev/null \
    --dump-header "$header_file" \
    --write-out '%{http_code}|%{time_total}|%{remote_ip}|%{errormsg}' \
    --resolve "${domain}:${port}:${nginx_ip}" \
    --connect-timeout 5 \
    --max-time "$TEST_TIMEOUT_SECONDS" \
    "${scheme}://${domain}/" 2>&1)
  curl_exit=$?
  set -e

  location="$(python3 - <<'PY' "$header_file"
import sys

header_file = sys.argv[1]
location = ""
with open(header_file, encoding="utf-8", errors="replace") as handle:
    for line in handle:
        if line.lower().startswith("location:"):
            location = line.split(":", 1)[1].strip()
            break
print(location)
PY
)"
  rm -f "$header_file"

  IFS='|' read -r http_code time_total remote_ip errormsg <<< "$curl_output"
  http_code="${http_code:-000}"
  time_total="${time_total:-0}"
  remote_ip="${remote_ip:-n/a}"
  errormsg="${errormsg:-}"
  location="${location:-}"

  result="FAIL"
  status="${http_code}"
  reason=""

  if [[ $curl_exit -eq 0 ]]; then
    if [[ "$http_code" == "200" || "$http_code" == "401" ]]; then
      result="PASS"
      reason="allowed-status"
    elif python3 - <<'PY' "$BASELINE_PATH" "$domain" "$http_code" "$location"
import json
import os
import sys

baseline_path, domain, status, location = sys.argv[1:5]
if not os.path.exists(baseline_path):
    raise SystemExit(1)

with open(baseline_path, encoding="utf-8") as handle:
    baseline = json.load(handle)

expected = baseline.get("redirects", {}).get(domain)
if not expected:
    raise SystemExit(1)

expected_status = str(expected.get("status", ""))
expected_location = str(expected.get("location", ""))

raise SystemExit(0 if status == expected_status and location == expected_location else 1)
PY
    then
      result="PASS"
      reason="baseline-redirect"
    else
      reason="unexpected-status"
    fi
  else
    case "$curl_exit" in
      6) reason="dns-failure" ;;
      7) reason="connection-failure" ;;
      28) reason="timeout" ;;
      35|51|58|60) reason="tls-failure" ;;
      *) reason="curl-exit-${curl_exit}" ;;
    esac
  fi

  if ! python3 - <<'PY' "$time_total" "$TEST_TIMEOUT_SECONDS"
import sys
time_total = float(sys.argv[1])
threshold = float(sys.argv[2])
raise SystemExit(0 if time_total <= threshold else 1)
PY
  then
    result="FAIL"
    reason="slow-response"
  fi

  printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$result" "$domain" "$scheme" "$status" "$time_total" "$reason" "$remote_ip" "$location"
}

main() {
  require_command curl
  require_command python3
  require_command getent
  require_file "$NPM_DB_PATH" "Nginx Proxy Manager database"

  local nginx_ip raw_targets json_error total_count passed_count failed_count
  nginx_ip="$(detect_nginx_ip)"
  if [[ -z "$nginx_ip" ]]; then
    log_line "[$(timestamp)] ERROR unable to resolve nginx container IP"
    exit 2
  fi

  raw_targets="$(collect_targets)"
  if python3 - <<'PY' "$raw_targets"
import json, sys
payload = json.loads(sys.argv[1])
raise SystemExit(0 if isinstance(payload, dict) and 'error' in payload else 1)
PY
  then
    json_error="$(python3 - <<'PY' "$raw_targets"
import json, sys
print(json.loads(sys.argv[1])['error'])
PY
)"
    log_line "[$(timestamp)] ERROR ${json_error}"
    exit 3
  fi

  total_count="$(python3 - <<'PY' "$raw_targets"
import json, sys
print(len(json.loads(sys.argv[1])))
PY
)"

  if [[ "$total_count" -eq 0 ]]; then
    log_line "[$(timestamp)] ERROR no enabled proxy hosts found to test"
    exit 3
  fi

  log_line "[$(timestamp)] START nginx proxy domain test run: total=${total_count} timeout=${TEST_TIMEOUT_SECONDS}s filter=${TEST_DOMAIN:-all}"

  passed_count=0
  failed_count=0

  while IFS=$'\t' read -r domain scheme; do
    [[ -n "$domain" ]] || continue
    local probe_output result domain_name probe_scheme status time_total reason remote_ip location
    probe_output="$(run_probe "$domain" "$scheme" "$nginx_ip")"
    IFS='|' read -r result domain_name probe_scheme status time_total reason remote_ip location <<< "$probe_output"

    if [[ "$result" == "PASS" ]]; then
      passed_count=$((passed_count + 1))
    else
      failed_count=$((failed_count + 1))
    fi

    log_line "[$(timestamp)] ${result} domain=${domain_name} scheme=${probe_scheme} status=${status} time=${time_total}s reason=${reason} nginx_ip=${remote_ip} location=${location:--}"
  done < <(python3 - <<'PY' "$raw_targets"
import json, sys
for item in json.loads(sys.argv[1]):
    print(f"{item['domain']}\t{item['scheme']}")
PY
)

  log_line "[$(timestamp)] SUMMARY total=${total_count} passed=${passed_count} failed=${failed_count}"

  if [[ "$failed_count" -gt 0 ]]; then
    exit 1
  fi
}

main "$@"