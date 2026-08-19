# Two-node Docker deployment

The active Medha deployment uses two Debian hosts and one pinned container image with distinct
roles. The Kubernetes manifests remain historical reference and are not applied to these hosts.

| Host | Address | Role |
| --- | --- | --- |
| `medha-storage-node` | `10.0.0.20` | Cloudflared, Nginx, SeaweedFS dev/prod, backups |
| `medha-worker-node` | `10.0.0.10` | API dev/prod, PostgreSQL dev/prod, Redis dev/prod |

The addresses must be reserved in DHCP. Deployment preflight must stop if either address differs.
Public hostnames, development/production ports, and application binaries are unchanged.
The `medha-firewall` unit loads the host-specific nftables policy before either role starts.

## Deployed state (2026-08-20)

- Active image tag: `medha-split:20260820.1`.
- Preserved rollback image: `medha-all-in-one:rollback-20260820` (`1072e4bf…d5be98`).
- API binary SHA-256 on both nodes: `68f06372…720f`.
- Baseline after migration: both databases have 31 public tables and Goose migration 50.
- The stopped `medha` container and storage-side PostgreSQL/Redis directories are retained for the
  seven-day rollback window. Do not start that container after worker accepts writes without first
  reverse-synchronizing worker state.

## Build

Build on storage against the last known-good all-in-one image:

```bash
docker image inspect medha-all-in-one:latest
docker build --build-arg BASE_IMAGE=medha-all-in-one:latest \
  -f docker/Dockerfile.split -t medha-split:20260820.1 .
docker run --rm --entrypoint /bin/bash medha-split:20260820.1 \
  -n /opt/medha/scripts/role-entrypoint.sh
```

Export the image with `docker save`, verify its SHA-256 on worker, then load it with `docker load`.
Do not rebuild the application during an infrastructure-only migration.

## Cutover invariants

- Preserve `medha-all-in-one:latest` and the stopped `medha` container configuration for rollback.
- Take verified dev and prod dumps before stopping the old databases.
- Stop old APIs before the final database and Redis synchronization.
- Do not start both PostgreSQL copies from the same or concurrently writable directory.
- Validate worker directly before replacing the storage container.
- Reopen public writes only after public API and S3 checks pass.

## Rollback

Before writes reopen, stop both role units and restart the original `medha` container. After writes
reopen, stop the worker first and reverse-sync its PostgreSQL and Redis directories to storage before
starting the original container. Never start the stale storage-side PostgreSQL copy after worker has
accepted writes.
