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

# DerbyNet binds a PHP-FPM socket under its bind-mounted runtime directory.
# Remove any stale socket so a clean restart does not trip over the previous boot.
rm -f "${MEDIA_STACK_REPO_ROOT}/proxied-apps/data/derbynet/run/php-fpm.sock"

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
