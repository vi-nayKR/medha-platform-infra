#!/bin/bash
set -euo pipefail

set -a
# shellcheck disable=SC1091
source /opt/medha/config/.env
set +a

export ENVIRONMENT=production
export DATABASE_URL="postgres://${PROD_POSTGRES_USER}:${PROD_POSTGRES_PASSWORD}@127.0.0.1:5433/${PROD_POSTGRES_DB}?sslmode=disable"
export REDIS_URL=redis://127.0.0.1:6380/0
export S3_ENDPOINT="${MEDHA_STORAGE_HOST:-10.0.0.20}:8334"
export S3_PUBLIC_ENDPOINT=https://s3.medha.dev
export SERVER_PORT=18083
export LOG_LEVEL=info
export SWAGGER_ENABLED=false
export SHARE_BASE_URL=https://medha.dev
export JWT_EXPIRY_MINUTES=15
export JWT_PRIVATE_KEY_PATH=/opt/medha/keys/jwt_private.pem
export JWT_PUBLIC_KEY_PATH=/opt/medha/keys/jwt_public.pem
export RESEND_FROM_DOMAIN=support.medha.dev
export MESSAGECENTRAL_BASE_URL=https://cpaas.messagecentral.com
export MINIO_BUCKET=medha-prod
export MINIO_CONSOLE_URL=https://minio.medha.dev
export MINIO_ENDPOINT="${MEDHA_STORAGE_HOST:-10.0.0.20}:8334"
export MINIO_PUBLIC_ENDPOINT=https://s3.medha.dev
export RESEND_API_KEY="${PROD_RESEND_API_KEY:-}"
export MESSAGECENTRAL_CUSTOMER_ID="${PROD_MESSAGECENTRAL_CUSTOMER_ID:-}"
export MESSAGECENTRAL_EMAIL="${PROD_MESSAGECENTRAL_EMAIL:-}"
export MESSAGECENTRAL_KEY_BASE64="${PROD_MESSAGECENTRAL_KEY_BASE64:-}"
export MAPMYINDIA_CLIENT_ID="${PROD_MAPMYINDIA_CLIENT_ID:-}"
export MAPMYINDIA_CLIENT_SECRET="${PROD_MAPMYINDIA_CLIENT_SECRET:-}"
export ADMIN_USERNAME="${PROD_ADMIN_USERNAME:-}"
export ADMIN_PASSWORD="${PROD_ADMIN_PASSWORD:-}"
export ADMIN_API_TOKEN="${PROD_ADMIN_API_TOKEN:-}"
export S3_ACCESS_KEY="${PROD_S3_ACCESS_KEY:-}"
export S3_SECRET_KEY="${PROD_S3_SECRET_KEY:-}"
export MINIO_ACCESS_KEY="${PROD_MINIO_ACCESS_KEY:-}"
export MINIO_SECRET_KEY="${PROD_MINIO_SECRET_KEY:-}"
export CREDENTIALS_ENCRYPTION_KEY="${PROD_CREDENTIALS_ENCRYPTION_KEY:-}"
export FIREBASE_SERVICE_ACCOUNT_JSON_PATH=/opt/medha/config/firebase-service-account.json

exec /opt/medha/bin/medha-api
