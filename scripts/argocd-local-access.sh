#!/bin/bash
exec bun "$(dirname "$0")/argocd-local-access.js" "$@"


