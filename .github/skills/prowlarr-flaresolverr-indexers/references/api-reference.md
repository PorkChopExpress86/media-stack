# Prowlarr API Reference

## Base URL
```
http://127.0.0.1:9696/api/v1
```

## Authentication
All requests require the `X-Api-Key` header with value from `.env` `PROWLARR_API_KEY`.

```
GET /indexer HTTP/1.1
Host: 127.0.0.1:9696
X-Api-Key: abc123...
Content-Type: application/json
```

## Core Endpoints

### Tags

#### List All Tags
```
GET /tag
```

Response:
```json
[
  {
    "id": 1,
    "label": "flaresolverr"
  }
]
```

#### Create Tag
```
POST /tag
Content-Type: application/json

{
  "label": "flaresolverr"
}
```

Response: Tag object with `id` and `label`.

#### Delete Tag
```
DELETE /tag/1
```

### IndexerProxy (Proxies)

#### List All Proxies
```
GET /indexerproxy
```

Response:
```json
[
  {
    "id": 1,
    "implementation": "FlareSolverr",
    "implementationName": "FlareSolverr",
    "name": "FlareSolverr",
    "host": "http://127.0.0.1:8191/",
    "port": null,
    "username": null,
    "password": null,
    "tags": [1],
    "configContract": "FlareSolverrSettings",
    "fields": [...]
  }
]
```

#### Create FlareSolverr Proxy
```
POST /indexerproxy
Content-Type: application/json

{
  "implementation": "FlareSolverr",
  "implementationName": "FlareSolverr",
  "configContract": "FlareSolverrSettings",
  "name": "FlareSolverr",
  "fields": [
    {
      "name": "host",
      "value": "http://127.0.0.1:8191/"
    }
  ],
  "tags": []
}
```

#### Update Proxy (Bind to Tag)
```
PUT /indexerproxy/1
Content-Type: application/json

{
  "id": 1,
  "implementation": "FlareSolverr",
  ...
  "tags": [1]
}
```

⚠️ **IMPORTANT**: PUT requires the ENTIRE proxy object from GET. Partial updates will fail.

### Indexer Schema

#### Get All Available Definitions
```
GET /indexer/schema
```

Response: Array of schema objects, one per available indexer definition.

```json
[
  {
    "id": 0,
    "name": "1337x",
    "implementation": "Cardigann",
    "implementationName": "Cardigann",
    "configContract": "CardigannSettings",
    "definitionName": "1337x",
    "infoLink": "https://1337x.to",
    "description": "1337x torrent tracker",
    "fields": [
      {
        "order": 0,
        "name": "baseUrl",
        "label": "Base URL",
        "value": "https://1337x.to/",
        "type": "text",
        "advanced": false
      },
      {
        "order": 1,
        "name": "flaresolverr",
        "label": "Use FlareSolverr",
        "helpText": "Enable for Cloudflare bypass",
        "value": true,
        "type": "info_flaresolverr"
      }
    ]
  }
]
```

### Indexer Instances

#### List All Indexer Instances
```
GET /indexer
```

Response:
```json
[
  {
    "id": 18,
    "name": "EZTV",
    "implementation": "Cardigann",
    "implementationName": "Cardigann",
    "definitionName": "eztv",
    "enable": true,
    "priority": 25,
    "appProfileId": 1,
    "downloadClientId": 0,
    "tags": [1],
    "added": "2026-04-22T12:00:00.000000Z",
    "fields": [
      {
        "name": "baseUrl",
        "value": "https://eztvx.to/"
      }
    ]
  }
]
```

#### Get Indexer by ID
```
GET /indexer/18
```

Response: Single indexer object (same structure as list).

#### Create Indexer Instance
```
POST /indexer
Content-Type: application/json

{
  "implementation": "Cardigann",
  "implementationName": "Cardigann",
  "configContract": "CardigannSettings",
  "name": "1337x",
  "definitionName": "1337x",
  "enable": true,
  "priority": 25,
  "appProfileId": 1,
  "downloadClientId": 0,
  "tags": [1],
  "fields": [
    {
      "name": "baseUrl",
      "value": "https://1337x.to/"
    }
  ]
}
```

**Required fields**:
- `implementation`: "Cardigann"
- `configContract`: From schema (e.g., "CardigannSettings")
- `name`: Display name
- `definitionName`: Must match schema definition exactly (case-sensitive)
- `fields`: Array from schema with configured `value` fields

**Response status codes**:
- `201 Created`: Indexer successfully created
- `400 Bad Request`: Missing required field or invalid payload
- `409 Conflict`: Indexer with same name already exists (may be soft conflict)

#### Update Indexer Instance
```
PUT /indexer/18
Content-Type: application/json

{
  "id": 18,
  "name": "EZTV",
  "enable": true,
  "tags": [1, 2],
  ...
}
```

⚠️ **IMPORTANT**: PUT requires the ENTIRE indexer object from GET. Omitting fields will reset them to defaults.

**Response status codes**:
- `200 OK`: Updated
- `202 Accepted`: Validation in progress
- `400 Bad Request`: Invalid payload

#### Delete Indexer Instance
```
DELETE /indexer/18
```

**Response status codes**:
- `200 OK`: Deleted
- `204 No Content`: Deleted (no response body)

## HTTP Status Codes

| Code | Meaning | Common Cause |
|------|---------|--------------|
| 200 | OK | Request successful |
| 201 | Created | Resource created successfully |
| 202 | Accepted | Request accepted, processing async (test indexer) |
| 204 | No Content | Successful delete, no response body |
| 400 | Bad Request | Invalid JSON, missing required field, or payload error |
| 401 | Unauthorized | Invalid API key |
| 404 | Not Found | Resource ID doesn't exist |
| 409 | Conflict | Duplicate indexer name or constraint violation |
| 500 | Internal Error | Prowlarr error; check logs |

## Example Workflows

### Complete: Add EZTV with FlareSolverr

1. **Get tag ID**:
   ```
   GET /tag
   # Find id where label="flaresolverr" (e.g., id=1)
   ```

2. **Get schema for definition**:
   ```
   GET /indexer/schema
   # Find item where definitionName="eztv"
   # Copy entire schema object for payload
   ```

3. **Create indexer from schema**:
   ```
   POST /indexer
   {
     "implementation": "Cardigann",
     "implementationName": "Cardigann",
     "configContract": "CardigannSettings",
     "name": "EZTV",
     "definitionName": "eztv",
     "enable": true,
     "priority": 25,
     "appProfileId": 1,
     "downloadClientId": 0,
     "tags": [1],
     "fields": [
       {
         "name": "baseUrl",
         "value": "https://eztvx.to/"
       }
     ]
   }
   # Response: id=18 (example)
   ```

4. **Test from UI or logs**:
   - Prowlarr UI: Settings → Indexers → click Test
   - Docker: `docker logs flaresolverr | grep -i challenge`

### Complete: Bind Proxy to Tag

1. **Get proxy ID** (FlareSolverr proxy):
   ```
   GET /indexerproxy
   # Find id where implementation="FlareSolverr" (e.g., id=1)
   ```

2. **Get full proxy object**:
   ```
   GET /indexerproxy/1
   ```

3. **Update tags**:
   ```
   PUT /indexerproxy/1
   {
     "id": 1,
     ... (entire object from GET)
     "tags": [1]
   }
   ```

## Troubleshooting

### 400 Bad Request on POST /indexer

**Problem**: Missing required field or invalid schema

**Solution**:
1. Copy entire schema object from `GET /indexer/schema`
2. Modify only `name`, `enable`, `tags`
3. Update field values but keep field structure
4. Check that `definitionName` matches schema exactly (case-sensitive)

### 409 Conflict on POST /indexer

**Problem**: Indexer with same name exists or duplicate constraint

**Solution**:
1. Use unique indexer names (e.g., "1337x-1", "1337x-2")
2. Or delete existing indexer first: `DELETE /indexer/{id}`

### PUT returns empty or partial object

**Problem**: Sent partial payload instead of full object

**Solution**:
- Always use: `GET /indexer/{id}` → modify → `PUT /indexer/{id}`
- Never construct payload manually; always base on GET response

## cURL Examples

### List indexers
```bash
curl -H "X-Api-Key: abc123" http://127.0.0.1:9696/api/v1/indexer | jq
```

### Test indexer connectivity (triggers validation)
```bash
curl -X POST \
  -H "X-Api-Key: abc123" \
  -H "Content-Type: application/json" \
  -d '{"id": 18}' \
  http://127.0.0.1:9696/api/v1/indexer/18/test
```

### Get schema for specific definition
```bash
curl -H "X-Api-Key: abc123" http://127.0.0.1:9696/api/v1/indexer/schema | jq '.[] | select(.definitionName=="1337x")'
```
