# Socket Access Test — Example Invocations

## Default (watchtower + /var/run/docker.sock)

```bash
bash .github/skills/socket-mount-validation/scripts/test-socket-access.sh
```

## Custom container

```bash
bash .github/skills/socket-mount-validation/scripts/test-socket-access.sh \
  --container myservice \
  --socket /var/run/docker.sock
```

## Env variable overrides

```bash
CONTAINER=myservice SOCKET_PATH=/run/docker.sock \
  bash .github/skills/socket-mount-validation/scripts/test-socket-access.sh
```

## Expected passing output

```text
[2026-04-22 20:05:52] START socket-access test container=watchtower socket=/var/run/docker.sock
[2026-04-22 20:05:52] PASS  container=watchtower check=socket-present path=/var/run/docker.sock method=host-stat
[2026-04-22 20:05:52] INFO  container=watchtower check=identity configured_user=1000:1000 group_add=986
[2026-04-22 20:05:53] PASS  container=watchtower check=docker-api-ping response=OK method=helper-container
[2026-04-22 20:05:53] PASS  container=watchtower check=log-scan reason=no-docker-api-errors-in-recent-50-lines
[2026-04-22 20:05:53] SUMMARY result=PASS failures=0
```

## Failure interpretation

| Symptom | Likely cause | Remedy |
|---------|--------------|--------|
| `socket-present path-missing` | Mount not wired | Check `volumes:` in compose |
| `socket-present exists-but-not-a-socket` | Wrong source path | Verify host path is a socket (`stat /var/run/docker.sock`) |
| `docker-api-ping permission-denied` | Group not inherited at runtime | Verify `group_add:` and `DOCKER_GID` in `.env` |
| `docker-api-ping unexpected-response` | Helper image pull failed or curl unavailable | Set `HELPER_IMAGE` to an image with curl pre-installed |
| `log-scan docker-api-errors-found` | Container is actively failing to talk to Docker | Check logs, re-verify group membership and socket permissions |

## Notes

- Log written to `socket-access.log` in project root (override with `LOG_PATH=`).
- Script exits `0` on full pass, `1` on any check failure, `2` on missing tooling or container not running.
- Run from any directory; it auto-resolves project root from its own path.
