#!/usr/bin/env python3
"""Export qBittorrent + Gluetun metrics for node_exporter textfile collector."""

from __future__ import annotations

import json
import os
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from http.cookiejar import CookieJar
from pathlib import Path

WEBUI_URL = os.getenv("QB_WEBUI_URL", "http://127.0.0.1:8080").rstrip("/")
WEBUI_USER = os.getenv("QB_WEBUI_USER", "")
WEBUI_PASSWORD = os.getenv("QB_WEBUI_PASSWORD", "")
GLUETUN_HEALTH_URL = os.getenv("GLUETUN_HEALTH_URL", "http://127.0.0.1:9999")
METRICS_FILE = Path(os.getenv("METRICS_FILE", "/textfile/qbittorrent.prom"))
POLL_INTERVAL = int(os.getenv("POLL_INTERVAL", "30"))
REQUEST_TIMEOUT = int(os.getenv("REQUEST_TIMEOUT", "10"))

AUTH_STATE = {"logged_in": False}
COOKIE_JAR = CookieJar()
OPENER = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(COOKIE_JAR))


def http_get_json(url: str):
    request = urllib.request.Request(url, method="GET")
    with OPENER.open(request, timeout=REQUEST_TIMEOUT) as response:
        return json.loads(response.read().decode("utf-8"))


def http_post(url: str, data: dict[str, str]):
    payload = urllib.parse.urlencode(data).encode("utf-8")
    request = urllib.request.Request(url, data=payload, method="POST")
    with OPENER.open(request, timeout=REQUEST_TIMEOUT) as response:
        return response.read().decode("utf-8", errors="replace")


def login() -> None:
    if not WEBUI_USER or not WEBUI_PASSWORD:
        return
    try:
        body = http_post(
            f"{WEBUI_URL}/api/v2/auth/login",
            {"username": WEBUI_USER, "password": WEBUI_PASSWORD},
        )
        AUTH_STATE["logged_in"] = body.strip().lower() == "ok."
    except Exception:
        AUTH_STATE["logged_in"] = False


def fetch_qb_json(path: str):
    url = f"{WEBUI_URL}{path}"
    try:
        return http_get_json(url)
    except (urllib.error.HTTPError, urllib.error.URLError, json.JSONDecodeError):
        login()
        return http_get_json(url)


def gluetun_health() -> int:
    try:
        request = urllib.request.Request(GLUETUN_HEALTH_URL, method="GET")
        with OPENER.open(request, timeout=REQUEST_TIMEOUT):
            return 1
    except Exception:
        return 0


def escape_label(value: str) -> str:
    return value.replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')


def write_metrics() -> None:
    transfer = fetch_qb_json("/api/v2/transfer/info")
    main_data = fetch_qb_json("/api/v2/sync/maindata")
    torrents = main_data.get("torrents", {})

    state_counts: Counter[str] = Counter()
    for torrent in torrents.values():
        state = str(torrent.get("state", "unknown"))
        state_counts[state] += 1

    incomplete_states = {
        "downloading",
        "forcedDL",
        "metaDL",
        "stalledDL",
        "queuedDL",
        "pausedDL",
        "checkingDL",
    }

    active_downloads = sum(
        state_counts[state]
        for state in ("downloading", "forcedDL", "metaDL", "checkingDL")
    )
    queued_downloads = sum(state_counts[state] for state in ("queuedDL",))
    stalled_downloads = sum(state_counts[state] for state in ("stalledDL",))
    paused_downloads = sum(state_counts[state] for state in ("pausedDL",))
    total_torrents = len(torrents)
    incomplete_torrents = sum(
        count for state, count in state_counts.items() if state in incomplete_states
    )

    lines = [
        '# HELP qbittorrent_download_speed_bytes_per_second Current qBittorrent download speed in bytes per second',
        '# TYPE qbittorrent_download_speed_bytes_per_second gauge',
        f'qbittorrent_download_speed_bytes_per_second {int(transfer.get("dl_info_speed", 0))}',
        '# HELP qbittorrent_upload_speed_bytes_per_second Current qBittorrent upload speed in bytes per second',
        '# TYPE qbittorrent_upload_speed_bytes_per_second gauge',
        f'qbittorrent_upload_speed_bytes_per_second {int(transfer.get("up_info_speed", 0))}',
        '# HELP qbittorrent_torrents_total Total number of torrents in qBittorrent',
        '# TYPE qbittorrent_torrents_total gauge',
        f'qbittorrent_torrents_total {total_torrents}',
        '# HELP qbittorrent_torrents_incomplete Torrents not yet fully completed',
        '# TYPE qbittorrent_torrents_incomplete gauge',
        f'qbittorrent_torrents_incomplete {incomplete_torrents}',
        '# HELP qbittorrent_torrents_active_downloads Torrents actively downloading or verifying',
        '# TYPE qbittorrent_torrents_active_downloads gauge',
        f'qbittorrent_torrents_active_downloads {active_downloads}',
        '# HELP qbittorrent_torrents_queued_downloads Torrents waiting in the queue',
        '# TYPE qbittorrent_torrents_queued_downloads gauge',
        f'qbittorrent_torrents_queued_downloads {queued_downloads}',
        '# HELP qbittorrent_torrents_stalled_downloads Torrents stalled during download',
        '# TYPE qbittorrent_torrents_stalled_downloads gauge',
        f'qbittorrent_torrents_stalled_downloads {stalled_downloads}',
        '# HELP qbittorrent_torrents_paused_downloads Torrents paused while incomplete',
        '# TYPE qbittorrent_torrents_paused_downloads gauge',
        f'qbittorrent_torrents_paused_downloads {paused_downloads}',
        '# HELP gluetun_health Gluetun health endpoint status (1=healthy, 0=unhealthy)',
        '# TYPE gluetun_health gauge',
        f'gluetun_health {gluetun_health()}',
        '# HELP qbittorrent_torrents_state Number of torrents by state',
        '# TYPE qbittorrent_torrents_state gauge',
    ]

    for state, count in sorted(state_counts.items()):
        lines.append(f'qbittorrent_torrents_state{{state="{escape_label(state)}"}} {count}')

    METRICS_FILE.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", dir=str(METRICS_FILE.parent), delete=False) as tmp:
        tmp.write("\n".join(lines))
        tmp.write("\n")
        tmp_path = Path(tmp.name)
    tmp_path.replace(METRICS_FILE)
    METRICS_FILE.chmod(0o644)


def main() -> None:
    while True:
        try:
            write_metrics()
        except Exception as exc:
            # Emit a minimal failure marker so the textfile collector still has something to read.
            METRICS_FILE.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile("w", dir=str(METRICS_FILE.parent), delete=False) as tmp:
                tmp.write('# HELP qbittorrent_exporter_up Exporter health (1=healthy, 0=unhealthy)\n')
                tmp.write('# TYPE qbittorrent_exporter_up gauge\n')
                tmp.write('qbittorrent_exporter_up 0\n')
                tmp.write(f'# HELP qbittorrent_exporter_last_error_seconds Unix timestamp of the last exporter error\n')
                tmp.write(f'# TYPE qbittorrent_exporter_last_error_seconds gauge\n')
                tmp.write(f'qbittorrent_exporter_last_error_seconds {int(time.time())}\n')
                tmp.write(f'# HELP qbittorrent_exporter_last_error_info Constant 1 with error text label\n')
                tmp.write(f'# TYPE qbittorrent_exporter_last_error_info gauge\n')
                tmp.write(f'qbittorrent_exporter_last_error_info{{error="{escape_label(str(exc))}"}} 1\n')
                tmp_path = Path(tmp.name)
            tmp_path.replace(METRICS_FILE)
            METRICS_FILE.chmod(0o644)
        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
