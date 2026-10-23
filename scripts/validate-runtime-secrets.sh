#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Fail closed for publication fixtures, empty values and malformed envelopes.
# This is not proof of decryption, required external secrets or service health.
ruby scripts/check-secrets.rb --runtime
