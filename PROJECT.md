# Medha infrastructure project

## Active runtime

The live runtime is a two-node, systemd-managed Docker deployment. Storage (`10.0.0.20`) owns
Cloudflared, Nginx, SeaweedFS and backups; worker (`10.0.0.10`) owns both APIs, PostgreSQL and
Redis. See `docs/two-node-docker.md`. The Kubernetes definitions below are retained as historical
desired-state material and are not applied to the current hosts.

## Environments

`dev` and `prod` are separate Kubernetes namespaces rendered from one Kustomize
base. Only overlay values, image tags, replica policy, storage and encrypted
secret material differ. Runtime environment selection is explicit for the backend;
branch or hostname sniffing inside the API application is prohibited. For static
frontend bundles, dynamic runtime hostname sniffing is used to select the API backend.

## Delivery

1. An application commit passes tests and builds an immutable image.
2. The API workflow updates only the matching overlay image tag in this repo.
3. Argo CD detects that Git commit and reconciles the matching namespace.
4. Cloudflared sends allowed public hostnames to Traefik; Traefik selects the
   namespace-specific Ingress by `Host`.
5. NetworkPolicies allow backend-to-data traffic and block cross-namespace data
   access by default.

Production image changes require the GitHub `prod` environment approval. Argo
CD self-heals drift, and production admin/console endpoints require Cloudflare
Access authentication.

See `docs/domains-and-naming.md`, `docs/migration.md`, and `docs/secrets.md`.
