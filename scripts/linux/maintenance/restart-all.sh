#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=media-stack-compose.sh
source "${SCRIPT_DIR}/../helpers/media-stack-compose.sh"

echo "==> Bringing all stacks down"
while IFS= read -r stack; do
  [[ -n "$stack" ]] || continue
  echo "  down: ${stack}"
  compose_cmd_for_stack "$stack" down
done < <(active_stack_names)

echo "==> Pulling new images"
while IFS= read -r stack; do
  [[ -n "$stack" ]] || continue
  echo "  pull: ${stack}"
  compose_cmd_for_stack "$stack" pull
done < <(active_stack_names)

echo "==> Starting all stacks"
while IFS= read -r stack; do
  [[ -n "$stack" ]] || continue
  echo "  up: ${stack}"
  compose_cmd_for_stack "$stack" up -d --wait
done < <(active_stack_names)

docker image prune -af

echo "==> Done"
