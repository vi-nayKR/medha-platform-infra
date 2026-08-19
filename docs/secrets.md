# Secrets — where each kind lives

Nothing secret is stored in this repo. Map of where things actually live:

| Kind | Storage | Notes |
|------|---------|-------|
| API runtime secrets (DB/S3/JWT/OTP/Firebase/Resend/MapMyIndia…) | Bitnami **SealedSecrets** in `kubernetes/overlays/<env>/backend-sealed-secret.yaml` | Encrypted and namespace-bound; safe in git. Decrypted in-cluster only. |
| Postgres bootstrap secret | Bitnami **SealedSecret** named `postgres-secrets` in each overlay | Must contain `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB` before stateful-resource adoption. |
| SeaweedFS S3 identity config | Bitnami **SealedSecret** named `seaweedfs-secrets` in each overlay | Contains `s3-identity-config`, a JSON identity file mounted into the SeaweedFS pod at `/etc/seaweedfs/s3_identity.json` (passed via `-s3.config`). Its access/secret key values must match `s3-access-key`/`s3-secret-key` in that overlay's `backend-*-secrets`. |
| Tunnel credentials | Host-managed file on `medha-storage` | Used by the systemd-managed tunnel; never copy into Kubernetes or commit the JSON. |
| CI/CD secrets (Android `KEYSTORE_*`, `OTA_ADMIN_SECRET`) | **GitHub → repo/environment secrets** | Move into the `prod` environment on medha-android for isolation. |
| Cloudflare deploy | Cloudflare Git integration (no token in repo) | web + admin build/deploy inside Cloudflare. |
| Frontend build URLs (`VITE_API_BASE_URL`) | **Committed** `.env.development` / `.env.production` | Public URLs, not secrets — all `VITE_` vars ship to the browser. |
| Local dev secrets | `.env` (gitignored) per app | Dev credentials only. **Never put prod credentials on a dev machine.** |
| Android signing keystore | `keystore.properties` + `.jks` (gitignored) locally; GitHub secret in CI | — |

## Rotating a sealed secret (API)

Re-seal with the cluster's public certificate and commit only the updated
`backend-sealed-secret.yaml` in the matching overlay; Argo CD reconciles it.
The non-secret sealing certificate is `secrets/pub-cert.pem`.

The checked-in legacy production ciphertext still needs a
`credentials-encryption-key` entry before first production sync. Do not invent
or commit the plaintext value. Generate it through the normal secret-management
process, re-seal it for the `prod` namespace, then run
`scripts/validate-runtime-secrets.sh`.

## Guard rails in place

- **API startup guard** refuses to boot if `ENVIRONMENT` doesn't match the DB/Redis/S3
  legacy host markers. For the mirrored short service names, namespace-scoped
  DNS plus default-deny NetworkPolicies provide the hard environment boundary.
- **Frontends bake the API URL at build** — a dev bundle has no prod URL and vice versa
  (verified: prod bundles contain only `api.*`, dev bundles only `api-dev.*`).
- **Admin login** API-target field is read-only in prod builds.
