#!/usr/bin/env bash

# Shared Compose helpers for the legacy monolith and the modular stack files.
# Defaults stay on docker-compose.yaml so existing cron jobs keep their behavior.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ -z "${COMPOSE_PROJECT_NAME:-}" && -f "${PROJECT_ROOT}/.env" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*COMPOSE_PROJECT_NAME=(.*)$ ]] || continue
    value="${BASH_REMATCH[1]}"
    if [[ "$value" =~ ^\"(.*)\"$ ]]; then
      value="${BASH_REMATCH[1]}"
    elif [[ "$value" =~ ^\'(.*)\'$ ]]; then
      value="${BASH_REMATCH[1]}"
    fi
    COMPOSE_PROJECT_NAME="$value"
    break
  done < "${PROJECT_ROOT}/.env"
fi

LEGACY_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-media-stack}"
LEGACY_COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yaml"

MODULAR_STACK_NAMES=(
  nginx-proxy
  jellyfin
  arr-stack
  immich
  lan-apps
  proxied-apps
  monitoring
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
  if [[ "${MEDIA_STACK_MODE:-legacy}" != "modular" ]]; then
    printf '%s\n' "$LEGACY_PROJECT_NAME"
    return
  fi

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
  if [[ "${MEDIA_STACK_MODE:-legacy}" == "modular" ]]; then
    printf '%s\n' "$1"
  else
    printf '%s\n' "$LEGACY_PROJECT_NAME"
  fi
}

compose_env_file_for_stack() {
  local stack="$1"

  if [[ "${MEDIA_STACK_MODE:-legacy}" == "modular" ]]; then
    local stack_env="${PROJECT_ROOT}/${stack}/.env"
    if [[ -f "$stack_env" ]]; then
      printf '%s\n' "$stack_env"
      return
    fi
  fi

  if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    printf '%s\n' "${PROJECT_ROOT}/.env"
  fi
}

compose_file_args_for_stack() {
  local stack="$1"
  if [[ "${MEDIA_STACK_MODE:-legacy}" == "modular" ]]; then
    local compose_file
    compose_file="$(compose_file_for_stack "$stack")" || return 1
    printf '%s\n%s\n' "-f" "$compose_file"
  else
    printf '%s\n%s\n' "-f" "$LEGACY_COMPOSE_FILE"
  fi
}

compose_cmd_for_stack() {
  local stack="$1"
  shift

  local project compose_file env_file
  stack="$(normalize_stack_name "$stack")"
  project="$(compose_project_for_stack "$stack")"
  if [[ "${MEDIA_STACK_MODE:-legacy}" == "modular" ]]; then
    compose_file="$(compose_file_for_stack "$stack")" || return 1
  else
    compose_file="$LEGACY_COMPOSE_FILE"
  fi
  env_file="$(compose_env_file_for_stack "$stack")"

  if [[ -n "$env_file" ]]; then
    (cd "$PROJECT_ROOT" && docker compose --project-directory "$PROJECT_ROOT" --env-file "$env_file" -p "$project" -f "$compose_file" "$@")
  else
    (cd "$PROJECT_ROOT" && docker compose --project-directory "$PROJECT_ROOT" -p "$project" -f "$compose_file" "$@")
  fi
}

compose_ps_ids() {
  if [[ "${MEDIA_STACK_MODE:-legacy}" != "modular" ]]; then
    compose_cmd_for_stack "$LEGACY_PROJECT_NAME" ps -q
    return
  fi

  local stack
  while IFS= read -r stack; do
    [[ -n "$stack" ]] || continue
    compose_cmd_for_stack "$stack" ps -q 2>/dev/null || true
  done < <(active_stack_names)
}

compose_service_id() {
  local service="$1"

  if [[ "${MEDIA_STACK_MODE:-legacy}" != "modular" ]]; then
    compose_cmd_for_stack "$LEGACY_PROJECT_NAME" ps -q "$service" 2>/dev/null || true
    return
  fi

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
  if [[ "${MEDIA_STACK_MODE:-legacy}" == "modular" ]]; then
    compose_cmd_for_stack nginx-proxy run --rm -T tests
  else
    compose_cmd_for_stack "$LEGACY_PROJECT_NAME" run --rm -T tests
  fi
}

compose_volume_keys() {
  if [[ "${MEDIA_STACK_MODE:-legacy}" != "modular" ]]; then
    compose_cmd_for_stack "$LEGACY_PROJECT_NAME" config --volumes 2>/dev/null || true
    return
  fi

  local stack
  while IFS= read -r stack; do
    [[ -n "$stack" ]] || continue
    compose_cmd_for_stack "$stack" config --volumes 2>/dev/null || true
  done < <(active_stack_names) | sort -u
}

compose_volume_name() {
  local volume_key="$1"

  if [[ "${MEDIA_STACK_MODE:-legacy}" != "modular" ]]; then
    local volume_name
    volume_name="$(docker volume ls -q \
      --filter "label=com.docker.compose.project=${LEGACY_PROJECT_NAME}" \
      --filter "label=com.docker.compose.volume=${volume_key}" 2>/dev/null | head -1)"
    if [[ -n "$volume_name" ]]; then
      printf '%s\n' "$volume_name"
    else
      printf '%s_%s\n' "$LEGACY_PROJECT_NAME" "$volume_key"
    fi
    return
  fi

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

  printf '%s_%s\n' "$LEGACY_PROJECT_NAME" "$volume_key"
}
