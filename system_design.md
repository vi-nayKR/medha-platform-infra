# Medha infrastructure — System Design

**Scope.** This document captures *why* the infrastructure is shaped the way it is: goals,
requirements, the key design decisions and their trade-offs, the failure modes the design guards
against, and the quality attributes it targets. For the *as-built* cluster topology, manifest
layout, and traffic path, see [`architecture.md`](./architecture.md). For conventions, guardrails,
and commands, see [`AGENTS.md`](./AGENTS.md).

---

## 1. Goals & non-goals

**Current state (2026-07-22):** the platform is deployed end to end in dev and production. Both
backend overlays pin `db5827f`; backend and web production now auto-sync with prune/self-heal.
Admin production remains manual-sync, and the only known active product polish is in
`medha-ios`.

**Goals**
- Run the whole Medha platform on **one self-hosted cluster** cheaply, with clean `dev`/`prod`
  isolation and no cloud bill that scales with idle capacity.
- Make **git the only control plane**: every change to what runs and how it's reachable is a
  reviewed commit that Argo CD reconciles — no snowflake `kubectl edit`.
- Keep `dev` and `prod` **the same shape**, differing only in a small overlay, so a change tested in
  dev behaves the same in prod.
- Never store a secret in plaintext, and never open an inbound port on the cluster.

**Non-goals**
- Not multi-region, not multi-cluster, not autoscaling. A single physical cluster with pinned
  hostPath storage is the deliberate ceiling (see §6).
- Not a platform-as-a-service for arbitrary apps — it hosts Medha's known workloads only.
- Not the home of application logic or images — app repos build those; this repo only *places* them.

## 2. Requirements

| Type | Requirement |
| --- | --- |
| Delivery | Backend dev/prod, web dev/prod and platform reconcile automatically; production admin remains approval-gated manual sync. |
| Isolation | `dev` and `prod` fully isolated by namespace + NetworkPolicy; neither can reach the other's data plane. |
| Security | No inbound ports (outbound tunnel only); no plaintext secrets in git; data services never publicly routable. |
| Reproducibility | The live cluster is derivable from this repo — drift is reverted (`selfHeal`) or caught by validation. |
| Safety | Application images are pinned to commit SHAs; production sync policy is explicit per workload. |

## 3. Key design decisions & trade-offs

| Decision | Rationale | Trade-off / ceiling |
| --- | --- | --- |
| **GitOps via Argo CD** (this repo = desired state) | One auditable control plane; drift auto-reverts on automated Applications | An agent almost never holds live credentials — everything goes through a PR, slower than `kubectl` |
| **One cluster, two namespaces** (`dev`/`prod`) | Cheapest isolation that's still real; identical shape | A cluster-wide outage takes both environments; no blast-radius separation between envs |
| **Kustomize base + thin overlays** | `dev`/`prod` differ only in overlay values, so parity is structural | Every genuine per-env need must be expressed as an overlay patch, not a base fork |
| **Cloudflare Tunnel (outbound only)** | No inbound firewall port; TLS terminated at the edge | Hard dependency on Cloudflare + the tunnel client being up; adds a hop |
| **SealedSecrets** (ciphertext in git) | Secrets are versioned and reviewable without being readable | Must re-seal on key rotation; only the in-cluster controller can decrypt |
| **hostPath storage pinned by `nodeSelector`** | Uses the real disks on real nodes; Argo adopts existing data dirs | Not cloud-elastic; a node loss is a data-availability event — this is the main ceiling |
| **Per-workload prod sync + pinned image SHAs** | Backend and web prod auto-reconcile; admin prod retains a human gate; `latest` cannot ship accidentally | Policy must remain explicit in each Application manifest |
| **Explicit `ENVIRONMENT` for backend, hostname-sniffing for frontends** | Backend config is unambiguous; static bundles can't leak a cross-env URL over a merge | Two different mechanisms to keep straight — documented in `AGENTS.md` §5 |
| **NetworkPolicy default-deny** | Postgres/Redis reachable only from their namespace's backend | Every new egress/ingress path must be explicitly allowed or it silently fails |

## 4. Traffic & delivery flows

**Public request → backend**
```
client → Cloudflare edge (TLS terminate, WAF)
       → Cloudflare Tunnel (outbound-only) → cloudflared (host: medha-storage)
       → Traefik (routes by Host header)
       → namespace Ingress → backend:8080 / seaweedfs:8333
```

**App release → running pod** (image tag is the only thing this repo receives)
```
medha-api CI → build immutable image → push to in-cluster registry (local-registry:5000)
            → bump image SHA in kubernetes/overlays/<env>/kustomization.yaml (INFRA_REPO_TOKEN)
Argo CD watches main:
  backend dev/prod + platform → auto-sync (prune + selfHeal)
  web dev/prod                → auto-sync (prune + selfHeal)
  admin prod                  → reviewer approval, then manual sync
backend initContainer runs ./medha-api -migrate before the main container starts
```

## 5. Security model

- **No inbound surface.** The cluster opens no port; all public traffic arrives via the outbound
  Cloudflare Tunnel. Argo CD and raw Postgres/Redis have **no public hostname** — Argo is reached
  only through an SSH loopback tunnel (`scripts/argocd-local-access.sh`).
- **Secrets never in plaintext.** API/DB/JWT/OTP/third-party keys are SealedSecrets (namespace-bound
  ciphertext); the host-managed tunnel credentials stay on `medha-storage` and are never committed;
  CI secrets live in GitHub, not here. `secrets/pub-cert.pem` (public) is what you seal against.
  `validate-runtime-secrets.sh` fails closed if a required key is missing from the ciphertext.
- **Namespace isolation as the security boundary.** Default-deny NetworkPolicy means a `dev` pod
  can't resolve or reach `prod`'s data plane; only Traefik may reach a backend, and only a backend
  (plus the public S3 API path) may reach the data services.
- **Least public exposure.** Web/admin static assets are Nginx-hosted in the cluster and reached
  through Cloudflare; admin hostnames sit behind Cloudflare Access (Terraform-owned). Postgres and
  Redis are never given a DNS record or Ingress.

## 6. Reliability, scalability & known ceilings

- **Scaling:** `prod` backend runs 2 replicas (RollingUpdate, `maxUnavailable: 0`) for zero-downtime
  deploys; `dev` runs 1 (Recreate). Stateless backend scales horizontally within the node budget.
  **The hard ceiling is single-node hostPath storage** — Postgres/Redis/SeaweedFS are 1-replica
  StatefulSets pinned to specific disks. `// ceiling:` growth beyond one storage node needs real
  volume provisioning or a managed datastore, not just more replicas.
- **Reliability:** Argo `selfHeal` reverts drift on backend dev/prod, web dev/prod and platform;
  manual production admin changes still reconcile only when explicitly synced. A live-only fix remains invisible
  to git (see `docs/HANDOFF.md`). A nightly `prod` CronJob backs up Postgres and SeaweedFS.
- **Failure modes:**
  - Cloudflare tunnel down → all public API/S3 traffic fails (edge can't reach the cluster); the
    cluster itself keeps running.
  - A storage node lost → that namespace's Postgres/Redis/SeaweedFS is unavailable until the node/disk
    returns; no automatic failover (single-node ceiling above).
  - SealedSecret missing a required key → `validate-runtime-secrets.sh` blocks the sync rather than
    booting a half-configured backend.
  - `latest`/unpinned image or a hostname mismatch → caught by `validate.sh` /
    `validate-env-contract.sh` before merge, not in production.

## 7. Change safety & validation

The design assumes changes are proposed by people (and agents) without live cluster access, so
**offline validation is the primary guard**: `validate.sh` (renders both overlays + validates
Terraform), `validate-runtime-secrets.sh` (fail-closed secret gate), and `validate-env-contract.sh`
(hostname/env agreement across sibling repos). Production policy is workload-specific: backend is
automated/self-healing, web is automated/self-healing, while admin retains manual approval. The shared safety nets are
validation, pinned revisions, review, and explicit Argo policy.

## 8. Roadmap / open questions

- Move off single-node hostPath for the data tier (real volume provisioning or managed DB) to lift
  the storage ceiling and enable failover.
- Add cluster-level observability (metrics/alerting) so a tunnel or node failure pages someone rather
  than being noticed by a failing `curl`.
- Offsite/rotated backups beyond the nightly on-cluster tar.
