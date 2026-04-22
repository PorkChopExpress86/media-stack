---
name: prowlarr-flaresolverr-indexers
description: 'Manage Prowlarr indexers with FlareSolverr for Cloudflare bypass. Use when: configuring torrent indexers, enabling Cloudflare-protected sites, troubleshooting indexer validation errors, adding/removing indexers, or managing proxy routing.'
argument-hint: 'Describe your Prowlarr/FlareSolverr task (e.g., "add 1337x with FlareSolverr", "fix validation error", "list enabled indexers")'
user-invocable: true
disable-model-invocation: false
---

# Prowlarr + FlareSolverr Indexer Management

## When to Use

This skill applies to tasks involving:
- **Adding new indexers** with Cloudflare protection to Prowlarr
- **Configuring FlareSolverr** as proxy for indexer routing
- **Troubleshooting indexer validation errors** (403 Forbidden, challenge detection)
- **Managing indexer tags and proxies** for automation
- **Testing and verifying** indexer connectivity and challenge solving
- **Replacing non-functional indexers** with working alternatives

## Architecture Overview

```
Prowlarr (Container)
├── Indexers (Cardigann YAML definitions)
├── Tags (routing labels)
├── Proxies (FlareSolverr + others)
└── API (http://127.0.0.1:9696/api/v1)
      ↓
  FlareSolverr (Container)
  ├── Cloudflare challenge solver
  └── HTTP/SOCKS endpoint (http://127.0.0.1:8191/)
      ↓
  Gluetun VPN (network namespace)
  └── Shared by all *arr services
```

## Prerequisites

- Docker Compose stack running with `prowlarr`, `flaresolverr`, and VPN containers
- `.env` file with `PROWLARR_API_KEY` variable
- FlareSolverr container healthy and reachable at `http://127.0.0.1:8191/`
- Direct network access from Prowlarr to FlareSolverr (same Docker network/namespace)

## Core Concepts

### Indexers

Prowlarr manages **indexer definitions** (YAML in Cardigann format) and **indexer instances** (enabled/disabled in database). Each instance maps to a definition and stores configuration state.

**Definition** = Template (read-only, shipped with Prowlarr)  
**Instance** = Active record in database (what you enable/disable/configure)

### Proxy Routing

Prowlarr routes requests through proxies via **tags**:
1. Create a tag (e.g., `flaresolverr`)
2. Assign tag to `IndexerProxy` record (links tag → FlareSolverr endpoint)
3. Apply tag to indexer instances (links indexer → routing)
4. Requests from tagged indexers automatically route through FlareSolverr

### Validation Errors

Common issues:
- **403 Forbidden after challenge solved**: Site may be blocking the resolved request or require specific headers
- **4xx errors without FlareSolverr logs**: Indexer definition URL may be outdated or invalid
- **Connection timeout**: FlareSolverr unreachable, VPN/network issue, or Prowlarr firewall blocked

## Workflow: Add a New Indexer with FlareSolverr

### Step 1: Verify FlareSolverr Configuration

```bash
# Check FlareSolverr reachability from Prowlarr container
docker exec prowlarr curl -s http://127.0.0.1:8191/ | head -c 200

# Expected: HTML response (FlareSolverr UI), no timeout/connection errors
```

### Step 2: Create or Verify FlareSolverr Tag

Use [query-tags.py](./scripts/query-tags.py) to check existing tags:

```bash
python3 .github/skills/prowlarr-flaresolverr-indexers/scripts/query-tags.py list
```

If `flaresolverr` tag exists, note its ID. Otherwise, create it:

```bash
python3 .github/skills/prowlarr-flaresolverr-indexers/scripts/query-tags.py create flaresolverr
```

### Step 3: Verify FlareSolverr IndexerProxy Exists

```bash
python3 .github/skills/prowlarr-flaresolverr-indexers/scripts/query-proxies.py list
```

Look for a row with `implementation=FlareSolverr` and `host=http://127.0.0.1:8191/`. If missing, create it:

```bash
python3 .github/skills/prowlarr-flaresolverr-indexers/scripts/query-proxies.py create-flaresolverr
```

Note the proxy `id` and verify it's bound to the tag:

```bash
python3 .github/skills/prowlarr-flaresolverr-indexers/scripts/query-proxies.py bind-to-tag <proxy_id> <tag_id>
```

### Step 4: Check Indexer Definitions

Query available definitions to find your target indexer:

```bash
python3 .github/skills/prowlarr-flaresolverr-indexers/scripts/query-definitions.py list --search "1337x"
```

Output shows definition name (e.g., `1337x`) and metadata. If found, note the definition name for Step 5.

### Step 5: Add Indexer Instance

Use [add-indexer.py](./scripts/add-indexer.py):

```bash
python3 .github/skills/prowlarr-flaresolverr-indexers/scripts/add-indexer.py \
  --definition 1337x \
  --name "1337x" \
  --tag <tag_id> \
  --enable
```

Expected output:
```
✓ Added indexer: id=21 name=1337x enabled=True tags=[1]
```

If validation fails during creation (HTTP 400), check the error message for missing required fields in the definition schema.

### Step 6: Test Connectivity

From Prowlarr UI:
1. Navigate to **Settings → Indexers**
2. Find the newly added indexer
3. Click **Test** to verify FlareSolverr can solve challenges and the indexer responds

Monitor FlareSolverr logs during test:

```bash
docker logs flaresolverr | tail -20
```

Expected (success):
```
Challenge detected. Title found: Just a moment...
Challenge solved!
```

Expected (failure, but recoverable):
```
Received response 403 Forbidden
# → Site returned 403 after challenge; try different mirror URL in indexer config
```

### Step 7: Verify Tag Applied

```bash
python3 .github/skills/prowlarr-flaresolverr-indexers/scripts/query-indexers.py list --filter tag=<tag_id>
```

Confirm new indexer appears in the list with `tags=[tag_id]`.

## Workflow: Replace a Non-Functional Indexer

If an indexer fails validation persistently (e.g., 403 Forbidden even with FlareSolverr solving challenges):

### Step 1: Identify Problematic Indexer

```bash
python3 .github/skills/prowlarr-flaresolverr-indexers/scripts/query-indexers.py list
```

Find the indexer with `enabled=False` or persistent test failures.

### Step 2: Search for Alternatives

Query definitions for similar indexers:

```bash
python3 .github/skills/prowlarr-flaresolverr-indexers/scripts/query-definitions.py list \
  --search "torrent" \
  --flaresolverr-only
```

The `--flaresolverr-only` flag filters definitions that support FlareSolverr challenges.

### Step 3: Add Replacement Indexer

Follow **Step 5–7** from the "Add a New Indexer" workflow using the new definition name.

### Step 4: Remove Failed Indexer

Once replacement is tested and working:

```bash
python3 .github/skills/prowlarr-flaresolverr-indexers/scripts/remove-indexer.py <indexer_id>
```

## Decision Tree: Troubleshooting Validation Errors

```
Indexer test fails
├─ Error: "Connection timeout" or "unreachable"
│  └─ Check: FlareSolverr healthy? (docker ps | grep flaresolverr)
│     └─ Restart: docker-compose restart flaresolverr
│  └─ Check: Prowlarr → FlareSolverr network connectivity
│     └─ Test: docker exec prowlarr curl http://127.0.0.1:8191/
├─ Error: "403 Forbidden" (after FlareSolverr logs show challenge solved)
│  └─ Site is blocking despite challenge bypass
│     └─ Try: Different mirror URL in indexer definition
│     └─ Try: Replace with alternative indexer (see "Replace Non-Functional" workflow)
├─ Error: "Invalid response" or "parsing error"
│  └─ Indexer definition may be outdated
│     └─ Check: Prowlarr logs (docker logs prowlarr)
│     └─ Search: Alternative definition or mirror URL
├─ Error: "HTTP 400" during indexer creation
│  └─ Missing required field in schema
│     └─ Check: API response for field name error message
│     └─ Verify: Definition name matches exactly (case-sensitive)
```

## Reference Documentation

- [API Endpoints & Payloads](./references/api-reference.md) — Detailed Prowlarr API calls, parameter documentation, error codes
- [FlareSolverr Log Analysis](./references/flaresolverr-logs.md) — Interpreting challenge solver output, debugging connection issues
- [Common Indexer Definitions](./references/indexer-definitions.md) — Pre-vetted definitions with FlareSolverr support

## Scripts

All scripts read from `.env` for `PROWLARR_API_KEY` and assume Prowlarr at `http://127.0.0.1:9696/api/v1`.

| Script | Purpose | Common Usage |
|--------|---------|--------------|
| [query-tags.py](./scripts/query-tags.py) | List, create, and manage tags | `python3 query-tags.py list` |
| [query-proxies.py](./scripts/query-proxies.py) | List proxies, create FlareSolverr, bind to tags | `python3 query-proxies.py list` |
| [query-definitions.py](./scripts/query-definitions.py) | Search available indexer definitions | `python3 query-definitions.py list --search "1337x"` |
| [query-indexers.py](./scripts/query-indexers.py) | List, filter, and inspect indexer instances | `python3 query-indexers.py list --filter tag=1` |
| [add-indexer.py](./scripts/add-indexer.py) | Add new indexer instance from definition | `python3 add-indexer.py --definition 1337x --name "1337x" --tag 1 --enable` |
| [remove-indexer.py](./scripts/remove-indexer.py) | Delete indexer instance | `python3 remove-indexer.py 21` |

Run any script with `--help` for detailed argument documentation:

```bash
python3 scripts/add-indexer.py --help
```

## Example Workflows

### Add 1337x with FlareSolverr
```bash
# Verify tag exists
python3 scripts/query-tags.py list | grep flaresolverr

# Add indexer, apply tag, enable
python3 scripts/add-indexer.py --definition 1337x --name "1337x" --tag 1 --enable

# Test from Prowlarr UI or logs
docker logs -f flaresolverr
```

### Find all available torrent definitions with FlareSolverr
```bash
python3 scripts/query-definitions.py list --search "torrent" --flaresolverr-only
```

### List all indexers currently using FlareSolverr tag
```bash
python3 scripts/query-indexers.py list --filter tag=1
```

### Replace failed ExtraTorrent.st with 1337x
```bash
# Find ExtraTorrent.st
python3 scripts/query-indexers.py list | grep -i extratorrent

# Note the id (e.g., 20), then remove
python3 scripts/remove-indexer.py 20

# Add replacement
python3 scripts/add-indexer.py --definition 1337x --name "1337x" --tag 1 --enable

# Verify
python3 scripts/query-indexers.py list --filter tag=1
```

## Notes & Best Practices

1. **Always test after adding**: Indexer may pass creation but fail validation due to site structure changes
2. **Monitor FlareSolverr logs**: They reveal whether challenges are detected, solved, or if the site is blocking post-solve
3. **Use tags for organization**: Group indexers by region, category, or priority using tags
4. **Backup database before bulk changes**: Snapshot `prowlarr_data:/config/prowlarr.db` before major operations
5. **Check Prowlarr version**: API structure can differ across versions; this skill targets Prowlarr 2.3.5+

## Limitations & Known Issues

- **ExtraTorrent.st validation failure**: Some mirrors return 403 even after FlareSolverr challenge bypass; recommend swapping for 1337x or other public tracker
- **FlareSolverr timeout on heavy load**: If Prowlarr makes many concurrent requests, FlareSolverr may timeout; monitor container resources
- **VPN-related blocks**: If Gluetun VPN IP is on indexer blocklist, FlareSolverr bypass won't help; try different VPN provider/region
