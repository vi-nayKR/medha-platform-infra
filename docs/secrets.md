# Secrets in the public reference snapshot

All eight checked-in SealedSecrets are **publication fixtures**, not operational ciphertext. Every encrypted value is `PUBLICATION_ONLY_NOT_A_CIPHERTEXT`; metadata marks each resource with `medha.dev/publication-only: "true"`. Names, namespaces and required key contracts remain for architecture review.

Do not deploy this checkout, remove the markers to bypass checks, or copy real credentials into it. See [publication review](PUBLICATION_REVIEW.md) for historical exposure and owner actions.

| Material | Public snapshot | Operational requirement outside this repository |
| --- | --- | --- |
| API, PostgreSQL, Redis, SeaweedFS secrets | Non-deployable sentinels | Privately provision and seal for the correct environment/controller |
| JWT signing keys | No private keys supplied | Separate authorized secret provisioning; shape checks do not verify availability |
| Tunnel credentials | Illustrative path only | Host/private credential store; never commit JSON credentials |
| Sealing certificate | Historical public X.509 certificate | Obtain the current trusted certificate from the authorized private infrastructure process |
| CI/deployment credentials | Not supplied or required by publication CI | Keep out of this public reference; use explicit contracts/approvals in operational sources |
| Local configuration | Ignored local files | Development-only values; never point a development process at production tunnels |

## Offline checks

- `./scripts/validate.sh`: publication structure and reference checks. Missing optional renderer/provider tools are explicit skips.
- `./scripts/validate-runtime-secrets.sh`: deliberately fails on this public checkout. It checks non-placeholder ciphertext shape and required keys, not decryption, credential correctness, external secret resources or live readiness.

Encrypted payloads are not plaintext passwords, and public certificates are not private keys. Nevertheless, current-tree cleanup cannot recall old public commits. Do not equate a passing generic secret scan with a complete publication/ownership or personal-data review.
