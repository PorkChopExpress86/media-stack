#!/bin/sh

set -eu

API_BASE_URL="http://127.0.0.1:8080"
PREFS_URL="${API_BASE_URL}/api/v2/app/preferences"
SET_PREFS_URL="${API_BASE_URL}/api/v2/app/setPreferences"

log() {
  echo "[qb-port-sync] $*"
}

extract_number() {
  json="$1"
  key="$2"
  printf '%s' "$json" | sed -n "s/.*\"${key}\":\([0-9][0-9]*\).*/\1/p" | head -n1
}

extract_string() {
  json="$1"
  key="$2"
  printf '%s' "$json" | sed -n "s/.*\"${key}\":\"\([^\"]*\)\".*/\1/p" | head -n1
}

get_prefs() {
  wget -qO- "$PREFS_URL"
}

wait_for_webui() {
  attempts=0
  until prefs="$(get_prefs 2>/dev/null)"; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 30 ]; then
      log "ERROR: qBittorrent WebUI on 127.0.0.1:8080 did not become reachable"
      return 1
    fi
    sleep 2
  done
  printf '%s' "$prefs"
}

post_preferences() {
  payload="$1"
  wget -qO- --retry-connrefused --post-data "$payload" "$SET_PREFS_URL" >/dev/null
}

mode="${1:-}"

if [ "$mode" != "up" ] && [ "$mode" != "down" ]; then
  log "Usage: qb-port-sync.sh <up|down> [port] [vpn_interface]"
  exit 2
fi

before_json="$(wait_for_webui)"
before_port="$(extract_number "$before_json" "listen_port")"
before_iface="$(extract_string "$before_json" "current_network_interface")"
log "Current qBittorrent prefs: listen_port=${before_port:-unknown}, current_network_interface=${before_iface:-unknown}"

case "$mode" in
  up)
    forwarded_port="${2:-}"
    vpn_interface="${3:-tun0}"

    if [ -z "$forwarded_port" ] || ! printf '%s' "$forwarded_port" | grep -Eq '^[0-9]+$'; then
      log "ERROR: invalid forwarded port '$forwarded_port'"
      exit 1
    fi

    payload=$(printf 'json={"listen_port":%s,"current_network_interface":"%s","random_port":false,"upnp":false}' "$forwarded_port" "$vpn_interface")
    post_preferences "$payload"
    log "Applied forwarded port ${forwarded_port} on interface ${vpn_interface}"
    ;;
  down)
    payload='json={"listen_port":0,"current_network_interface":"lo","random_port":false,"upnp":false}'
    post_preferences "$payload"
    log "Applied down fallback (listen_port=0, current_network_interface=lo)"
    ;;
esac

after_json="$(wait_for_webui)"
after_port="$(extract_number "$after_json" "listen_port")"
after_iface="$(extract_string "$after_json" "current_network_interface")"
log "Updated qBittorrent prefs: listen_port=${after_port:-unknown}, current_network_interface=${after_iface:-unknown}"
