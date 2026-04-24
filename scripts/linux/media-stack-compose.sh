#!/usr/bin/env bash

# Shared Compose helpers for the modular stack files.
# Each stack owns its own compose file, project name, and env file.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

MODULAR_STACK_NAMES=(
  jellyfin
  arr-stack
  immich
  lan-apps
  proxied-apps
  monitoring
  nginx-proxy
)

normalize_stack_name() {
  case "$1" in
    proxy) printf '%s\n' "nginx-proxy" ;;
    lan) printf '%s\n' "lan-apps" ;;
    proxied) printf '%s\n' "proxied-apps" ;;
    download-vpn) printf '%s\n' "arr-stack" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

compose_file_for_stack() {
  case "$(normalize_stack_name "$1")" in
    nginx-proxy) printf '%s\n' "${PROJECT_ROOT}/nginx-proxy/compose.yml" ;;
    jellyfin) printf '%s\n' "${PROJECT_ROOT}/jellyfin/compose.yml" ;;
    arr-stack) printf '%s\n' "${PROJECT_ROOT}/arr-stack/compose.yml" ;;
    immich) printf '%s\n' "${PROJECT_ROOT}/immich/compose.yml" ;;
    lan-apps) printf '%s\n' "${PROJECT_ROOT}/lan-apps/compose.yml" ;;
    proxied-apps) printf '%s\n' "${PROJECT_ROOT}/proxied-apps/compose.yml" ;;
    monitoring) printf '%s\n' "${PROJECT_ROOT}/monitoring/compose.yml" ;;
    *) return 1 ;;
  esac
}

active_stack_names() {
  if [[ -n "${MEDIA_STACK_STACKS:-}" ]]; then
    local stack
    while IFS= read -r stack; do
      [[ -n "$stack" ]] || continue
      normalize_stack_name "$stack"
    done < <(tr ',' '\n' <<< "$MEDIA_STACK_STACKS")
  else
    printf '%s\n' "${MODULAR_STACK_NAMES[@]}"
  fi
}

compose_project_for_stack() {
  printf '%s\n' "$1"
}

compose_env_file_for_stack() {
  local stack="$1"

  local stack_env="${PROJECT_ROOT}/${stack}/.env"
  if [[ -f "$stack_env" ]]; then
    printf '%s\n' "$stack_env"
    return 0
  fi

  printf 'Missing compose env file: %s\n' "$stack_env" >&2
  return 1
}

compose_file_args_for_stack() {
  local stack="$1"

  local compose_file
  compose_file="$(compose_file_for_stack "$stack")" || return 1
  printf '%s\n%s\n' "-f" "$compose_file"
}

compose_cmd_for_stack() {
  local stack="$1"
  shift

  local project compose_file env_file
  stack="$(normalize_stack_name "$stack")"
  project="$(compose_project_for_stack "$stack")"
  compose_file="$(compose_file_for_stack "$stack")" || return 1
  env_file="$(compose_env_file_for_stack "$stack")"

  (cd "$PROJECT_ROOT" && docker compose --project-directory "$PROJECT_ROOT" --env-file "$env_file" -p "$project" -f "$compose_file" "$@")
}

compose_ps_ids() {
  local stack
  while IFS= read -r stack; do
    [[ -n "$stack" ]] || continue
    compose_cmd_for_stack "$stack" ps -q 2>/dev/null || true
  done < <(active_stack_names)
}

compose_service_id() {
  local service="$1"

  local stack cid
  while IFS= read -r stack; do
    [[ -n "$stack" ]] || continue
    cid="$(compose_cmd_for_stack "$stack" ps -q "$service" 2>/dev/null || true)"
    if [[ -n "$cid" ]]; then
      printf '%s\n' "$cid"
      return
    fi
  done < <(active_stack_names)
}

compose_run_proxy_tests() {
  compose_cmd_for_stack nginx-proxy run --rm -T tests
}

compose_volume_keys() {
  local stack
  while IFS= read -r stack; do
    [[ -n "$stack" ]] || continue
    compose_cmd_for_stack "$stack" config --volumes 2>/dev/null || true
  done < <(active_stack_names) | sort -u
}

compose_volume_name() {
  local volume_key="$1"

  # First try per-stack compose labels (works when containers are running).
  local stack volume_name
  while IFS= read -r stack; do
    [[ -n "$stack" ]] || continue
    volume_name="$(docker volume ls -q \
      --filter "label=com.docker.compose.project=${stack}" \
      --filter "label=com.docker.compose.volume=${volume_key}" 2>/dev/null | head -1)"
    if [[ -n "$volume_name" ]]; then
      printf '%s\n' "$volume_name"
      return
    fi
  done < <(active_stack_names)

  # Fall back to the legacy monolithic project prefix preserved across all stacks.
  printf 'media-stack_%s\n' "$volume_key"
}
