# Medha infrastructure architecture

> **Historical Kubernetes reference.** The diagram and policies below describe retained manifests, not verified current runtime. A later two-node Docker design is documented in [two-node-docker.md](docs/two-node-docker.md). This public checkout has non-deployable secret fixtures; see [publication review](docs/PUBLICATION_REVIEW.md). Validation is offline and does not gate an external live controller automatically.

**Scope.** This document describes the infrastructure *as built* — cluster topology, manifest
layout, traffic path, and delivery pipeline. For *why* it's designed this way (goals, trade-offs,
quality attributes, failure modes), see [`system_design.md`](./system_design.md). For conventions,
guardrails, and commands, see [`AGENTS.md`](./AGENTS.md).

`medha-infra` is a GitOps repository, not an application. It declares where
Medha's application artifacts run (a single self-hosted Kubernetes cluster)
and which public hostnames may reach them. Application repos (`medha-api`,
`medha-web`, `medha-admin-panel`, `medha-android`) build images; this repo is
the only thing with permission to say "run this image, here, reachable at
this hostname."

## System diagram

```
                              Cloudflare edge
        ┌──────────────────────────────────────────────────────┐
        │  DNS + Access (Zero Trust) + tunnel routing, via      │
        │  terraform/cloudflare                                 │
        └───────────────┬─────────────────────┬─────────────────┘
                         │ tunnel (outbound)
                         ▼
        ┌─────────────────────────┐
        │ cloudflared tunnel      │
        │ outbound edge bridge    │
        └───────────┬─────────────┘
                     │ HTTP by Host header
                     ▼
        ┌─────────────────────────┐
        │ Traefik (k3s built-in)  │
        │ + security-headers      │
        │   middleware            │
        │ platform/traefik        │
        └───────────┬─────────────┘
                     │ routes by namespace-scoped Ingress
         ┌───────────┴───────────┐
         ▼                       ▼
 ┌───────────────┐       ┌───────────────┐
 │ namespace: dev│       │ namespace:    │
 │               │       │ prod          │
 │ backend       │       │ backend       │
 │ web + admin   │       │ web + admin   │
 │ postgres      │       │ postgres      │
 │ redis         │       │ redis         │
 │ seaweedfs     │       │ seaweedfs     │
 └───────────────┘       └───────────────┘
     both rendered from kubernetes/base via
     kubernetes/overlays/{dev,prod}, reconciled
     continuously by Argo CD (argocd/medha-{dev,prod}.yaml)
```

Argo CD itself (`argocd/medha-platform.yaml`) reconciles `platform/`
(Traefik middleware and the local image registry) into the `kube-system`
namespace. The Cloudflare tunnel is intentionally host-managed by systemd on
`medha-storage`; `platform/cloudflared/host-migration-config.yml` is retained
as a reference for that service and is not a Kubernetes workload. Argo CD has
no public hostname — see [Operator access](#operator-access).

## Repository layout as source of truth

| Path | Owns |
|---|---|
| `kubernetes/base` | The one resource shape shared by both environments: `backend` Deployment, `postgres`/`redis`/`seaweedfs` StatefulSets, and default-deny `NetworkPolicy` set. |
| `kubernetes/overlays/{dev,prod}` | Backend/data namespace, image tag, ConfigMap values, hostPath data directories, and namespace-bound SealedSecrets. |
| `kubernetes/apps/{medha-web,medha-admin-panel}` | Nginx deployments serving built frontend assets, with dev/prod overlays. |
| `platform` | Cluster-wide, not namespace-bound: Traefik security-headers middleware and the local Docker registry. The host-managed tunnel's reference configuration is kept separately under `platform/cloudflared/`. |
| `terraform/cloudflare` | Cloudflare tunnel DNS records and Zero Trust Access policy for public/operator hostnames. |
| `argocd` | Seven Applications: backend dev/prod, web dev/prod, admin dev/prod, and platform. |
| `scripts/validate.sh` | Offline consistency checks, plus Kustomize/Terraform validation in CI. |
| `scripts/validate-runtime-secrets.sh` | Fail-closed gate: refuses a cluster sync if a required SealedSecret key is missing. |

## Environments

`dev` and `prod` are two namespaces in **one cluster**, rendered from the
same Kustomize base. They differ only in overlay values — image tag, replica
policy, storage paths, and encrypted secret material. Runtime environment
selection is explicit (`ENVIRONMENT` env var) for the Kubernetes backend API;
branch or hostname sniffing inside the API container is prohibited. For static
frontend client bundles (web and admin panel), dynamic runtime hostname sniffing
is used to select the matching API backend to prevent build-time environment leakage
across Git merges.

Both namespaces use identical in-cluster service names: `backend`,
`postgres`, `redis`, `seaweedfs`. Kubernetes DNS resolves those names only
within a pod's own namespace, so a `dev` pod cannot resolve `prod`'s
`postgres` by short name — namespace isolation is the environment boundary,
reinforced by NetworkPolicy (below).

## Workload shape (per namespace)

- **backend** — Deployment. An `initContainer` runs `./medha-api -migrate`
  before the main container starts. Reads `DATABASE_URL`, S3 keys, admin
  credentials, and third-party API keys (Resend, MessageCentral, MapMyIndia)
  from a `backend-{env}-secrets` SealedSecret; non-secret config (ports, log
  level, public URLs, JWT expiry) from a generated `backend-config`
  ConfigMap. JWT signing keys are mounted from a `jwt-keys` Secret. `dev`
  runs 1 replica (`Recreate` strategy), pinned via `nodeSelector` + a
  toleration to the control-plane node — spare capacity, and a brief
  restart window on deploy is acceptable. `prod` runs 2 replicas
  (`RollingUpdate`, `maxUnavailable: 0`) with node-affinity to
  `workload-type: worker|storage` — off the control plane, zero-downtime
  deploys.
- **postgres** — StatefulSet (`postgis/postgis:17-3.4-alpine`), 1 replica,
  `hostPath` volume so Argo adopts the existing data directory in place
  rather than provisioning an empty one (`/mnt/ssd/postgres-{dev,prod}`).
- **redis** — StatefulSet (`redis:7.4-alpine`, AOF + periodic RDB save), same
  hostPath-adoption pattern (`/mnt/ssd/redis-{dev,prod}`).
- **seaweedfs** — StatefulSet (`chrislusf/seaweedfs`, all-in-one `weed server -s3`
  mode), S3 API on 8333, hostPath at `/mnt/hdd/seaweedfs-{dev,prod}`. S3 identity
  (access/secret key) comes from a `seaweedfs-secrets` SealedSecret mounted as a
  file, not env vars — SeaweedFS has no MinIO-style `ROOT_USER`/`ROOT_PASSWORD`.
- **backup CronJob** (`prod` only) — nightly at 02:00, `pg_dump`s Postgres and
  tars the SeaweedFS data directory to `/mnt/hdd/backups`.

All data services are pinned via `nodeSelector` (`workload-type:
worker`/`storage`) to nodes with the matching disk attached — this is a
single physical cluster, not cloud-elastic storage.

## Networking and traffic path

1. **Cloudflare edge** terminates public TLS and, for `api*`/`s3*`
   hostnames, forwards over an outbound-only Cloudflare Tunnel — no inbound
   port is opened on the cluster's firewall.
2. **cloudflared** is the host-managed tunnel client on `medha-storage`. It
   has no Kubernetes Deployment or inbound listener; it dials out to
   Cloudflare and forwards traffic to Traefik on the host.
3. **Traefik**, k3s's built-in ingress controller, receives tunnel traffic
   and routes purely by `Host` header to the matching namespace's `Ingress`
   (`kubernetes/overlays/{dev,prod}/ingress.yaml`). A shared
   `medha-security-headers` middleware (`platform/traefik`) applies to every
   route.
4. Each namespace's `Ingress` sends `api[-dev]` to `backend:8080`,
   `s3[-dev]` to `seaweedfs:8333`.
5. **NetworkPolicy**, applied per namespace (`kubernetes/base/network-policies.yaml`):
   - `default-deny` — every pod denies all ingress/egress unless explicitly
     allowed.
   - `allow-dns` — every pod may reach kube-dns.
   - `backend-egress` — backend may reach `postgres:5432`, `redis:6379`,
     `seaweedfs:8333`, and the public internet on 443 (RFC1918 ranges excluded,
     so no cross-node-network egress).
   - `backend-ingress-from-traefik` — only Traefik (in `kube-system`) may
     reach backend's 8080.
   - `data-ingress` — postgres/redis/seaweedfs accept traffic only from backend,
     plus kube-system on 8333 for the public S3 API ingress path.
   - `seaweedfs-egress` — seaweedfs itself (not just backend) may reach the public
     internet on 443, mirroring `backend-egress`'s RFC1918-excluded shape.

   Net effect: `postgres` and `redis` are unreachable from anywhere but their
   own namespace's `backend`; the only two ways into a namespace's data
   plane are the backend pod and the Traefik-routed public S3 API.

- **web** and **admin** are served by Nginx Deployments declared under `kubernetes/apps/`, with
  separate Argo Applications for dev and prod. Their built static assets live on node `hostPath`
  directories; Cloudflare remains the public edge and Access gate.
- **Argo CD** and raw **Postgres/Redis** have no public hostname by design —
  see `docs/domains-and-naming.md` for the full hostname table.

## Delivery pipeline

1. An application commit in `medha-api` (etc.) passes tests and builds an
   immutable image, pushed to the in-cluster local registry
   (`platform/registry`, `local-registry:5000`).
2. The API repo's CI workflow updates *only* the image tag in the matching
   `medha-infra` overlay (`kubernetes/overlays/{dev,prod}/kustomization.yaml`)
   using an `INFRA_REPO_TOKEN` scoped per GitHub environment. Production
   requires the GitHub `prod` environment's reviewer approval gate.
3. **Argo CD** watches this repo's `main` branch. Backend dev/prod, web dev/prod, and platform
   auto-sync with prune/self-heal; admin prod remains manual-sync. The namespace
   migration is complete; `docs/HANDOFF.md` records the cutover history.
4. Cloudflare/Traefik pick up newly routable services automatically since
   routing is Host-header based, not tied to pod IPs.

## Secrets

Nothing secret is stored in plaintext in this repo. Summary (full table in
`docs/secrets.md`):

- **API runtime secrets** (DB URL, S3 keys, JWT signing key path targets,
  admin creds, Resend/MessageCentral/MapMyIndia keys) — Bitnami
  **SealedSecrets**, namespace-bound, committed as ciphertext
  (`backend-sealed-secret.yaml` per overlay). Only the cluster's private key
  can decrypt them; `secrets/pub-cert.pem` (public, safe to commit) is what
  you seal *against*.
- **Postgres bootstrap secret** — a `postgres-secrets` SealedSecret per
  overlay, must exist before Argo is allowed to adopt the StatefulSet.
- **SeaweedFS S3 identity config** — a `seaweedfs-secrets` SealedSecret per
  overlay, mounted as a file into the SeaweedFS pod. Its credential values
  must match the `s3-access-key`/`s3-secret-key` sealed into that overlay's
  `backend-*-secrets`.
- **Tunnel credentials** — a plain (unsealed) Kubernetes `Secret` created
  out-of-band, never committed.
- **CI/CD secrets** (Android keystore, OTA admin secret) — GitHub
  repo/environment secrets, not this repo.
- **Frontend build URLs** — intentionally committed in plaintext
  (`.env.development`/`.env.production`); they're public by construction
  since `VITE_` vars ship to the browser.

Guard rails: the API refuses to boot if `ENVIRONMENT` doesn't match its
DB/Redis/S3 host markers; frontend bundles are built once per environment
so a prod bundle physically cannot contain a dev API URL (and vice versa);
the admin panel's API-target field is read-only in prod builds.

## Operator access

Argo CD has no public route. Access is SSH-only:
`./scripts/argocd-local-access.sh` (or the equivalent
`ssh -L 8081:127.0.0.1:8081 medha-master 'kubectl -n argocd port-forward ...'`)
opens a loopback-only tunnel to the Argo CD UI. This is deliberate — one less
authenticated surface exposed to the internet, since SSH + Cloudflare Access
already gate operator entry points (`ssh-master`/`ssh-worker`/`ssh-storage`).

## Validate before every change

- `./scripts/validate.sh` — publication fixtures, YAML/reference contracts and script tests. Kustomize/provider checks run only when their tools and initialization are available; skips are explicit.
- `./scripts/validate-runtime-secrets.sh` — ciphertext-shape check that intentionally rejects this public checkout. Passing it elsewhere would not prove decryption or runtime readiness, and no external controller is automatically gated by this script.

## Further reading

- `docs/domains-and-naming.md` — full hostname-to-service table.
- `docs/migration.md` — historical production-safe cutover plan; the current desired state is the
  manifests and Argo Application files.
- `docs/secrets.md` — secret storage locations and the re-sealing procedure.
- `docs/operations.md` — Argo CD access and validation commands.
- `docs/local-development.md` — pointing each application repo at `dev`.
