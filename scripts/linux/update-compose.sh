#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=media-stack-compose.sh
source "${SCRIPT_DIR}/media-stack-compose.sh"

if [[ "${MEDIA_STACK_MODE:-legacy}" == "modular" ]]; then
  while IFS= read -r stack; do
    [[ -n "$stack" ]] || continue
    echo "Updating stack: ${stack}"
    compose_cmd_for_stack "$stack" pull
    compose_cmd_for_stack "$stack" up -d
  done < <(active_stack_names)
else
  compose_cmd_for_stack "$LEGACY_PROJECT_NAME" down
  compose_cmd_for_stack "$LEGACY_PROJECT_NAME" pull
  compose_cmd_for_stack "$LEGACY_PROJECT_NAME" up -d
fi

docker image prune -af
