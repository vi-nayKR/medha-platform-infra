#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

ruby -ryaml -e '
  errors = []
  required_backend = {
    "dev" => %w[database-url s3-access-key s3-secret-key],
    "prod" => %w[database-url s3-access-key s3-secret-key credentials-encryption-key]
  }

  required_backend.each do |env, required|
    path = "kubernetes/overlays/#{env}/backend-sealed-secret.yaml"
    encrypted = YAML.load_file(path).dig("spec", "encryptedData") || {}
    missing = required - encrypted.keys
    errors << "#{env}: backend SealedSecret is missing #{missing.join(", ")}" unless missing.empty?

    postgres = "kubernetes/overlays/#{env}/postgres-sealed-secret.yaml"
    unless File.file?(postgres)
      errors << "#{env}: missing #{postgres}"
      next
    end
    postgres_encrypted = YAML.load_file(postgres).dig("spec", "encryptedData") || {}
    postgres_missing = %w[POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB] - postgres_encrypted.keys
    errors << "#{env}: postgres SealedSecret is missing #{postgres_missing.join(", ")}" unless postgres_missing.empty?
  end

  abort errors.join("\n") unless errors.empty?
'

echo "runtime secret readiness passed"
