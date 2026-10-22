#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

ruby scripts/check-secrets.rb --publication
ruby scripts/test_publication_secrets.rb
ruby scripts/test_docker_validation.rb

# Inspect tracked text only; no network, infrastructure access, or ripgrep dependency.
ruby -e '
  paths = IO.popen(["git", "ls-files", "-z"], &:read).split("\0").select { |path| File.file?(path) }
  texts = paths.map { |path| [path, File.read(path, encoding: "UTF-8")] }.select { |_, text| text.valid_encoding? }
  expected = %w[medha.dev www.medha.dev dev.medha.dev api.medha.dev api-dev.medha.dev admin.medha.dev admin-dev.medha.dev s3.medha.dev s3-dev.medha.dev]
  expected.each { |host| abort "missing hostname declaration: #{host}" unless texts.any? { |_, text| text.include?(host) } }
  excluded = %w[docs/migration.md docs/HANDOFF.md platform/cloudflared/host-migration-config.yml]
  legacy = /dev-api\.medhainnovation\.com|minio-console(-dev)?\.medhainnovation\.com|argocd\.medhainnovation\.com/
  texts.each { |path, text| abort "legacy management hostname outside migration record: #{path}" if !excluded.include?(path) && text.match?(legacy) }
'

for env in dev prod; do
  test -f "kubernetes/overlays/$env/backend-sealed-secret.yaml"
  if command -v kubectl >/dev/null; then
    kubectl kustomize "kubernetes/overlays/$env" >/dev/null
  elif command -v kustomize >/dev/null; then
    kustomize build "kubernetes/overlays/$env" >/dev/null
  else
    echo "SKIP: kubectl/kustomize unavailable; $env rendering was not checked"
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

for scope in platform argocd; do
  if command -v kubectl >/dev/null; then
    kubectl kustomize "$scope" >/dev/null
  elif command -v kustomize >/dev/null; then
    kustomize build "$scope" >/dev/null
  else
    echo "SKIP: kubectl/kustomize unavailable; $scope rendering was not checked"
  fi
done

if command -v terraform >/dev/null; then
  terraform -chdir=terraform/cloudflare fmt -check
  if [ -d terraform/cloudflare/.terraform/providers ]; then
    terraform -chdir=terraform/cloudflare validate
  else
    echo "SKIP: terraform providers uninitialized; provider validation was not checked"
  fi
else
  echo "SKIP: terraform unavailable; fmt/provider validation was not checked"
fi

./scripts/validate-docker-split.sh

echo "publication reference checks passed subject to reported SKIPs; NOT deployment readiness"
