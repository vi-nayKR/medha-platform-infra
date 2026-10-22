# Public infrastructure publication review

Review date: 2026-10-22. Scope: `vi-nayKR/medha-platform-infra`, not private infrastructure or running hosts.

## This checkout is intentionally not deployable

Every SealedSecret under `kubernetes/overlays/{dev,prod}` now has:

- Metadata annotation `medha.dev/publication-only: "true"`.
- The literal sentinel `PUBLICATION_ONLY_NOT_A_CIPHERTEXT` for every encrypted payload.
- Its resource name, namespace, template metadata and key contract preserved.

The sentinel is deliberately not plausible ciphertext. Do not apply or reconcile this repository. Deployment policy examples in Argo CD are preserved unchanged: backend/web production automatic sync, production admin manual sync. Preserving a policy example is not permission to connect the snapshot to a controller.

The backend/Redis/SeaweedFS files already contained placeholder-like values. The two PostgreSQL files still retained ciphertext-shaped payloads; those are now replaced too. Retained ciphertext is not a plaintext credential disclosure, and decryption/authenticity was not tested. It is still unnecessary environment-specific material in a public portfolio copy.

## Other changes

- Removed the real tunnel identifier default from Terraform; an authorized operator must supply an identifier. The migration-config example uses a conspicuous fictional UUID and matching illustrative credential path.
- Parameterized the historical cutover script's SSH target, identity and known-hosts paths. Batch authentication and strict host-key checking remain required. No SSH command or live cutover was executed.
- Kept `secrets/pub-cert.pem` as a historical **public** X.509 artifact. It is not a private key and not an approved current sealing target. Authorized operators obtain the current certificate from their private infrastructure process.
- Corrected the README's automatic-canary/rollback claim. The retained manifests show ordinary rolling updates and Argo reconciliation, not a canary controller. The Docker runbook is a later dated design; this checkout does not verify today's topology or historical success.
- Separated publication validation from ciphertext-shape preflight, added unit tests and wired offline publication checks into a read-only hosted-runner workflow.
- Fixed Docker-script syntax validation to parse every script separately. `bash -n file1 file2` previously parsed only the first file.

## Validation contracts

```bash
./scripts/validate.sh
ruby scripts/test_publication_secrets.rb
ruby scripts/test_docker_validation.rb
./scripts/validate-runtime-secrets.sh
```

- `validate.sh` validates publication sentinels/key contracts, YAML, reference backup constraints and Docker script structure/syntax. Secret fixtures must contain exactly one YAML document, unique scalar mapping keys, the exact SealedSecret API/name/namespace contract and required consumer keys; extra documents, aliases and mixed ciphertext fail. Tests compare the required-key inventory to non-optional secretKeyRef consumers in retained manifests. It explicitly reports missing optional tools. Hostname presence is a basic inventory check, not full cross-file agreement.
- When installed, `kubectl` renders dev/prod/platform references and Terraform runs formatting/provider validation. A skipped check is not a pass; Terraform provider validation also needs initialization.
- `validate-runtime-secrets.sh` must **exit nonzero on this checkout**. It rejects publication annotations, sentinels, missing keys and malformed envelopes across all eight secret resources. Tests demonstrate that a fabricated ciphertext-shaped value can pass shape checking: decryption and credential correctness are deliberately not claimed.
- Shape checks do not prove availability of external `jwt-keys`, controller bindings, mounted credentials, runtime permissions or service health. A validator does not automatically gate a live Argo controller unless an authorized operator wires such enforcement into a different operational source.
- Do not relax runtime validation to make this portfolio snapshot appear deployment-ready.

## Historical exposure and owner-controlled actions

Gitleaks **8.30.1**, default rules and full redaction, scanned the single pre-review commit across all fetched refs. It reported two candidates, both inside PostgreSQL encryptedData. These are ciphertext-shaped payloads, not confirmed live plaintext keys. No broad scanner allowlist was added. Current-tree cleanup does not erase them from the original public commit.

The fetched repository initially exposed only `main`, no tags, and empty queried release, issue/PR and Actions-artifact lists. This is a point-in-time inventory, not proof that forks, cached data, closed issues or inaccessible refs are absent. Closed-issue/history-artifact discovery was not exhaustive.

Authorized maintainers must:

1. Confirm this public repository is not a live reconciliation/deployment source before merging publication-fixture changes. Keep private operational repositories and their secrets separate.
2. Review ownership/licensing approval for product-derived manifests and documentation. Existing attribution and LICENSE were preserved, not re-assigned.
3. If a real plaintext secret or private sealing key is found elsewhere, revoke/rotate it and reseal affected material through the private operations process. Removing ciphertext alone does not justify indiscriminate rotation or prove current compromise.
4. Decide separately whether historical copies require owner-approved rewriting/removal or visibility changes. No force-push, deletion, archival or visibility change was performed here.
5. Review the historical cutover's rollback trap separately before reuse. Once worker services can accept writes, restarting the original state without a consistent reverse synchronization can lose data. Parameterization and syntax checks do not fix that operational hazard; no migration or rollback was tested.

## Safety boundary

Public domains, RFC1918 topology, ports, resource names and secret key names are configuration, not authentication secrets. Their presence was not automatically treated as a credential leak. Operator-specific tunnel identifiers/SSH paths were removed where unnecessary. Historical runbooks remain labelled reference material and must not be used as unreviewed production procedures.

No live cluster, Cloudflare API, SSH host, database, storage service or credential store was contacted. No production sync policy was changed. Passing offline checks is not a certification that every historical or upstream artifact is safe to publish.

## Recorded local results (2026-10-22)

| Command | Result |
| --- | --- |
| `./scripts/validate.sh` with temporary Kustomize on PATH | Pass, exit 0; Terraform fmt/provider validation explicitly **SKIPPED** because Terraform was unavailable |
| `ruby scripts/test_publication_secrets.rb` | 11 tests, 342 assertions, zero failures/errors |
| `ruby scripts/test_docker_validation.rb` | 1 test, 3 assertions, zero failures/errors |
| `./scripts/validate-runtime-secrets.sh` | Expected rejection, exit 1; publication fixtures are not deployable |
| `kustomize build kubernetes/overlays/dev` / `prod`, `platform`, `argocd` | All four rendered offline, exit 0; no apply/sync |
| `actionlint -shellcheck='' -pyflakes=''` | Pass, exit 0; optional ShellCheck/Pyflakes subprocesses disabled |
| `gitleaks dir --redact=100 --no-banner .` | Pass, exit 0, no checked-out-tree candidates |
| `git diff --check` and diff checks on Argo/base/Kustomization policy paths | Pass, exit 0; production policies unchanged |

Kustomize 5.7.1, Actionlint 1.7.7 and checksum-verified Gitleaks 8.30.1 were temporary tools. No provider initialization, live credential test, historical erasure, migration or full ShellCheck run was performed.
