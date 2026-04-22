# FlareSolverr Log Analysis

## Overview

FlareSolverr logs reveal whether Cloudflare challenges are detected, solved, or if the site is blocking requests. Understanding logs is key to diagnosing validation errors.

## Viewing Logs

### Real-time Logs
```bash
docker logs -f flaresolverr
```

### Recent Logs
```bash
docker logs flaresolverr | tail -50
```

### Filter by Keyword
```bash
docker logs flaresolverr | grep -i "challenge\|solved\|forbidden"
```

## Log Patterns & Interpretation

### Successful Challenge Solve

```
[2026-04-22 12:30:45] [INFO] Request to https://1337x.to/
[2026-04-22 12:30:46] [DEBUG] Challenge detected. Title found: Just a moment...
[2026-04-22 12:30:48] [DEBUG] Challenge solved!
[2026-04-22 12:30:49] [INFO] Response status: 200 OK
```

**Interpretation**: ✅ FlareSolverr successfully bypassed Cloudflare and retrieved the page.

**Next step**: Check Prowlarr logs for how it parsed the response. If validation fails despite successful solve, the site may reject the solved request or have changed its structure.

### Challenge Detected But Not Solved

```
[2026-04-22 12:30:45] [INFO] Request to https://example.com/
[2026-04-22 12:30:46] [DEBUG] Challenge detected. Title found: Just a moment...
[2026-04-22 12:30:47] [ERROR] Failed to solve challenge
[2026-04-22 12:30:47] [ERROR] Timeout waiting for challenge page
```

**Interpretation**: ❌ FlareSolverr detected a Cloudflare challenge but couldn't solve it (timeout, browser crash, etc.).

**Causes**:
- Browser/Chromium crashed or out of memory
- FlareSolverr container resource constraints (CPU/RAM)
- Challenge complexity beyond FlareSolverr capability

**Solutions**:
1. Increase FlareSolverr container resources:
   ```yaml
   flaresolverr:
     deploy:
       resources:
         limits:
           cpus: '2'
           memory: 1G
   ```
2. Restart FlareSolverr: `docker-compose restart flaresolverr`
3. Check container health: `docker ps | grep flaresolverr`

### No Challenge (Direct Response)

```
[2026-04-22 12:30:45] [INFO] Request to https://eztv.to/
[2026-04-22 12:30:45] [DEBUG] No challenge detected
[2026-04-22 12:30:45] [INFO] Response status: 200 OK
```

**Interpretation**: Site doesn't require Cloudflare bypass (or VPN/proxy already in bypass list). FlareSolverr passed response through.

### Forbidden Response (403)

```
[2026-04-22 12:30:45] [INFO] Request to https://extratorrent.st/
[2026-04-22 12:30:46] [DEBUG] Challenge detected. Title found: Just a moment...
[2026-04-22 12:30:48] [DEBUG] Challenge solved!
[2026-04-22 12:30:49] [INFO] Response status: 403 Forbidden
```

**Interpretation**: ⚠️ FlareSolverr solved the challenge, but site returned 403 after bypass.

**Causes**:
- Site detecting request as coming from proxy/VPN and blocking it
- VPN IP on site's blocklist
- Site applying additional anti-bot after Cloudflare (rate-limit, suspicious patterns)
- Mirror URL no longer functional

**Solutions**:
1. Try different mirror URL (if indexer definition has multiple baseUrl options)
2. Replace indexer with alternative tracker
3. Check VPN provider; consider switching region
4. Add delays between requests (Prowlarr rate-limit settings)

### Connection Timeout

```
[2026-04-22 12:30:45] [INFO] Request to https://example.com/
[2026-04-22 12:30:50] [ERROR] Connection timeout
```

**Interpretation**: FlareSolverr couldn't reach the target site within timeout window.

**Causes**:
- Site offline or unreachable
- VPN connection issues
- Network latency from VPN to target
- Site blocking VPN IP

**Solutions**:
1. Test manually: `docker exec flaresolverr curl https://example.com`
2. Check VPN container health: `docker logs vpn | tail -20`
3. Verify DNS: `docker exec flaresolverr nslookup example.com`

### Invalid SSL Certificate

```
[2026-04-22 12:30:45] [INFO] Request to https://example.com/
[2026-04-22 12:30:46] [ERROR] SSL certificate validation failed
```

**Interpretation**: FlareSolverr couldn't verify site's SSL certificate.

**Causes**:
- Site using self-signed certificate
- Browser/CA bundle outdated in FlareSolverr container
- Man-in-the-middle proxy (e.g., corporate firewall)

**Solutions**:
1. Update FlareSolverr image: `docker-compose pull flaresolverr && docker-compose up -d flaresolverr`
2. Disable SSL verification (security risk): Check FlareSolverr environment variables
3. Use `http://` URL if available (not recommended)

## Prowlarr + FlareSolverr Interaction

### Request Flow

```
Prowlarr Test Button
      ↓
[Prowlarr API Handler]
      ↓
FlareSolverr Proxy (if tag applied)
      ↓
[FlareSolverr Container]
      ↓
Chromium Browser
      ↓
Target Site (with Cloudflare)
      ↓
Response → FlareSolverr → Prowlarr
```

### Logging Both Sides

**FlareSolverr logs**:
```bash
docker logs flaresolverr | tail -20
```

**Prowlarr logs** (shows parsing/validation):
```bash
docker logs prowlarr | tail -20
```

**Example sequence**:
1. Prowlarr: "Testing indexer EZTV"
2. FlareSolverr: "Challenge detected...", "Challenge solved!"
3. Prowlarr: "Received response from EZTV, parsing..."
4. Prowlarr: "✓ EZTV test successful" OR "✗ EZTV validation failed: ..."

### Parsing Errors vs Cloudflare Errors

**Is Cloudflare the problem?**
- Check FlareSolverr logs for "Challenge detected"
- If yes: Problem is site blocking post-solve (403), not Cloudflare bypass

**Is parsing the problem?**
- Check FlareSolverr logs show 200 OK
- Prowlarr logs show parsing error (HTML structure changed, regex no longer matches)
- Solution: Update indexer definition or find alternative

## Common Indexer-Specific Log Patterns

### 1337x
```
Challenge detected. Title found: Just a moment...
Challenge solved!
Response status: 200 OK
```
Expected behavior: Usually solves cleanly on first attempt.

### EZTV
```
No challenge detected
Response status: 200 OK
```
Expected behavior: Often doesn't require Cloudflare bypass; may skip FlareSolverr entirely.

### kickasstorrents
```
Challenge detected. Title found: Just a moment...
Challenge solved!
Response status: 200 OK
```
Expected behavior: Consistent Cloudflare protection; FlareSolverr handles reliably.

### ExtraTorrent.st (Known Issue)
```
Challenge detected. Title found: Just a moment...
Challenge solved!
Response status: 403 Forbidden
```
Expected behavior: Challenges are solved but site blocks post-solve. **Recommend replacing with 1337x**.

## Debugging Workflow

**If indexer test fails**:

1. Check FlareSolverr container:
   ```bash
   docker ps | grep flaresolverr
   # Should be "healthy" or "up"
   ```

2. View FlareSolverr logs:
   ```bash
   docker logs flaresolverr | grep -A 5 -B 5 "<indexer-url>"
   ```

3. Identify log pattern from above table

4. Check Prowlarr logs for parsing details:
   ```bash
   docker logs prowlarr | grep -i "indexer\|validation\|failed"
   ```

5. Decision tree:
   - FlareSolverr logs show "Challenge solved! 200 OK" → Problem is parsing/site change → Update indexer definition
   - FlareSolverr logs show "403 Forbidden" → Site blocking post-solve → Replace indexer
   - FlareSolverr logs show "Connection timeout" → Network/VPN issue → Check VPN container
   - FlareSolverr logs not present → Proxy not applied → Check tag binding

## Performance Monitoring

### Check FlareSolverr Resource Usage
```bash
docker stats flaresolverr --no-stream
```

**Target ranges**:
- CPU: < 50% (< 100% during challenge solving)
- Memory: 300-600 MB (< 1 GB)

If exceeding limits:
- Increase container resources
- Reduce concurrent requests from Prowlarr
- Restart FlareSolverr to clear memory leaks

### Average Challenge Solve Time
Typically 2-5 seconds per challenge. If consistently > 10 seconds:
- Check system load: `docker stats`
- Reduce other container resource usage
- Update FlareSolverr image to latest version
