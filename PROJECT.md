# Medha infrastructure reference

## Public snapshot boundary

This repository is an offline portfolio/reference derivative, not the private operational source. All SealedSecrets contain non-deployable publication sentinels. No claim about current live health follows from the files here. See [publication review](docs/PUBLICATION_REVIEW.md).

## Documented later design

The dated two-node Docker runbook separates storage/edge and worker/data roles. It records an intended migration and rollback procedure, not independently verified current state. Historical SSH/cutover procedures must not be run from this checkout.

## Historical Kubernetes design

The Kubernetes examples retain dev/prod overlays from one shared base, namespace isolation, image references, and workload-specific Argo CD policies. These are preserved for architecture review, not a live reconciliation target. Ordinary Argo sync/self-heal is not an automatic canary/rollback controller.

## Offline checks

Run `./scripts/validate.sh`. Publication fixtures should pass structural checks; `./scripts/validate-runtime-secrets.sh` must reject them. Optional missing tools are reported as skips. No publication check applies infrastructure or verifies deployment readiness.
