# Operations

## Argo CD over SSH

From the workstation (macOS/Linux):

```bash
cd medha-infra
./scripts/argocd-local-access.sh
```

From the workstation (Windows PowerShell):

```powershell
cd medha-infra
.\scripts\argocd-local-access.ps1
```

Or run the equivalent command directly:

```bash
ssh -o ExitOnForwardFailure=yes \
  -L 8081:127.0.0.1:8081 medha-master \
  "kubectl -n argocd port-forward --address 127.0.0.1 svc/argocd-server 8081:80"
```

Open `http://127.0.0.1:8081`. The port-forward binds only to loopback; there is
no DNS record, Tunnel hostname or Kubernetes Ingress for Argo CD.

## Validation

Run `./scripts/validate.sh`. In CI install `kubectl` and Terraform so the script
also renders both overlays and validates the Cloudflare module.

The API repository's `dev` and `prod` GitHub environments each require an
`INFRA_REPO_TOKEN` that can update `vi-nayKR/medha-platform-infra`. Keep the
production environment reviewer gate enabled.
