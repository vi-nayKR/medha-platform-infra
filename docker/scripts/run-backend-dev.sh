#!/bin/bash
set -euo pipefail

set -a
# shellcheck disable=SC1091
source /opt/medha/config/.env
set +a

export ENVIRONMENT=development
export DATABASE_URL="postgres://${DEV_POSTGRES_USER}:${DEV_POSTGRES_PASSWORD}@127.0.0.1:5432/${DEV_POSTGRES_DB}?sslmode=disable"
export REDIS_URL=redis://127.0.0.1:6379/0
export S3_ENDPOINT="${MEDHA_STORAGE_HOST:-10.0.0.20}:8333"
export S3_PUBLIC_ENDPOINT=https://s3-dev.medha.dev
export SERVER_PORT=18082
export LOG_LEVEL=debug
export SWAGGER_ENABLED=true
export SHARE_BASE_URL=https://dev.medha.dev
export JWT_EXPIRY_MINUTES=15
export JWT_PRIVATE_KEY_PATH=/opt/medha/keys/jwt_private.pem
export JWT_PUBLIC_KEY_PATH=/opt/medha/keys/jwt_public.pem
export RESEND_FROM_DOMAIN=support.medha.dev
export MESSAGECENTRAL_BASE_URL=https://cpaas.messagecentral.com
export RESEND_API_KEY="${DEV_RESEND_API_KEY:-}"
export MESSAGECENTRAL_CUSTOMER_ID="${DEV_MESSAGECENTRAL_CUSTOMER_ID:-}"
export MESSAGECENTRAL_EMAIL="${DEV_MESSAGECENTRAL_EMAIL:-}"
export MESSAGECENTRAL_KEY_BASE64="${DEV_MESSAGECENTRAL_KEY_BASE64:-}"
export MAPMYINDIA_CLIENT_ID="${DEV_MAPMYINDIA_CLIENT_ID:-}"
export MAPMYINDIA_CLIENT_SECRET="${DEV_MAPMYINDIA_CLIENT_SECRET:-}"
export ADMIN_USERNAME="${DEV_ADMIN_USERNAME:-}"
export ADMIN_PASSWORD="${DEV_ADMIN_PASSWORD:-}"
export ADMIN_API_TOKEN="${DEV_ADMIN_API_TOKEN:-}"
export S3_ACCESS_KEY="${DEV_S3_ACCESS_KEY:-}"
export S3_SECRET_KEY="${DEV_S3_SECRET_KEY:-}"
export MINIO_ACCESS_KEY="${DEV_MINIO_ACCESS_KEY:-}"
export MINIO_SECRET_KEY="${DEV_MINIO_SECRET_KEY:-}"

exec /opt/medha/bin/medha-api
