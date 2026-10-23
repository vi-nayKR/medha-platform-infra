#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

scripts=(docker/scripts/*.sh)
for script in "${scripts[@]}"; do
  bash -n "$script"
done

required=(
  docker/Dockerfile.split
  docker/scripts/apply-firewall.sh
  docker/scripts/cutover-two-node.sh
  docker/supervisor/worker.conf
  docker/supervisor/storage.conf
  docker/systemd/medha-worker.service
  docker/systemd/medha-storage.service
  docker/systemd/medha-firewall.service
  docker/firewall/worker.nft
  docker/firewall/storage.nft
)
for file in "${required[@]}"; do
  [[ -s "$file" ]] || { echo "missing required file: $file" >&2; exit 1; }
done

grep -q 'MEDHA_ROLE=worker' docker/systemd/medha-worker.service
grep -q 'MEDHA_ROLE=storage' docker/systemd/medha-storage.service
grep -q 'MEDHA_STORAGE_HOST:-10.0.0.20' docker/scripts/run-backend-dev.sh
grep -q 'MEDHA_STORAGE_HOST:-10.0.0.20' docker/scripts/run-backend-prod.sh
grep -q '10.0.0.10:18082' docker/nginx/dev.conf
grep -q '10.0.0.10:18083' docker/nginx/prod.conf
grep -q -- '-filer.port=8888' docker/supervisor/storage.conf
grep -q -- '-filer.port=8889' docker/supervisor/storage.conf

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "${scripts[@]}" scripts/validate-docker-split.sh
fi

echo "two-node Docker reference structure/syntax passed (not deployment readiness)"
