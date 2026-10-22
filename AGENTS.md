# AGENTS.md — Medha Infra

> **Public snapshot boundary (2026-10-22):** This is an offline reference derivative, not an authorized deployment source. All SealedSecrets contain explicit non-deployable publication sentinels. `scripts/validate.sh` checks publication structure; `scripts/validate-runtime-secrets.sh` must reject this checkout. Do not apply, seal against the historical certificate, sync, migrate, or contact any live host. The operational instructions below are historical reference, not permission. See `docs/PUBLICATION_REVIEW.md`.

> **Historical runtime note (2026-08-20):** a later two-node Docker design is recorded
> in [`docs/two-node-docker.md`](./docs/two-node-docker.md), separating edge/object storage from
> APIs, PostgreSQL and Redis. This public snapshot does not verify today's live runtime.
> The Kubernetes/Argo CD material below is historical configuration, not an authorized
> deployment workflow.

> **Cross-tool agent guide.** This file is the single source of truth for AI coding agents in
> this repository, written to the open [AGENTS.md](https://agents.md) convention.
>
> - **OpenAI Codex** and **Google Gemini** (Gemini CLI / Antigravity / Jules) read `AGENTS.md`
>   from the repo root automatically.
> - **Anthropic Claude Code** reads `CLAUDE.md`, a thin pointer back to this file.
> - **Put guidance here — update one file, not several.**
>
> Deep dives: [`architecture.md`](./architecture.md) (as-built structure) and
> [`system_design.md`](./system_design.md) (design decisions, quality attributes).

---

## 1. What this is

`medha-infra` is the **GitOps** repository for the Medha platform — it is not an application and
produces no build artifact of its own. It declares *where* application artifacts run (a single
self-hosted Kubernetes cluster) and *which public hostnames* may reach them. Application repos
(`medha-api`, `medha-web`, `medha-admin-panel`, `medha-android`) build images or static bundles;
this repo is the only thing with permission to say "run this image, here, reachable at this
hostname." Argo CD continuously reconciles this repo's `main` branch into the live cluster — a
merged commit is reconciled automatically for backend `dev`/`prod` and web `dev`/`prod`; admin
production remains manual-sync (§7).

**Delivery status (2026-07-22):** the Medha platform is complete end to end in both namespaces.
The API overlays pin the same deployed `db5827f` revision, the production backend Application now
has automated prune/self-heal, and web/admin have separate Argo Applications. Remaining active work
is a small improvement in `medha-ios`, not an infrastructure cutover.

If unsure whether a change belongs here or in an app repo: app repos own *what runs* (code,
image); this repo owns *where it runs and how it's reachable* (namespace, replicas, image tag,
hostname, secret ciphertext).

## 2. Prerequisites & tools

| Tool | Used for | Notes |
| --- | --- | --- |
| `kubectl` | Rendering/validating manifests (`kubectl kustomize ...`) | No standalone `kustomize` binary needed |
| `terraform` >= 1.8.0 | `terraform/cloudflare` (provider `cloudflare/cloudflare ~> 5.17`) | Needs `TF_VAR_cloudflare_api_token` |
| `kubeseal` | Authoring/rotating a SealedSecret | Seals **against** `secrets/pub-cert.pem`; only the in-cluster controller can decrypt |
| `argocd` CLI / Argo CD UI | Inspecting sync/health, manual prod sync | No public hostname — reach it via `./scripts/argocd-local-access.sh` (SSH tunnel) |
| `ruby`, `rg` (ripgrep) | Internals of `scripts/validate*.sh` | Assumed present in CI |
| `ssh` + `cloudflared` | Cluster/Argo/registry-node access for a human operator | See `docs/HANDOFF.md` for the `medha-master` / `medha-worker` / `medha-storage` SSH config |

An agent working in this repo almost never holds live cluster or Cloudflare credentials — treat
the cluster as reachable only through git. Don't assume you can `kubectl apply`, `terraform
apply`, or `argocd sync` from an agent session unless the user has explicitly handed you that
access.

## 3. Common commands

| Task | Command |
| --- | --- |
| Full offline validation (CI-equivalent) | `./scripts/validate.sh` |
| Runtime-secret readiness gate (before any sync) | `./scripts/validate-runtime-secrets.sh` |
| Cross-repo hostname/env contract (needs sibling repos checked out) | `./scripts/validate-env-contract.sh` |
| Render a namespace's manifests | `kubectl kustomize kubernetes/overlays/dev` (or `prod`) |
| Render cluster-wide platform manifests | `kubectl kustomize platform` |
| Terraform fmt/validate | `terraform -chdir=terraform/cloudflare fmt -check && terraform -chdir=terraform/cloudflare validate` |
| Terraform plan | `cd terraform/cloudflare && TF_VAR_cloudflare_api_token=$(cat ~/.config/cloudflare/medha-infra-token) terraform plan` |
| Bootstrap/update Argo CD Applications | `kubectl apply -k argocd` |
| Reach the Argo CD UI | `./scripts/argocd-local-access.sh` → `http://127.0.0.1:8081` |
| Seal a new/updated secret value | `kubeseal --cert secrets/pub-cert.pem --format yaml < secret.yaml > kubernetes/overlays/<env>/<name>-sealed-secret.yaml` |
| Scaffold a local `.env` for an app repo | `./scripts/sync-env.sh <api\|web\|admin\|android>` |
| Migrate object data from MinIO to SeaweedFS (during the cutover window only) | `OLD_MINIO_ACCESS_KEY=... OLD_MINIO_SECRET_KEY=... ./scripts/migrate-storage-to-seaweedfs.sh <dev\|prod>` |

Run `./scripts/validate.sh` before proposing any Kubernetes or Terraform change — it's the same
check CI runs, and it's cheap.

## 4. Repository layout

```
kubernetes/base/        shared resource shape: backend Deployment, postgres/redis/seaweedfs
                         StatefulSets, default-deny NetworkPolicy set
kubernetes/overlays/
  dev/                   namespace=dev, image tag, ConfigMap values, hostPath paths, dev SealedSecrets
  prod/                  namespace=prod, same, plus the nightly backup CronJob
platform/                cluster-wide, not namespace-bound: Traefik middleware and local registry;
                         the host-managed tunnel has a reference config under platform/cloudflared/
terraform/cloudflare/    Tunnel DNS records and Zero Trust Access policy
argocd/                  the 3 Application objects that reconcile everything above
scripts/                 validate.sh, validate-runtime-secrets.sh, validate-env-contract.sh,
                         sync-env.sh, argocd-local-access.sh / .ps1
docs/                    domains-and-naming, migration, operations, secrets, local-development, HANDOFF
secrets/pub-cert.pem     public sealing cert — safe to commit; seal new secrets against it
```

Full description of what each path owns:
[`architecture.md`](./architecture.md#repository-layout-as-source-of-truth).

## 5. Conventions

- **Git is the only way to change the cluster.** Never `kubectl edit`/`apply`/`delete` a live
  resource as *the* fix — change the manifest, commit, push, let Argo CD reconcile. Backend `dev`
  and `prod`, plus `platform`, have `selfHeal: true` and will silently revert a manual edit. The
  production web/admin Applications are still manual-sync. A live-only fix is invisible to git and
  gets wiped on the next sync (this has already happened once — see `docs/HANDOFF.md`).
- **Overlays are the only place `dev` and `prod` differ.** `kubernetes/base` must stay identical
  resource *shape* for both. A genuine per-environment need is a patch in
  `kubernetes/overlays/<env>/`, not a fork of the base.
- **Secrets are SealedSecrets or they don't go in git.** No plaintext Kubernetes `Secret`, API
  key, token, or credential is ever committed — see §6.
- **Both namespaces use identical short service names** (`backend`, `postgres`, `redis`,
  `seaweedfs`) — no environment suffixes on resource names. Namespace-scoped DNS is the isolation
  boundary; don't reintroduce `-dev`/`-prod`-suffixed resource names.
- **Backend environment selection is explicit**, via the `ENVIRONMENT` ConfigMap value — never
  branch- or hostname-sniffing inside the API. Frontend clients (web, admin panel) are the
  opposite on purpose: they use *runtime* hostname sniffing to pick an API target, because their
  bundles are static and must not leak a dev/prod URL across a git merge.
- **Image tags are pinned to a commit SHA** in each overlay's `kustomization.yaml` `images:`
  block — never `newTag: latest`. A `latest` tag has already nearly shipped an unvalidated build
  during the prod cutover.
- **Production policy is workload-specific.** `argocd/medha-prod.yaml` and
  `medha-web-prod.yaml` auto-sync the backend and web after their GitOps revisions are reviewed;
  `medha-admin-panel-prod.yaml` intentionally remains manual. Do not change the admin policy
  without an explicit decision.

## 6. Secrets

| Kind | Storage |
| --- | --- |
| API runtime secrets (DB/S3/JWT/OTP/Resend/MapMyIndia…) | SealedSecret, `kubernetes/overlays/<env>/backend-sealed-secret.yaml` |
| Postgres bootstrap credentials | SealedSecret `postgres-secrets`, one per overlay |
| SeaweedFS S3 identity config | SealedSecret `seaweedfs-secrets`, one per overlay — mounted as a file, not env vars |
| Cloudflare Tunnel credentials | Host-managed file on `medha-storage` — never committed |
| CI/CD secrets (Android keystore, OTA admin secret) | GitHub repo/environment secrets, not this repo |
| Frontend build URLs (`VITE_API_BASE_URL`) | Committed plaintext — public by construction, not a secret |

Full table and the re-sealing procedure: [`docs/secrets.md`](./docs/secrets.md). Always run
`./scripts/validate-runtime-secrets.sh` after touching a SealedSecret — it fails closed if a
required key is missing from the ciphertext.

## 7. Change workflow

1. Edit `kubernetes/base` (shared shape) or a specific `kubernetes/overlays/<env>` (per-env
   value) — not both for what should be one concept.
2. `./scripts/validate.sh`; also run `validate-runtime-secrets.sh` if you touched a SealedSecret,
   and `validate-env-contract.sh` if you touched a hostname.
3. Open a PR into `main`. There's no separate long-lived dev/prod branch here — the environment
   split is namespaces + overlays, not branches.
4. On merge, Argo CD's backend, web, and platform Applications auto-sync
   (`automated: {prune: true, selfHeal: true}`). Production admin still needs an explicit sync
   after review.
5. Confirm: `kubectl get applications -n argocd` shows `Synced`/`Healthy`, and the real hostname
   (e.g. `curl https://api[-dev].medha.dev/health`) responds through the actual
   Cloudflare → Traefik → backend path — not just that Argo reports success.

## 8. Agent guardrails

**Do**
- Put every credential through `kubeseal` against `secrets/pub-cert.pem`; treat any other secret
  representation in a diff as a bug to flag, not commit.
- Keep `kubernetes/base` environment-agnostic; put the difference in the overlay patch.
- Pin new or updated image tags to a real commit SHA.
- Update `docs/domains-and-naming.md` together with Terraform, the Ingress, and the cloudflared
  ConfigMap when a hostname changes — they must agree or Traefik/Cloudflare will silently 404.
- Verify a StatefulSet's `hostPath` matches the environment's real data directory before letting
  Argo adopt it — a fresh empty path means Argo will happily initialize an empty database.

**Don't**
- Don't remove backend or web prod auto-sync, or add auto-sync to production admin, without an
  explicit policy decision.
- Don't commit tunnel credential JSON, Cloudflare API tokens, `terraform.tfvars`, or any
  unsealed Kubernetes `Secret`.
- Don't give PostgreSQL or Redis a public hostname, Ingress rule, or Cloudflare DNS record.
- Don't treat `kubectl apply` against the live cluster as a substitute for a git change.
- Don't create Cloudflare Access policies/applications by hand — they're Terraform-owned; import
  existing resources rather than creating duplicates.
