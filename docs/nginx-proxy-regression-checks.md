# Nginx Proxy Regression Checks

This guide documents the nginx proxy accessibility test flow used to catch breaking changes after stack updates or configuration edits.

## Purpose

The regression test verifies that enabled Nginx Proxy Manager proxy hosts are still reachable through the proxy layer.

It is designed to answer one simple question:

> Did a recent change break public access to one or more proxied services?

## What the test checks

The test service:

- reads enabled proxy host records from Nginx Proxy Manager's `proxy_host` table in `database.sqlite`
- derives whether each host should be tested with `http` or `https`
- resolves each domain to the internal `nginx` container IP so the request exercises the proxy path instead of bypassing it
- measures response time for each request
- marks a domain as passing only when the response status is `200` or `401`
- marks a domain as passing when a `302` matches a checked-in known-good redirect baseline
- marks any request slower than 10 seconds as failed
- appends results to the root-level `test.log`

## Files involved

- `Dockerfile.tests` — builds the lightweight test image
- `nginx-proxy/compose.yml` — defines the `tests` service
- `nginx-proxy/config/nginx-proxy-regression-baseline.json` — checked-in baseline of acceptable redirect targets
- `scripts/linux/testing/test-domains.sh` — main test runner
- `scripts/linux/testing/run-tests-scheduled.sh` — wrapper for scheduled runs
- `test.log` — append-only execution log in the repository root

## How to run it

### Build the test image

```bash
docker compose --project-directory "$PWD" --env-file nginx-proxy/.env -p nginx-proxy -f nginx-proxy/compose.yml build tests
```

### Run all enabled proxy checks

```bash
docker compose --project-directory "$PWD" --env-file nginx-proxy/.env -p nginx-proxy -f nginx-proxy/compose.yml run --rm -T tests
```

### Run a single domain

```bash
docker compose --project-directory "$PWD" --env-file nginx-proxy/.env -p nginx-proxy -f nginx-proxy/compose.yml run --rm -T -e TEST_DOMAIN=immich.ohmygoshwhatever.com tests
```

### Run the scheduled wrapper manually

```bash
bash scripts/linux/testing/run-tests-scheduled.sh
```

### Example cron entry

```bash
(crontab -l 2>/dev/null; echo "0 2 * * 0 /mnt/samsung/Docker/MediaServer/scripts/linux/testing/run-tests-scheduled.sh") | crontab -
```

## Log format

Each run writes a start line, one line per domain, and a summary line.

Example:

```text
[2026-04-22 22:53:56] START nginx proxy domain test run: total=1 timeout=10s filter=immich.ohmygoshwhatever.com
[2026-04-22 22:53:57] PASS domain=immich.ohmygoshwhatever.com scheme=https status=200 time=0.013378s reason=allowed-status nginx_ip=172.18.0.17
[2026-04-22 22:53:57] SUMMARY total=1 passed=1 failed=0
```

## Pass and fail rules

### Passing statuses

- `200`
- `401`
- `302` when both the status and `Location` header match an entry in `nginx-proxy/config/nginx-proxy-regression-baseline.json`

### Failing conditions

- any other HTTP status, including `302`, `500`, `502`, and `504`
- DNS resolution failures
- TLS failures
- connection failures
- timeouts
- any response slower than 10 seconds

## Exit codes

- `0` — all checked domains passed
- `1` — one or more checked domains failed
- `2` — missing required tooling or required files
- `3` — no matching enabled domains found or the requested domain filter did not match anything

## Notes about redirects

This test now allows selected `302` redirects as healthy when they match the checked-in baseline file.

That lets login and app-entry redirects pass without making all redirects automatically acceptable.

If a service changes its expected redirect target in a legitimate way, update `nginx-proxy/config/nginx-proxy-regression-baseline.json` to reflect the new known-good behavior.

## Troubleshooting

### The test says a domain is missing

Check that the proxy host is enabled in Nginx Proxy Manager. Disabled hosts are intentionally skipped.

### The test fails with `Requested domain not found among enabled proxy hosts`

The `TEST_DOMAIN` value must exactly match an enabled domain listed in Nginx Proxy Manager.

### The test returns unexpected `302` failures

Check the actual `Location` header returned by the app and compare it with `nginx-proxy/config/nginx-proxy-regression-baseline.json`. If the redirect changed intentionally, update the baseline.

### The log file is not updating

The test writes to `test.log` at the repository root. Make sure the compose run is started from the project root so the bind mount points at the correct workspace path.

## Recommended workflow

Use this sequence after nginx, compose, container image, or service routing changes:

1. Build the test image if the test tooling changed.
2. Run the full regression suite.
3. Review `test.log` for any new failures.
4. If needed, re-run a single domain with `TEST_DOMAIN=...` while debugging.
5. Repeat after the fix until the relevant domain passes.
