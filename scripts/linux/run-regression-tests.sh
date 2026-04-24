#!/usr/bin/env bash
# run-regression-tests.sh — run all regression tests and report a combined result.
#
# Tests run (in order):
#   1. Nginx proxy domain regression  (docker compose run tests)
#   2. Volume permission regression    (test-volume-permissions.sh)
#   3. VPN namespace/connectivity      (test-vpn-namespace-connectivity.sh)
#   4. Container health/reachability   (test-container-health-reachability.sh)
#
# Exit codes:
#   0 — all suites passed
#   1 — one or more suites failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "$PROJECT_ROOT"

# shellcheck source=media-stack-compose.sh
source "${SCRIPT_DIR}/media-stack-compose.sh"

overall_pass=true

# ─── helpers ─────────────────────────────────────────────────────────────────

banner() { echo; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; echo "  $*"; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }

run_suite() {
  local name="$1"
  shift
  banner "$name"
  if "$@"; then
    echo "[SUITE PASS] $name"
  else
    echo "[SUITE FAIL] $name"
    overall_pass=false
  fi
}

# ─── suite 1: nginx proxy domain regression ──────────────────────────────────

run_suite "Nginx proxy domain regression" \
  compose_run_proxy_tests

# ─── suite 2: volume permission regression ───────────────────────────────────

run_suite "Volume permission regression" \
  bash "${SCRIPT_DIR}/test-volume-permissions.sh"

# ─── suite 3: vpn namespace/connectivity regression ──────────────────────────

run_suite "VPN namespace/connectivity regression" \
  bash "${SCRIPT_DIR}/test-vpn-namespace-connectivity.sh"

# ─── suite 4: container health/reachability regression ───────────────────────

run_suite "Container health/reachability regression" \
  bash "${SCRIPT_DIR}/test-container-health-reachability.sh"

# ─── overall result ──────────────────────────────────────────────────────────

echo
banner "Combined regression result"
if $overall_pass; then
  echo "  RESULT: ALL SUITES PASSED"
  exit 0
else
  echo "  RESULT: ONE OR MORE SUITES FAILED — check test.log, volume-permissions.log, vpn-namespace-connectivity.log, and container-health-reachability.log"
  exit 1
fi
