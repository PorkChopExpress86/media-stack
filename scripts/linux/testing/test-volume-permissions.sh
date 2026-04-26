#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
LOG_PATH="${VOLUME_PERMISSION_LOG_PATH:-${PROJECT_ROOT}/volume-permissions.log}"

# shellcheck source=media-stack-compose.sh
source "${SCRIPT_DIR}/../helpers/media-stack-compose.sh"

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log_line() {
  local line="$1"
  mkdir -p "$(dirname "$LOG_PATH")"
  printf '%s\n' "$line" | tee -a "$LOG_PATH"
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    log_line "[$(timestamp)] ERROR missing required command: ${command_name}"
    exit 2
  fi
}

collect_mounts() {
  local container_ids
  container_ids="$(compose_ps_ids)"

  if [[ -z "$container_ids" ]]; then
    log_line "[$(timestamp)] ERROR no compose containers found to inspect"
    exit 3
  fi

  docker inspect $container_ids | python3 -c '
import json
import sys

containers = json.load(sys.stdin)
for container in containers:
    name = container.get("Name", "").lstrip("/")
    labels = container.get("Config", {}).get("Labels", {}) or {}
    service = labels.get("com.docker.compose.service", name)
    state = container.get("State", {})
    if not state.get("Running", False):
        continue
    for mount in container.get("Mounts", []):
        if mount.get("Type") not in {"bind", "volume"}:
            continue
        destination = mount.get("Destination", "")
        source = mount.get("Source", "")
        mode = "rw" if mount.get("RW", False) else "ro"
        mount_name = mount.get("Name", "")
        print("\t".join([
            name,
            service,
            mount.get("Type", ""),
            mode,
            destination,
            source,
            mount_name,
        ]))
'
}

run_with_container_shell() {
  local container_name="$1"
  local script="$2"
  shift 2

  local shell_name output
  for shell_name in sh /bin/sh bash /bin/bash ash /bin/ash; do
    if output=$(docker exec "$container_name" "$shell_name" -lc "$script" "$shell_name" "$@" 2>/dev/null); then
      printf '%s\n' "$output"
      return 0
    fi
  done

  return 127
}

get_container_identity() {
  local container_name="$1"
  local output inspect_user

  if output=$(run_with_container_shell "$container_name" '
uid=$(id -u 2>/dev/null || echo unknown)
gid=$(id -g 2>/dev/null || echo unknown)
user=$(id -un 2>/dev/null || echo unknown)
printf "%s|%s|%s\n" "$uid" "$gid" "$user"
'); then
    printf '%s\n' "$output"
    return 0
  fi

  inspect_user="$(docker inspect -f '{{.Config.User}}' "$container_name" 2>/dev/null || true)"
  if [[ -z "$inspect_user" ]]; then
    printf '0|0|root(inspect)\n'
  elif [[ "$inspect_user" =~ ^[0-9]+:[0-9]+$ ]]; then
    printf '%s|%s|%s\n' "${inspect_user%%:*}" "${inspect_user##*:}" "$inspect_user"
  elif [[ "$inspect_user" =~ ^[0-9]+$ ]]; then
    printf '%s|%s|%s\n' "$inspect_user" "$inspect_user" "$inspect_user"
  else
    printf 'unknown|unknown|%s\n' "$inspect_user"
  fi
}

run_helper_mount_check() {
  local container_name="$1"
  local destination="$2"
  local mode="$3"
  local uid="$4"
  local gid="$5"

  docker run --rm --volumes-from "$container_name" --user "${uid}:${gid}" --entrypoint sh media-stack-tests:latest -lc '
dest="$1"
mode="$2"

if [ -d "$dest" ]; then
  if [ ! -r "$dest" ] || [ ! -x "$dest" ]; then
    echo "FAIL|directory-unreadable(helper)"
    exit 0
  fi

  if [ "$mode" = "rw" ] && [ ! -w "$dest" ]; then
    echo "FAIL|directory-not-writable(helper)"
    exit 0
  fi

  echo "PASS|directory-access-ok(helper)"
  exit 0
fi

if [ -S "$dest" ]; then
  echo "PASS|socket-present(helper)"
  exit 0
fi

if [ -f "$dest" ]; then
  if [ ! -r "$dest" ]; then
    echo "FAIL|file-unreadable(helper)"
    exit 0
  fi

  if [ "$mode" = "rw" ] && [ ! -w "$dest" ]; then
    echo "FAIL|file-not-writable(helper)"
    exit 0
  fi

  echo "PASS|file-access-ok(helper)"
  exit 0
fi

if [ -e "$dest" ]; then
  if [ "$mode" = "rw" ] && [ ! -w "$dest" ]; then
    echo "FAIL|path-not-writable(helper)"
    exit 0
  fi
  if [ ! -r "$dest" ]; then
    echo "FAIL|path-unreadable(helper)"
    exit 0
  fi
  echo "PASS|path-access-ok(helper)"
  exit 0
fi

echo "FAIL|path-missing(helper)"
' sh "$destination" "$mode" 2>/dev/null
}

check_mount_access() {
  local container_name="$1"
  local destination="$2"
  local mode="$3"
  local uid="$4"
  local gid="$5"
  local output

  if output=$(run_with_container_shell "$container_name" '
dest="$1"
mode="$2"

if [ -d "$dest" ]; then
  if [ ! -r "$dest" ] || [ ! -x "$dest" ]; then
    echo "FAIL|directory-unreadable"
    exit 0
  fi

  if [ "$mode" = "rw" ] && [ ! -w "$dest" ]; then
    echo "FAIL|directory-not-writable"
    exit 0
  fi

  echo "PASS|directory-access-ok"
  exit 0
fi

if [ -S "$dest" ]; then
  echo "PASS|socket-present"
  exit 0
fi

if [ -f "$dest" ]; then
  if [ ! -r "$dest" ]; then
    echo "FAIL|file-unreadable"
    exit 0
  fi

  if [ "$mode" = "rw" ] && [ ! -w "$dest" ]; then
    echo "FAIL|file-not-writable"
    exit 0
  fi

  echo "PASS|file-access-ok"
  exit 0
fi

if [ -e "$dest" ]; then
  if [ "$mode" = "rw" ] && [ ! -w "$dest" ]; then
    echo "FAIL|path-not-writable"
    exit 0
  fi
  if [ ! -r "$dest" ]; then
    echo "FAIL|path-unreadable"
    exit 0
  fi
  echo "PASS|path-access-ok"
  exit 0
fi

echo "FAIL|path-missing"
' "$destination" "$mode"); then
    printf '%s\n' "$output"
    return 0
  fi

  if [[ "$uid" =~ ^[0-9]+$ && "$gid" =~ ^[0-9]+$ ]]; then
    if output=$(run_helper_mount_check "$container_name" "$destination" "$mode" "$uid" "$gid"); then
      printf '%s\n' "$output"
      return 0
    fi
  fi

  printf 'SKIP|exec-unavailable\n'
}

main() {
  require_command docker
  require_command python3

  local total_count pass_count fail_count skip_count inspected_mounts
  total_count=0
  pass_count=0
  fail_count=0
  skip_count=0

  : > "$LOG_PATH"

  inspected_mounts="$(collect_mounts)"
  if [[ -z "$inspected_mounts" ]]; then
    log_line "[$(timestamp)] ERROR no running compose-managed bind or volume mounts found"
    exit 3
  fi

  local mount_total
  mount_total="$(printf '%s\n' "$inspected_mounts" | sed '/^$/d' | wc -l | awk '{print $1}')"
  log_line "[$(timestamp)] START volume permission test run: mounts=${mount_total}"

  declare -A identity_cache=()

  while IFS=$'\t' read -r container_name service mount_type mode destination source mount_name; do
    [[ -n "$container_name" ]] || continue
    total_count=$((total_count + 1))

    if [[ -z "${identity_cache[$container_name]:-}" ]]; then
      identity_cache[$container_name]="$(get_container_identity "$container_name")"
    fi

    local uid gid username identity result details source_label
    identity="${identity_cache[$container_name]}"
    IFS='|' read -r uid gid username <<< "$identity"

    result="$(check_mount_access "$container_name" "$destination" "$mode" "$uid" "$gid")"
    IFS='|' read -r result details <<< "$result"

    if [[ "$mount_type" == "volume" && -n "$mount_name" ]]; then
      source_label="$mount_name"
    else
      source_label="$source"
    fi

    case "$result" in
      PASS) pass_count=$((pass_count + 1)) ;;
      SKIP) skip_count=$((skip_count + 1)) ;;
      *) fail_count=$((fail_count + 1)) ;;
    esac

    log_line "[$(timestamp)] ${result} service=${service} container=${container_name} uid=${uid} gid=${gid} user=${username} type=${mount_type} mode=${mode} destination=${destination} source=${source_label} reason=${details}"
  done <<< "$inspected_mounts"

  log_line "[$(timestamp)] SUMMARY total=${total_count} passed=${pass_count} failed=${fail_count} skipped=${skip_count}"

  if [[ "$fail_count" -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
