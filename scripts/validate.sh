#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

expected=(
  medha.dev www.medha.dev dev.medha.dev
  api.medha.dev api-dev.medha.dev
  admin.medha.dev admin-dev.medha.dev
  s3.medha.dev s3-dev.medha.dev
)

for host in "${expected[@]}"; do
  rg -q --fixed-strings "$host" . || { echo "missing hostname declaration: $host" >&2; exit 1; }
done

if rg -n 'dev-api\.medhainnovation\.com|minio-console(-dev)?\.medhainnovation\.com|argocd\.medhainnovation\.com' \
  --glob '!docs/migration.md' \
  --glob '!docs/HANDOFF.md' \
  --glob '!platform/cloudflared/host-migration-config.yml' .; then
  echo "legacy/public management hostname remains outside the migration record" >&2
  exit 1
fi

for env in dev prod; do
  test -f "kubernetes/overlays/$env/backend-sealed-secret.yaml"
  if command -v kubectl >/dev/null; then
    kubectl kustomize "kubernetes/overlays/$env" >/dev/null
  fi
done

ruby -e '
  require "yaml"
  Dir.glob("{kubernetes,platform,argocd}/**/*.{yaml,yml}").sort.each do |path|
    YAML.load_stream(File.read(path))
  rescue StandardError => e
    warn "invalid YAML #{path}: #{e.message}"
    exit 1
  end
'

ruby -e '
  require "yaml"
  cron = YAML.safe_load(File.read("kubernetes/overlays/prod/backup-cronjob.yaml"))
  abort "backup jobs must not overlap" unless cron.dig("spec", "concurrencyPolicy") == "Forbid"
  job = cron.dig("spec", "jobTemplate", "spec")
  abort "backup deadline is missing" unless job["activeDeadlineSeconds"].to_i.positive?
  container = job.dig("template", "spec", "containers", 0)
  abort "backup client must match PostgreSQL 17" unless container["image"].start_with?("postgres:17")
  secret_env = container.fetch("env").each_with_object([]) do |entry, names|
    names << entry["name"] if entry.dig("valueFrom", "secretKeyRef", "name") == "postgres-secrets"
  end
  missing = %w[PGPASSWORD POSTGRES_USER POSTGRES_DB] - secret_env
  abort "backup secret variables missing: #{missing.join(", ")}" unless missing.empty?
  script = container.fetch("args").join("\n")
  abort "backup must use custom pg_dump format" unless script.include?("--format=custom")
  abort "backup must verify pg_dump output" unless script.include?("pg_restore --list")
  abort "backup must publish files atomically" unless script.include?(".partial")
'

if command -v kubectl >/dev/null; then
  kubectl kustomize platform >/dev/null
fi

if command -v terraform >/dev/null; then
  terraform -chdir=terraform/cloudflare fmt -check
  terraform -chdir=terraform/cloudflare validate
fi

echo "medha-infra validation passed"
