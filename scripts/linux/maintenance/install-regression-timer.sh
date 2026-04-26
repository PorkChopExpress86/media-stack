#!/usr/bin/env bash
# install-regression-timer.sh — install (or uninstall) the systemd timer that
# runs the media-stack regression tests every Sunday at 02:00.
#
# Usage:
#   bash install-regression-timer.sh          # install / re-install
#   bash install-regression-timer.sh uninstall

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_DIR="${SCRIPT_DIR}/../systemd"
SYSTEMD_DIR="/etc/systemd/system"
SERVICE="media-stack-regression.service"
TIMER="media-stack-regression.timer"

need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Error: this script must be run as root (sudo)." >&2
    exit 1
  fi
}

do_install() {
  need_root
  echo "Installing ${SERVICE} and ${TIMER} → ${SYSTEMD_DIR}/"
  cp "${UNIT_DIR}/${SERVICE}" "${SYSTEMD_DIR}/${SERVICE}"
  cp "${UNIT_DIR}/${TIMER}"   "${SYSTEMD_DIR}/${TIMER}"

  systemctl daemon-reload
  systemctl enable --now "${TIMER}"

  echo
  echo "Done. Timer status:"
  systemctl status "${TIMER}" --no-pager
}

do_uninstall() {
  need_root
  echo "Disabling and removing ${TIMER} and ${SERVICE}…"
  systemctl disable --now "${TIMER}" 2>/dev/null || true
  rm -f "${SYSTEMD_DIR}/${TIMER}" "${SYSTEMD_DIR}/${SERVICE}"
  systemctl daemon-reload
  echo "Uninstalled."
}

case "${1:-install}" in
  install)   do_install ;;
  uninstall) do_uninstall ;;
  *) echo "Usage: $0 [install|uninstall]" >&2; exit 1 ;;
esac
