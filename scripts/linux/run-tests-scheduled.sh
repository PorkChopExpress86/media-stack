#!/usr/bin/env bash
# run-tests-scheduled.sh — entrypoint for scheduled/cron test runs.
# Delegates to run-regression-tests.sh for the full suite.
#
# Note: This script is also copied into Dockerfile.tests. Inside that container,
# it is called from the test service context (not from the host), which is why
# the container image uses a separate docker-compose run entrypoint. If you
# update the container-internal test path, update Dockerfile.tests as well.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec bash "${SCRIPT_DIR}/run-regression-tests.sh" "$@"
