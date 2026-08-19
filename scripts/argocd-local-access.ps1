$ErrorActionPreference = "Stop"

$listenPort = $env:ARGOCD_LOCAL_PORT
if (-not $listenPort) {
    $listenPort = "5051"
}

$sshHost = $env:ARGOCD_SSH_HOST
if (-not $sshHost) {
    $sshHost = "medha-master"
}

if ($listenPort -notmatch "^\d+$") {
    Write-Error "ARGOCD_LOCAL_PORT must be numeric"
    exit 1
}

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Write-Error "ssh is required (ensure OpenSSH Client is installed or available in PATH)"
    exit 1
}

Write-Host "Argo CD will be available at http://127.0.0.1:$listenPort"
Write-Host "Keep this process running; press Ctrl-C to close access."

ssh -o ExitOnForwardFailure=yes `
  -L "${listenPort}:127.0.0.1:${listenPort}" `
  $sshHost `
  "kubectl --namespace argocd port-forward --address 127.0.0.1 service/argocd-server ${listenPort}:80"
