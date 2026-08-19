# Production-safe migration

The checked-in desired state is the final naming model. Apply it in phases; do
not point a hostname at a different service in one step.

## Current live status (2026-07-18)

- `api-dev`, `s3`, and `s3-dev` are routed through the existing tunnel and have
  matching Traefik Ingress rules.
- Both backend deployments generate public object URLs with their respective
  `s3` hostname. Production also has explicit production console and share URLs.
- The locally managed tunnel runs on `medha-storage`; its validated reference
  configuration is `platform/cloudflared/host-migration-config.yml`.
- `dev` still serves the development API during the compatibility window.
- `minio` and `minio-dev` still serve the S3 API during the compatibility
  window. The legacy `minio-console*` names still serve port 9001.
- Cloudflare Access for admin and console hostnames must be active before the
  `minio*` hostnames are switched to port 9001.
- The public Argo CD route is closed. Its remaining DNS record can be deleted.

1. Import existing DNS and Access resources into Terraform state. Keep the
   existing locally configured tunnel; do not click the irreversible dashboard
   migration. Add/import the proxied `www` CNAME before enabling its canonical
   redirect rule.
2. Add `api-dev`, `s3`, and `s3-dev` while current names continue serving.
   Deploy backend configuration so generated/presigned URLs use the S3 names.
3. Verify uploads, downloads, CORS and presigned URLs in both environments.
4. Create Access applications for `admin`, `admin-dev`, `minio`, and
   `minio-dev` before exposing their routes. Use separate Pages projects for
   prod and dev admin builds; a Pages custom domain targets a project's
   production deployment, not an arbitrary preview branch.
5. Move console traffic to `minio` and `minio-dev`. Keep old
   `minio-console` names only while logs show callers; then remove both DNS and
   tunnel rules.
6. Move every development API client to `api-dev`. Only after logs show no API
   traffic on `dev`, delete the transitional tunnel rule and attach `dev` to the
   web Worker.
7. Remove the public Argo CD DNS/tunnel/Ingress route. Use the SSH workflow in
   `docs/operations.md`.
8. Before Argo manages Postgres/Redis/MinIO, adopt the existing PVCs or complete
   a tested backup/restore. Create the required `postgres-secrets` SealedSecret
   (`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`). Never allow Argo to
   create a new empty production database accidentally.
9. Re-seal the production backend secret with a strong
   `credentials-encryption-key`. The retained legacy production SealedSecret
   does not contain that key, and the API intentionally refuses to start in
   production without it.
10. Run `./scripts/validate-runtime-secrets.sh`, bootstrap the Argo applications,
    sync dev, run acceptance checks, then manually approve and sync prod. Keep
    production auto-sync disabled until the migration has proved stable.
