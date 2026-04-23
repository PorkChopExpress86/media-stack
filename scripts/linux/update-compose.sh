#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=media-stack-compose.sh
source "${SCRIPT_DIR}/media-stack-compose.sh"

while IFS= read -r stack; do
  [[ -n "$stack" ]] || continue
  echo "Updating stack: ${stack}"
  compose_cmd_for_stack "$stack" pull
  compose_cmd_for_stack "$stack" up -d
done < <(active_stack_names)

docker image prune -af
