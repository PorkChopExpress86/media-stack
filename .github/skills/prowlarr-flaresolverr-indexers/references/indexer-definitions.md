# Common Indexer Definitions with FlareSolverr Support

This reference documents pre-vetted indexer definitions that work with FlareSolverr in the media-stack setup.

## Quick Reference Table

| Definition | Name | Type | FlareSolverr | Status | Notes |
|-----------|------|------|--------------|--------|-------|
| `1337x` | 1337x | Torrent | ✅ | ✓ Working | Popular public tracker; reliable Cloudflare bypass |
| `eztv` | EZTV | TV Episodes | ✅ | ✓ Working | Often no Cloudflare protection; FlareSolverr passes through |
| `kickasstorrents-ws` | kickasstorrents.ws | Torrent | ✅ | ✓ Working | Consistent Cloudflare protection; reliable solve |
| `extratorrent-st` | ExtraTorrent.st | Torrent | ✅ | ⚠️ Broken | 403 Forbidden after FlareSolverr bypass; **not recommended** |
| `torrent9` | Torrent9 | Torrent | ✅ | ? Untested | French tracker; likely working |
| `thepiratebay` | The Pirate Bay | Torrent | ✅ | ? Untested | Cloudflare-protected; should work |
| `torrentkitty` | TorrentKitty | Torrent | ✅ | ? Untested | Asia-based; may have geoblocking |

## How to Check Definitions

### Query Available Definitions
```bash
cd /mnt/samsung/Docker/MediaServer
python3 .github/skills/prowlarr-flaresolverr-indexers/scripts/query-definitions.py list
```

### Search for Specific Definition
```bash
python3 .github/skills/prowlarr-flaresolverr-indexers/scripts/query-definitions.py list --search "1337x"
```

### List Only FlareSolverr-Compatible Definitions
```bash
python3 .github/skills/prowlarr-flaresolverr-indexers/scripts/query-definitions.py list --flaresolverr-only
```

## Detailed Profiles

### ✅ 1337x

**Definition**: `1337x`  
**Official Site**: https://1337x.to/  
**Type**: General torrent tracker  
**Cloudflare**: Protected → FlareSolverr required  
**Availability**: Stable, mirrors available  

**Recommended Configuration**:
```bash
python3 scripts/add-indexer.py \
  --definition 1337x \
  --name "1337x" \
  --tag 1 \
  --enable
```

**Testing**:
```bash
# Test from Prowlarr UI or watch logs:
docker logs -f flaresolverr | grep -i "1337x\|challenge"
```

**Expected Behavior**:
- FlareSolverr detects Cloudflare challenge
- Solves within 3-5 seconds
- Returns 200 OK with torrent list
- Prowlarr parses successfully

**Known Issues**: None (as of 2026-04-22)

**Alternative Mirrors**: If `https://1337x.to/` fails, define custom `baseUrl` in indexer config:
- `https://1337x.st/`
- `https://1337xx.to/`

---

### ✅ EZTV

**Definition**: `eztv`  
**Official Site**: https://eztvx.to/  
**Type**: TV episode tracker  
**Cloudflare**: Sometimes protected → FlareSolverr optional  
**Availability**: Stable

**Recommended Configuration**:
```bash
python3 scripts/add-indexer.py \
  --definition eztv \
  --name "EZTV" \
  --tag 1 \
  --enable
```

**Testing**:
- Most requests bypass FlareSolverr (no challenge detected)
- When challenge occurs, FlareSolverr solves reliably
- Very low failure rate

**Expected Behavior**:
- May show "No challenge detected" in FlareSolverr logs
- Returns 200 OK with episode list
- Prowlarr parses successfully

**Known Issues**: None (as of 2026-04-22)

---

### ✅ kickasstorrents.ws

**Definition**: `kickasstorrents-ws` or `kickasstorrents-to`  
**Official Site**: https://kickass.ws/  
**Type**: General torrent tracker  
**Cloudflare**: Protected → FlareSolverr required  
**Availability**: Stable

**Recommended Configuration**:
```bash
python3 scripts/add-indexer.py \
  --definition kickasstorrents-ws \
  --name "kickass.ws" \
  --tag 1 \
  --enable
```

**Testing**:
- Consistent Cloudflare protection
- FlareSolverr reliably solves challenges
- Quick response times (2-4 seconds)

**Expected Behavior**:
- FlareSolverr detects challenge consistently
- Solves within 3-5 seconds
- Returns 200 OK
- Prowlarr parses successfully

**Known Issues**: None (as of 2026-04-22)

---

### ⚠️ ExtraTorrent.st (NOT RECOMMENDED)

**Definition**: `extratorrent-st`  
**Official Site**: https://extratorrent.st/  
**Type**: General torrent tracker  
**Cloudflare**: Protected → FlareSolverr bypasses but site rejects  
**Availability**: Site functional but blocks FlareSolverr-bypassed requests  

**Status**: 🔴 **BROKEN** — Do not use

**Failure Pattern**:
```
FlareSolverr logs show: "Challenge solved! 200 OK"
Prowlarr validation shows: "403 Forbidden"
```

The site successfully detects and bypasses Cloudflare via FlareSolverr, but then returns 403 Forbidden. Root cause unknown — possibly:
- VPN IP blocklist
- Post-Cloudflare bot detection
- Site-specific rate limiting

**Workaround**: Replace with `1337x` or other public tracker from list above.

**Removal Command**:
```bash
# Find ExtraTorrent.st id
python3 scripts/query-indexers.py list | grep -i extratorrent

# Delete (e.g., id=20)
python3 scripts/remove-indexer.py 20 --force

# Add replacement
python3 scripts/add-indexer.py --definition 1337x --name "1337x" --tag 1 --enable
```

---

## Untested Definitions (Available, Status Unknown)

These are available in Prowlarr but not yet validated in this deployment:

### torrent9
- **Definition**: `torrent9`
- **Type**: French general torrent tracker
- **Likely Status**: Working (similar structure to 1337x)
- **Test if**: Need French language torrents

### thepiratebay
- **Definition**: `thepiratebay`
- **Type**: General torrent tracker (legendary)
- **Likely Status**: Working (Cloudflare-protected, common FlareSolverr use case)
- **Test if**: Need backup tracker

### torrentkitty
- **Definition**: `torrentkitty`
- **Type**: Asia-based torrent tracker
- **Likely Status**: Working (FlareSolverr compatible)
- **Test if**: Need Asia-region torrents or backup

## How to Test New Definition

1. **Query availability**:
   ```bash
   python3 scripts/query-definitions.py list --search "torrent9"
   ```

2. **Add with tag**:
   ```bash
   python3 scripts/add-indexer.py \
     --definition torrent9 \
     --name "Torrent9" \
     --tag 1
   ```

3. **Monitor logs during first test**:
   ```bash
   docker logs -f flaresolverr &
   docker logs -f prowlarr &
   # Then click Test in Prowlarr UI
   ```

4. **Outcomes**:
   - ✅ FlareSolverr logs show "Challenge solved! 200 OK" + Prowlarr shows ✓ → **Working**
   - ⚠️ FlareSolverr shows "403 Forbidden" → **Broken (like ExtraTorrent.st)**
   - ⚠️ FlareSolverr shows "Connection timeout" → **Network issue or site down**
   - ⚠️ Prowlarr shows parsing error despite successful FlareSolverr → **Definition outdated**

5. **Document result**:
   - If working: Update this reference with ✅ status
   - If broken: Look for alternative or skip
   - If timeout: Check VPN/network before giving up

## Performance Characteristics

### Fast Indexers (< 3 seconds response time)
- `kickasstorrents-ws`: Cloudflare challenge solve + response ~2-3 seconds
- `1337x`: Cloudflare challenge solve + response ~3-4 seconds

### Variable Indexers (2-10 seconds)
- `eztv`: Highly variable; sometimes no challenge (< 1s), sometimes challenged (2-5s)
- `thepiratebay`: May have rate-limiting delays

### Slow/Unreliable
- None validated yet; test new definitions before adding to rotation

## Regional Availability

| Indexer | US | EU | Asia | Notes |
|---------|----|----|------|-------|
| 1337x | ✅ | ✅ | ✅ | Mirrors in multiple regions |
| EZTV | ✅ | ✅ | ✅ | Global CDN |
| kickasstorrents.ws | ✅ | ✅ | ⚠️ | May require different region |
| Torrent9 | ⚠️ | ✅ | ⚠️ | French-focused |
| thepiratebay | ✅ | ✅ | ⚠️ | Geoblocking varies by region |

## Maintenance

Monitor these indexers regularly:

```bash
# Check all FlareSolverr-tagged indexers status
python3 scripts/query-indexers.py list --filter tag=1

# Test each from Prowlarr UI or:
curl -X POST \
  -H "X-Api-Key: $PROWLARR_API_KEY" \
  http://127.0.0.1:9696/api/v1/indexer/21/test
# (where 21 is indexer id)
```

## Contributing

To add or update indexer status:
1. Test indexer against current deployment
2. Document FlareSolverr behavior and parsing outcomes
3. Note any configuration quirks or mirror URLs
4. Update this reference and open a discussion/PR
