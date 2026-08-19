#!/bin/bash
set -euo pipefail
umask 077

set -a
# shellcheck disable=SC1091
source /opt/medha/config/.env
set +a

worker_host="${MEDHA_WORKER_HOST:-10.0.0.10}"
timestamp="$(date -u +%Y%m%d_%H%M%S)"
backup_dir=/data/backups

dump_db() {
  local environment="$1" port="$2" user="$3" password="$4" database="$5"
  local temporary="$backup_dir/.db_${environment}_${timestamp}.dump.tmp"
  local final="$backup_dir/db_${environment}_${timestamp}.dump"
  PGPASSWORD="$password" pg_dump --host="$worker_host" --port="$port" \
    --username="$user" --dbname="$database" --format=custom --file="$temporary"
  pg_restore --list "$temporary" >/dev/null
  mv "$temporary" "$final"
  sha256sum "$final" >"$final.sha256"
}

echo "[$(date -u --iso-8601=seconds)] starting backup"
dump_db dev 5432 "$DEV_POSTGRES_USER" "$DEV_POSTGRES_PASSWORD" "$DEV_POSTGRES_DB"
dump_db prod 5433 "$PROD_POSTGRES_USER" "$PROD_POSTGRES_PASSWORD" "$PROD_POSTGRES_DB"

seaweed_tmp="$backup_dir/.seaweedfs_prod_${timestamp}.tar.gz.tmp"
seaweed_final="$backup_dir/seaweedfs_prod_${timestamp}.tar.gz"
tar -czf "$seaweed_tmp" -C /data/seaweedfs-prod .
mv "$seaweed_tmp" "$seaweed_final"
sha256sum "$seaweed_final" >"$seaweed_final.sha256"

find "$backup_dir" -type f \( -name 'db_*.dump' -o -name 'db_*.dump.sha256' \
  -o -name 'seaweedfs_*.tar.gz' -o -name 'seaweedfs_*.tar.gz.sha256' \) \
  -mtime +7 -delete
echo "[$(date -u --iso-8601=seconds)] backup completed"
