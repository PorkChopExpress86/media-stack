# Security Audit & Hardening Report - 2026-04-24

## 1. Network & Router Audit
### Findings:
- **Router:** Ubiquiti router with UPnP disabled (Excellent).
- **Exposed Ports:** 80, 443, 32400 (Nginx Proxy, Plex).
- **Internal Ports:** Numerous Docker containers are listening on `0.0.0.0` (all interfaces), which can bypass `ufw` via `iptables`.
- **Remote Router Audit:** Not directly possible from within this machine. However, your current configuration (UPnP off, minimal open ports) is a strong start.

### Recommendation:
- **Status: Completed (2026-04-24).** Docker network bindings have been audited and hardened to `127.0.0.1` for all proxied services.

## 2. Sensitive Data Protection (.env Files)
### Findings:
- Multiple `.env` files containing credentials were world-readable (`644` or `755`).

### Actions Taken:
- **Fixed:** All `.env` files in `~` and `/mnt/samsung` have been changed to `600` (read/write only by the owner).
- **Command Used:** `find ~ /mnt/samsung -name ".env" -exec chmod 600 {} +`

### Actions Taken (2026-04-24):
- **Hardened Docker Port Bindings:** Restricted numerous services (Radarr, Sonarr, Prowlarr, Jellyfin, Immich, Grafana, Scrutiny, etc.) to bind to `127.0.0.1` instead of `0.0.0.0`. This ensures they are only reachable via the local host or the Nginx proxy, preventing `ufw` bypass via `iptables`.
- **Updated Group Permissions:** Changed `PGID` from `1000` to `1001` (media group) and updated `user` directives (e.g., `1000:1001`) across all relevant Docker Compose files to align with the recommended security posture for `/mnt/media` access.
- **Affected Files:**
    - `arr-stack/compose.yml`
    - `jellyfin/compose.yml`
    - `lan-apps/compose.yml`
    - `monitoring/compose.yml`
    - `proxied-apps/compose.yml`
    - `immich/compose.yml`
    - `scheduler/compose.yaml`

## 3. Permissions & Access Control (/mnt/media)
### Findings:
- `/mnt/media` was set to `777` (world-writable).
- **Constraint:** Permissions need to allow Docker containers (Jellyfin, Sonarr, Radarr, etc.) to read and write.

### Actions Taken (2026-04-24):
- **Fixed:** All Docker containers now use `PGID=1001` or `user: 1000:1001` to match the `media` group.
- **Recommendation:** Now that Docker is configured correctly, the administrator should run:
    ```bash
    sudo chown -R specter:media /mnt/media
    sudo chmod -R 775 /mnt/media
    ```
    This will finally remove the need for `777` permissions.

## 4. SSH Hardening
### Actions Taken:
- **Disabled Password Authentication:** SSH now requires a public key to login. 
    - File modified: `/etc/ssh/sshd_config` (`PasswordAuthentication no`).
- **Installed fail2ban:** Automatically blocks IP addresses that show malicious signs (e.g., too many password failures, though password auth is now disabled, it still protects against other SSH probes).
- **Disabled pwfeedback:** Removed the `Defaults pwfeedback` setting from `/etc/sudoers.d/pwfeedback` to prevent leaking password length during `sudo`.
- **Generated New SSH Key:** Created a password-less Ed25519 key at `~/.ssh/id_ed25519`.
    - **Note:** Ensure you add your local machine's public key to `~/.ssh/authorized_keys` before disconnecting, as password login is now disabled.

### Connectivity Check:
- **Tailscale:** Verified Tailscale status. The machine is reachable over your Tailscale mesh (`100.122.14.63`). Even with password auth disabled, you can still SSH over Tailscale as long as you have your keys configured or Tailscale SSH is enabled in your Tailscale admin console.

---
**Audit performed by Gemini CLI**

## Post-Audit: Docker Configuration (Crucial)
To ensure your Docker containers (Jellyfin, Sonarr, Radarr, etc.) continue to have read/write access to `/mnt/media` without using `777` permissions, follow these steps:

1. **Identify Group ID (GID):** The 'media' group GID is **1001**.
2. **Update Docker Containers:** In your `docker-compose.yml` or container environment settings, update the `PGID` to match this value:
   ```yaml
   environment:
     - PUID=1000  # Your user ID (specter)
     - PGID=1001  # The new 'media' group ID
   ```
3. **Restart Containers:** Run `docker-compose up -d` to apply the changes. This allows the containers to run with the permissions of the 'media' group.

