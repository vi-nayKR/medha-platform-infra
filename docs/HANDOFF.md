# Medha infrastructure continuation handoff

Last updated: 2026-07-18 (Asia/Kolkata), after the Cloudflare Access lockdown
and the dev **and prod** namespace GitOps cutovers.

This document is the continuation context for another engineer or AI model.
It describes the intended architecture, the verified live state, completed
changes, remaining work, required owner actions, and safety constraints. Both
`dev` and `prod` are now fully on the unsuffixed, Argo-managed manifests —
there is no outstanding namespace cutover left.

## Goal

Operate symmetric `dev` and `prod` Kubernetes environments behind Cloudflare.
Both namespaces use the same short internal service names and manifest
shape, with environment differences supplied through kustomize overlay
patches (node paths, replica counts, secrets).

Final public naming standard (now fully live):

| Service | Production | Development | Exposure |
|---|---|---|---|
| Web | `medha.dev` | `dev.medha.dev` | Public Cloudflare Worker (`medha-web` / `medha-web-dev`) |
| Web alias | `www.medha.dev` -> apex | none | Public 308 redirect (Cloudflare Ruleset) |
| API | `api.medha.dev` | `api-dev.medha.dev` | Public tunnel -> Traefik Ingress |
| Admin | `admin.medha.dev` (Pages) | `admin-dev.medha.dev` (Worker) | Cloudflare Access |
| S3 API | `s3.medha.dev` | `s3-dev.medha.dev` | Public only as required for uploads |
| MinIO console | `minio.medha.dev` | `minio-dev.medha.dev` | Cloudflare Access, port 9001 |
| PostgreSQL | no public hostname | no public hostname | Namespace-private |
| Redis | no public hostname | no public hostname | Namespace-private |
| Argo CD | no public hostname | no public hostname | SSH local forward only |

Note: `admin.medha.dev` is a genuine Cloudflare **Pages** project
(`medha-admin-panel`), while `admin-dev.medha.dev` is a **Workers
custom domain** bound to the `medha-admin-panel-dev` Worker (Workers Static
Assets, deployed via Workers Builds from the medha-admin-panel repo's `dev`
branch). These are different underlying mechanisms — don't assume symmetry
when touching one.

Both namespaces now use exactly the same service names: `backend`, `postgres`,
`redis`, `minio` (unsuffixed). The legacy suffixed resources
(`backend-prod`, `postgres-prod`, `minio-prod`, `redis-prod`, and their dev
equivalents) have been deleted in both namespaces.

## Repository locations and branches

Workspace: `/Users/vinay/Developer/Medha`

| Repository | Working branch | Purpose |
|---|---|---|
| `medha-infra` | `main` | Desired Kubernetes, Cloudflare Terraform, Argo applications, validation and operations docs |
| `medha-api` | `dev` locally; production is remote branch `prod` | Go backend and CD workflow |
| `medha-web` | `main` | Public web Worker; contains prod and dev custom-domain declarations |
| `medha-admin-panel` | `dev` (also builds a separate Worker per branch: `dev`->`medha-admin-panel-dev`, `prod`->`medha-admin-panel`) | Admin app |
| `medha-android` | `dev` | Android client using the dev API hostname |

## SSH access

```sshconfig
Host medha-master
    HostName ssh-master.medha.dev
    User medha-master
    ProxyCommand /opt/homebrew/bin/cloudflared access ssh --hostname %h

Host medha-worker
    HostName ssh-worker.medha.dev
    User medha-worker
    ProxyCommand /opt/homebrew/bin/cloudflared access ssh --hostname %h

Host medha-storage
    HostName ssh-storage.medha.dev
    User medha-storage
    ProxyCommand /opt/homebrew/bin/cloudflared access ssh --hostname %h
```

Use `medha-master` for `kubectl`. The Cloudflare Tunnel runs on `medha-storage`
(`/etc/cloudflared/config.yml`, systemd service `cloudflared`). It is **not**
GitOps-managed — edit it directly via SSH, back up first
(`cp config.yml config.yml.pre-<change>`), validate with
`cloudflared tunnel ingress validate`, then `systemctl restart cloudflared`.

## Cloudflare: fully migrated

Terraform (`medha-infra/terraform/cloudflare/`) now owns and has imported:

- 6 tunnel DNS records (api, api-dev, s3, s3-dev, minio, minio-dev)
- The `admin.medha.dev` Pages domain
- The `admin-dev.medha.dev` Workers custom domain
  (`cloudflare_workers_custom_domain`, **not** `cloudflare_pages_domain` —
  there is no Pages project named `medha-admin-panel-dev`)
- A Cloudflare Access policy ("Medha operators") + Access applications for
  `admin`, `admin-dev`, `minio`, `minio-dev`, and the three SSH hostnames
- The `www` -> apex 308 redirect (`cloudflare_ruleset`, phase
  `http_request_dynamic_redirect`) — coexists fine with `www` being a Workers
  custom domain, since the redirect rule fires before the Worker is invoked
- `terraform.tfvars` holds `account_id`/`zone_id`/`access_emails`, gitignored;
  token is supplied via `TF_VAR_cloudflare_api_token` from
  `~/.config/cloudflare/medha-infra-token` (Zone: DNS, Single Redirects;
  Account: Zero Trust, Cloudflare Pages, Workers Scripts — all edit)

Retired entirely (DNS + tunnel + Access, no longer resolve):
`minio-console.medha.dev`, `minio-console-dev.medha.dev`,
`argocd.medha.dev`.

Fixed live misconfigurations (not caused by this session, just found and
corrected): `medha.dev`/`www.medha.dev` were bound to the
`medha-web-dev` Worker instead of `medha-web` (content happened to be correct
— a prod-configured build had been pushed to the dev script as a stopgap);
`dev.medha.dev` was still tunnel-routed to the Go backend
(returning a bare 404) instead of the `medha-web-dev` Worker.

All verification from the old table now passes: Access-gated hostnames
302 to Cloudflare Access login; `minio*`/`minio-dev*` serve the console
(port 9001); `s3*`/`s3-dev*` remain the S3 API (port 9000, 403 XML
anonymous); `www` returns a 308; `dev.medha.dev` serves the actual
web app.

**Not yet done:** the dev admin Pages/Workers custom-domain project name was
already correct (`medha-admin-panel-dev` exists and works) — the "create the
dev admin Pages project" item from the original plan turned out to be moot,
it was already live as a Worker, just needed the Access + Terraform
bookkeeping which is now done.

## Kubernetes: dev is cut over, prod is not

### Dev (done)

The dev namespace now runs entirely on the new unsuffixed manifests, applied
directly and then handed to a new Argo Application (`medha-infra/argocd/medha-dev.yaml`,
`automated: {prune: true, selfHeal: true}`). Confirmed `Synced`/`Healthy`.

The old `medha-backend-dev` Argo Application (tracking `medha-api.git` path
`deployments/k8s/dev`, which no longer exists after the deployment
centralization) has been deleted, along with the old suffixed Deployments/
StatefulSet (`backend-dev`, `minio-dev`, `redis-dev`, `postgres-dev`) and the
old `backend-ingress-dev`/`minio-ingress-dev` Ingress objects.

Bugs found and fixed by actually running the new manifests (all in
`kubernetes/base/*.yaml` and the dev overlay, committed to `main`):

1. **postgres/minio/redis used `volumeClaimTemplates`** (fresh dynamic PVC)
   instead of the `hostPath` directories the live data actually sits on
   (`/mnt/ssd/postgres-*`, `/mnt/hdd/minio-*`, `/mnt/ssd/redis-*`, pinned by
   `workload-type: worker|storage` node labels, no PVC/PV exists at all).
   Fixed to declare a placeholder hostPath in base, patched to the real path
   per overlay in `workload-patch.yaml`.
2. **backend**: `runAsNonRoot: true` can't verify the image's non-numeric
   `USER appuser` without a numeric UID. Fixed with explicit
   `runAsUser: 100` / `runAsGroup: 101` (confirmed via the image's
   `/etc/passwd`, not guessed).
3. **redis**: container defaulted to root; the official image's entrypoint
   tries to `setuid` to the `redis` user internally, but
   `capabilities.drop: [ALL]` blocks `CAP_SETUID`, so it crash-looped with
   `setresuid failed: Operation not permitted`. Fixed with explicit
   `runAsUser: 999` / `runAsGroup: 999` (also confirmed via `/etc/passwd`)
   so it never needs to drop privileges itself.
4. **postgres major-version mismatch**: manifest specified
   `postgis/postgis:17-3.4`, but the live hostPath data was initialized
   under Postgres 16 (`postgis/postgis:16-3.4-alpine`). Postgres correctly
   refused to start rather than risk corruption. Downgraded the image to
   match. **A deliberate 16->17 upgrade (pg_upgrade or dump/restore) is
   separate future work, not something to redo as a side effect of this
   migration.**
5. **ResourceQuota too small**: the dev namespace's `namespace-quota`
   (previously untracked, cluster-only) was `limits.cpu: 2, limits.memory:
   3Gi` — sized for the old footprint. The new manifests' combined limits
   are ~3.1 CPU / 5.25Gi. Raised dev to `4 CPU / 6Gi` (matching prod's
   already-correct but likewise untracked live value) and committed both as
   tracked `ResourceQuota` objects in each `namespace.yaml`.
6. **`database-url` pointed at the legacy `postgres-dev-service` hostname**
   inside `backend-dev-secrets`. Re-sealed the secret with the same
   user/password/db but the new unsuffixed `postgres` service hostname.
7. **Missing Traefik Middleware**: the new Ingress references
   `kube-system-medha-security-headers`, which didn't exist live (Traefik
   silently drops routes with unresolvable middleware refs -> 404 for
   everything). The Middleware was already defined in
   `platform/traefik/security-headers.yaml` but never applied. Applied it
   directly (not the full `platform/` kustomization — that also bundles
   `platform/cloudflared/host-migration-config.yml`, which documents the
   systemd-managed tunnel on `medha-storage`; the Kubernetes tunnel workload
   was removed from the platform kustomization to prevent a credential-less
   duplicate from being deployed).
8. A repo credential for `medha-infra` didn't exist in Argo CD at all (only
   `medha-api-repo`). Cloned the same username/token as a new
   `medha-infra-repo` secret in `argocd` namespace — it had sufficient
   access. If it stops working, this needs its own dedicated credential.

Verified end-to-end: `postgres-0`, `redis-0`, `minio-0` all came up against
the **existing** hostPath data (tables, AOF file, and the `medha-dev` bucket
all intact — no data was copied or recreated).
`https://api-dev.medha.dev/health` returns `200 ok-v2 (dev-local)`
through the real Cloudflare -> Traefik -> backend path.

### Prod (done)

Prod now runs entirely on the new unsuffixed manifests, applied directly and
then handed to a new Argo Application (`medha-infra/argocd/medha-prod.yaml`).
Confirmed `Synced`/`Healthy`. Unlike dev, this Application has **no**
`automated` block — production stays manually approval-gated, per the safety
constraint; syncs are triggered explicitly via the `operation` field.

Sign-off was obtained before scaling down (load was very low at the time —
1m CPU on backend pods). The old `medha-backend-prod` Argo Application
(reconciling from `medha-api.git` branch `prod`, path `deployments/k8s/prod`)
was deleted (`--cascade=orphan`, confirmed no finalizer), along with the old
suffixed Deployments/StatefulSet (`backend-prod`, `minio-prod`, `redis-prod`,
`postgres-prod`) and the old `backend-ingress-prod`/`minio-ingress-prod`
Ingress objects.

Since prod's base manifests are shared with dev, the UID/capabilities/
Postgres-version/Middleware bugs dev hit did **not** recur — they were
already fixed at the base level. Two new, prod-specific bugs surfaced instead:

1. **`db-secrets`' `postgres-password` was stale.** Don't trust a secret's
   claimed value without checking it authenticates over the *real* network
   path: testing via `-h localhost` from inside the same pod hit
   `pg_hba.conf`'s `trust`-authenticated loopback rule, which accepts *any*
   password and gave a false positive for both candidates. Testing via the
   Service ClusterIP (hitting the actual `host all all all scram-sha-256`
   rule) proved `db-secrets` fails and the password already embedded in
   `backend-prod-secrets`' `database-url` is the one that actually works.
   Used that verified value for the new `postgres-secrets` SealedSecret, not
   the literal "pull it from db-secrets" instruction.
2. **`kustomization.yaml` had `newTag: latest`** instead of a pinned SHA —
   would have deployed whatever `latest` resolves to in the registry instead
   of the currently-running, validated build, bundling an unvalidated app
   change into the infra cutover. Pinned to the exact live SHA
   (`2a915812a2972314d7c987f296c68a6c378dc974`).

**Operational lesson, already paid for once:** all three of the above were
fixed by editing files locally and applying directly to the live cluster via
raw `kubectl apply` — *before* committing/pushing to `medha-infra`. The
moment `argocd/medha-prod.yaml` was applied and synced, Argo pulled the
stale `main` branch (still containing both bugs) and reverted the live
fixes, briefly resurrecting a crash-looping extra pod on the wrong image
with the wrong secret. Commit and push GitOps-managed changes to the actual
git remote *before* creating/syncing the Argo Application that will read
them — a local working-tree edit and a live `kubectl apply` are both
invisible to Argo, which only ever reconciles against git.

Verified end-to-end: `postgres-0` came up against the existing hostPath data
with all 35 tables intact; `minio-0` has the real `medha-prod` bucket;
`redis-0` responds to `PING`; `https://api.medha.dev/health`
returns `200` through the real Cloudflare -> Traefik -> backend path. As a
side effect of finally applying the correct base manifests, prod's
`minio.medha.dev` now serves the console (port 9001) and
`s3.medha.dev` the S3 API (port 9000) — this mapping was
previously backwards in the legacy Ingress.

## Recent Operational Fixes (July 19, 2026)

The following operational issues were resolved in this session:

1. **Database Schema Repair (`medha-api`)**:
   - The dev database `medha_dev` on `postgres-0` had migration `00032_admin_assignment_engine.sql` marked as applied (`is_applied = t` in `goose_db_version`), but its schema changes (`job_leads`, `platform_fee_config` tables and `events.platform_fee` column) were completely missing. This caused the Go backend's `/api/v2/admin/events` query to fail with a `500 Internal Error`.
   - Manually applied the missing migration `00032` schemas directly to `medha_dev` database via `psql` to restore consistency. The endpoint now returns successfully.
2. **Dynamic API Hostname Sniffing**:
   - Replaced static build-time `VITE_API_BASE_URL` configs in both the public website (`medha-web`) and console (`medha-admin-panel`) with dynamic **runtime hostname sniffing** in their API client (`getApiBase`).
   - If accessed via `dev.medha.dev` or `admin-dev.medha.dev`, requests are routed to `api-dev.medha.dev`. If accessed via production domains (`medha.dev`, `admin.medha.dev`), they route to `api.medha.dev`. This prevents backend environment leakage when merging `dev` and `prod` git branches.
3. **Cloudflare Worker Naming & DNS Restorations**:
   - Fixed configuration name collisions in `wrangler.jsonc` across branches in `medha-web` and `medha-admin-panel`. Fast-forward merges had overwritten the Worker names.
   - Pushed correct names to respective branches: production builds to `medha-web` / `medha-admin-panel`; development builds to `medha-web-dev` / `medha-admin-panel-dev`.
   - Used the Cloudflare API token to manually re-attach Workers custom domains (`dev.medha.dev` -> `medha-web-dev`, and `medha.dev`/`www.medha.dev` -> `medha-web`), bringing both sites back online after DNS resolution errors (`NXDOMAIN`).
4. **CI Pipeline Removal**:
   - Deleted `.github/workflows/ci.yml` from `medha-api`. The code coverage `upload-artifact` step was hitting GitHub's repository artifact storage limits and blocking all PR checks. Testing has been moved locally.

## Production safety constraints

- Never expose PostgreSQL or Redis through Cloudflare DNS or a public Ingress.
- Never use the same public hostname for both the Web Worker and API.
- Keep the cloudflared catch-all `http_status:404` rule last.
- Do not click the irreversible Cloudflare dashboard tunnel migration for the
  locally managed tunnel.
- Never commit tunnel credential JSON, Cloudflare tokens, plaintext
  Kubernetes Secrets, private SSH keys, or unsealed production credentials.
- Do not let Argo create a new empty production PostgreSQL/MinIO/Redis
  volume — always verify the new StatefulSet's hostPath matches the live
  directory before deleting the old one.
- Production changes require sign-off on the downtime window before scaling
  down live prod resources.

## Useful verification commands

```bash
# Tunnel validation
ssh medha-storage 'sudo cloudflared --config /etc/cloudflared/config.yml tunnel ingress validate'

# Cluster / Argo health
ssh medha-master 'kubectl get nodes; kubectl get pods -A'
ssh medha-master 'kubectl get applications.argoproj.io -n argocd -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'

# Force an Argo re-evaluation (aggregate .status.sync.status can be stale for
# a few seconds after a manual kubectl apply or a git push - hard-refresh and
# re-check rather than trusting the first read)
ssh medha-master 'kubectl patch application medha-dev -n argocd --type=merge -p "{\"metadata\":{\"annotations\":{\"argocd.argoproj.io/refresh\":\"hard\"}}}"'

# Argo CD UI (local port-forward)
ssh -o ExitOnForwardFailure=yes -L 8081:127.0.0.1:8081 medha-master \
  'kubectl -n argocd port-forward --address 127.0.0.1 svc/argocd-server 8081:80'
# then open http://127.0.0.1:8081 (HTTP, not HTTPS - argocd-server runs --insecure)

# Repository validation (from medha-infra root)
TF_VAR_cloudflare_api_token=$(cat ~/.config/cloudflare/medha-infra-token) ./scripts/validate.sh
./scripts/validate-runtime-secrets.sh
```

## Documentation already available

- `medha-infra/PROJECT.md`
- `medha-infra/docs/domains-and-naming.md`
- `medha-infra/docs/migration.md`
- `medha-infra/docs/operations.md`
- `medha-infra/docs/secrets.md`
- `medha-infra/docs/local-development.md`
- `medha-infra/scripts/validate.sh`, `validate-runtime-secrets.sh`,
  `argocd-local-access.sh`

## Definition of done

- [x] Web prod and dev hostnames serve the correct Worker deployments.
- [x] API prod hostname serves its Kubernetes namespace; API dev likewise,
      now on the new unsuffixed resources.
- [x] Presigned URLs use `s3` and `s3-dev`.
- [x] `minio`/`minio-dev` serve port 9001 and require Access.
- [x] Admin prod and dev both require Access.
- [x] `www` returns a 308 redirect to the apex.
- [x] Old `minio-console*`, transitional dev API, and Argo DNS records are
      removed.
- [x] PostgreSQL and Redis have no public route.
- [x] `medha-infra` is the GitOps source of truth for the platform, dev, and
      prod.
- [x] Dev and prod Argo applications are both Synced/Healthy with tested
      stateful-volume adoption (web prod auto-syncs; admin prod remains manual-sync).
- [x] `validate.sh` and `validate-runtime-secrets.sh` pass; prod's live pods,
      data (Postgres tables, MinIO bucket, Redis ping), and public health
      endpoint were verified end-to-end post-cutover.
