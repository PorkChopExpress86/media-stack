---
name: docker-nginx-debugging
description: 'Diagnose and fix Docker container startup failures, nginx 500 errors in reverse proxy routing, and volume permission issues. Use when: containers won''t start, nginx returns 502/504 gateway errors, sites return 500 errors, or volumes have permission problems.'
argument-hint: 'Describe the issue (e.g., "container won''t start", "nginx 500 error on example.com", "volume permission denied")'
user-invocable: true
disable-model-invocation: false
---

# Docker & Nginx Debugging Workflow

## When to Use

This skill applies to troubleshooting:
- **Container startup failures** — container exits immediately, won't stay running
- **Nginx 500/502/504 errors** — reverse proxy can't reach upstream, routing misconfigured
- **Volume permission issues** — permission denied errors, mount failures, read-only issues
- **Service connectivity failures** — containers can't reach each other, DNS resolution problems
- **Nginx configuration errors** — invalid upstream config, SSL cert issues, proxy directives

## Architecture Context

Your stack uses:
- **Docker Compose** orchestration with named volumes and custom networks
- **Nginx container** (reverse proxy) routing traffic to internal services (Prowlarr, Sonarr, Immich, Audiobookshelf, etc.)
- **Gluetun VPN** shared network namespace for `*arr` services
- **Volume mounts** with host-side data directories (e.g., `./data/` → container `/config`)
- **Internal Docker DNS** — containers reach each other by service name (e.g., `http://prowlarr:9696/api`)

### Common Failure Modes

| Symptom | Likely Causes |
|---------|---------------|
| Container exits immediately | Bad entrypoint, missing volumes, env vars not set, insufficient resources |
| Nginx 502 Bad Gateway | Upstream unreachable, upstream crashed, wrong port/hostname, network isolation |
| Nginx 500 error from upstream | Upstream app crashed, permission denied on config, SSL cert issues |
| Permission denied on volumes | Wrong owner/group on mount point, incorrect `user:` in docker-compose, SELinux/AppArmor |
| DNS resolution fails | Service not running, typo in service name, wrong network, outdated container IP cache |

---

## Phase 1: Pre-Flight Checks

Run these once to verify the Docker environment is healthy before diagnosing individual containers.

### 1a. Verify Docker Daemon

```bash
docker ps -a
```

**Expected output**: List of containers with status.  
**If fails**: Docker daemon not running. Start with `systemctl start docker` or equivalent.

### 1b. Verify Docker Networks

```bash
docker network ls
```

**Look for**: Your stack's network (e.g., `mediaserver_default` or custom network name).

```bash
docker network inspect <network-name>
```

**Expected**: All relevant containers should be connected to the network with assigned IPs.  
**If missing**: Containers not on same network; they won't reach each other by hostname.

### 1c. Verify Volumes Exist

```bash
docker volume ls | grep mediaserver
```

For host-bound mounts, verify mount points exist:

```bash
ls -la data/ config/
```

**If missing**: Create with `mkdir -p` or `docker volume create <name>`.

### 1d. Check Host-Side Permissions

```bash
ls -la data/ config/
```

**Look for**: Owner/group matches the container's user. If containers run as `root`, host permissions don't matter as much. If containers run as non-root (e.g., `65534:65534` for `nobody`), host directory must be readable/writable by that UID/GID.

---

## Phase 2: Container Startup Diagnosis

For a container that won't start or keeps exiting:

### 2a. Get Container Status

```bash
docker ps -a | grep <service-name>
```

**Note the status column**:
- `Exited (0)` — Graceful exit
- `Exited (1)` or `Exited (127)` — Error
- `Restarting` — Stuck in restart loop

### 2b. Read Full Logs

```bash
docker logs <container-id-or-name> --tail 100
```

**Common patterns to search for**:
- `Permission denied` → Volume/file permission issue (Phase 5)
- `Connection refused` → Upstream service not running or port mismatch
- `panic` or `fatal` → Application crash, likely config error
- `port already in use` → Port conflict, another container owns the port
- `no such file or directory` → Volume not mounted, missing config file

### 2c. Inspect Container Config

```bash
docker inspect <container-name> | jq '.[] | {Env, VolumeMounts, Ports, NetworkSettings}'
```

**Verify**:
- Environment variables are set (check for required vars like API keys, URLs)
- Volumes are mounted to expected paths inside container
- Ports are exposed/published as expected
- Network is correct

### 2d. If App Requires External Services

Check upstream services are running first:

```bash
# Example: If Sonarr fails, check if Gluetun is up
docker ps | grep gluetun
docker logs gluetun | tail -20
```

Some services (especially in VPN namespace) need the VPN container healthy before starting.

---

## Phase 3: Nginx Reverse Proxy Debugging

When nginx returns 502, 504, or 500 errors.

### 3a. Verify Nginx Container Is Running

```bash
docker ps | grep nginx
docker logs nginx --tail 50
```

**Look for errors in startup or during requests** (especially `upstream unreachable`, `connection refused`, `no resolver`).

### 3b. Check Nginx Configuration Syntax

```bash
docker exec nginx nginx -t
```

**Expected**: `syntax is ok` and `test is successful`.  
**If fails**: Config has syntax error. Review the config file (usually mounted at `/etc/nginx/` in container).

### 3c. Inspect Upstream Definitions

```bash
docker exec nginx cat /etc/nginx/conf.d/*.conf
```

**Look for**:
- `upstream <name>` blocks — server hostname, port (must be resolvable inside container)
- `proxy_pass` directives — should point to upstream name with `http://` scheme
- `resolver` directive — must be set for Docker internal DNS (usually `127.0.0.11:53`)

**Example valid upstream**:
```nginx
upstream sonarr {
    server sonarr:8989;  # service name (will resolve via Docker DNS)
}

server {
    listen 80;
    server_name sonarr.example.com;
    
    resolver 127.0.0.11:53;  # Docker internal DNS
    set $upstream sonarr;     # Create variable to trigger DNS resolution per-request
    
    location / {
        proxy_pass http://$upstream;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### 3d. Verify Upstream Service Is Reachable from Nginx Container

```bash
docker exec nginx curl -v http://sonarr:8989/
```

**Expected**: HTTP response (even if 401 or 404, means service is reachable).  
**If timeout/refused**: 
- Service not running (`docker ps | grep sonarr`)
- Wrong port in nginx config
- Service not on same network as nginx

### 3e. Check Nginx Access/Error Logs During Request

In one terminal, tail logs:
```bash
docker logs nginx -f
```

In another, generate a request:
```bash
curl -v http://localhost/sonarr/ 2>&1 | head -50
```

**Look for**:
- Upstream address in `upstream` phrase (confirms resolution worked)
- HTTP status from upstream in response
- Connection errors with specific upstream IP

### 3f. Test Upstream Directly (Without Nginx)

```bash
docker exec nginx curl -v http://sonarr:8989/
docker exec sonarr curl -v http://localhost:8989/
```

**If direct curl works, nginx config issue. If curl fails, upstream service problem** (go to Phase 2).

---

## Phase 4: Service Connectivity & DNS Debugging

When containers can't reach each other or DNS fails.

### 4a. Verify Services Are on Same Network

```bash
docker network inspect <network-name> | jq '.Containers'
```

**All interacting containers must appear here.**

### 4b. Test DNS Resolution Inside Container

```bash
docker exec <container-name> nslookup sonarr
docker exec <container-name> getent hosts sonarr
```

**Expected**: IP address assigned to the service.  
**If fails**: 
- Service not running (`docker ps | grep sonarr`)
- Service not connected to network
- Service name typo in docker-compose

### 4c. Test Connectivity Between Containers

```bash
docker exec <source-container> curl -v http://<target-service>:<port>/
docker exec <source-container> nc -zv <target-service> <port>
```

**Expected**: Connection succeeds (response code, or just connection established).  
**If refused/timeout**: Target service not listening, wrong port, or network isolation.

### 4d. Check Container Network Mode

```bash
docker inspect <container-name> | jq '.HostConfig.NetworkMode'
```

**Should be**:
- `<network-name>` (default — uses bridge network)
- `container:<other-container>` (shares namespace with another container, e.g., shared Gluetun for VPN)

**If wrong**: Containers won't reach each other on standard bridge network.

---

## Phase 5: Volume & Permission Debugging

When you see `permission denied` or volume mount errors.

### 5a. Verify Volume Is Mounted Inside Container

```bash
docker exec <container-name> mount | grep <config-path>
docker exec <container-name> ls -la <config-path>
```

**Expected**: File listing with readable/writable access.  
**If fails**: Volume not mounted, or mounted read-only.

### 5b. Check Host-Side Mount Point Permissions

```bash
ls -la data/<service-name>_data/
```

**Note the owner/group and permissions** (e.g., `1000:1000` = UID 1000, GID 1000).

### 5c. Identify Container's User

```bash
docker inspect <container-name> | jq '.Config.User'
```

**Output**:
- Empty or `null` → Runs as root (UID 0)
- `<uid>:<gid>` or `<username>` → Non-root user

### 5d. Match Container User to Host Directory

If container user is non-root, host directory owner must match:

```bash
# Example: Container runs as UID 1000
docker exec <container-name> id

# Host mount point should be owned by UID 1000
sudo chown -R 1000:1000 data/<service-name>_data/
```

### 5e. Fix Common Permission Issues

**Case 1: Container runs as root, but volume is read-only**
```bash
docker inspect <container-name> | jq '.Mounts[] | select(.Source | contains("data"))'
```

Look for `"ReadOnly": true`. In docker-compose, remove `:ro` from volume mount:
```yaml
volumes:
  - ./data/sonarr_data:/config  # Remove :ro if present
```

**Case 2: Container runs as non-root, host mount has wrong owner**
```bash
# Get container's UID
docker exec <container-name> id

# Fix host directory (example: UID 1000)
sudo chown -R 1000:1000 data/sonarr_data/
sudo chmod 755 data/sonarr_data/
```

**Case 3: SELinux or AppArmor blocking access**
```bash
# Check if SELinux is active (on RHEL/CentOS/Fedora)
getenforce

# Temporarily disable for testing
sudo setenforce 0

# Or, check AppArmor (on Ubuntu/Debian)
sudo aa-status | grep docker
```

If disabled the block and issue goes away, add SELinux context or AppArmor profile to docker-compose.

### 5f. Rebuild Container After Permission Changes

```bash
docker-compose up -d <service-name>
docker logs <service-name> --tail 50
```

---

## Workflow Decision Tree

Use this flow to narrow down the issue:

```
START: Issue observed
│
├─→ Container won't start or keeps crashing?
│   ├─→ Go to Phase 2 (Container Startup Diagnosis)
│   └─→ If solved, DONE. If not, continue below.
│
├─→ Nginx error (502, 504, or 500 from app)?
│   ├─→ Go to Phase 3 (Nginx Reverse Proxy Debugging)
│   ├─→ If "upstream unreachable" → Check if upstream running (Phase 2)
│   └─→ If solved, DONE.
│
├─→ "Permission denied" error in logs?
│   ├─→ Go to Phase 5 (Volume & Permission Debugging)
│   └─→ If solved, DONE.
│
├─→ Containers can't reach each other?
│   ├─→ Go to Phase 4 (Service Connectivity Debugging)
│   └─→ If solved, DONE.
│
└─→ If still unresolved:
    ├─→ Re-check Phase 1 (pre-flight checks)
    ├─→ Run `docker-compose logs` for all containers
    ├─→ Check docker-compose.yaml for typos (service names, ports, volumes)
    └─→ Consider rebuilding stack: `docker-compose down && docker-compose up -d`
```

---

## Quick Reference: Common Commands

| Goal | Command |
|------|---------|
| List all containers | `docker ps -a` |
| View container logs | `docker logs <name> --tail 100 -f` |
| Exec command in container | `docker exec -it <name> bash` |
| Inspect container config | `docker inspect <name>` |
| Check resource usage | `docker stats <name>` |
| Verify network connectivity | `docker exec <from> curl http://<to>:<port>/` |
| Restart service | `docker-compose restart <service>` |
| Rebuild and restart | `docker-compose up -d --force-recreate <service>` |
| View docker-compose config | `docker-compose config` |
| Check volume mount status | `docker exec <name> mount \| grep /config` |

---

## Prevention Tips

1. **Always include `healthcheck:` in docker-compose** for critical services — helps identify when upstream is down
2. **Use explicit `depends_on:` in docker-compose** if one service must start after another
3. **Test nginx config before deployment**: `docker exec nginx nginx -t`
4. **Monitor logs proactively**: `docker-compose logs -f` during stack startup
5. **Document your nginx upstreams**: Include comments in nginx config for service names and ports
6. **Use named networks** instead of default bridge for better isolation and control
7. **Bind volumes explicitly** — avoid relying on auto-created volumes; use `docker volume create` + docker-compose `external: true`
