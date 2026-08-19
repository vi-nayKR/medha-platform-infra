#!/bin/bash
set -euo pipefail

case "${MEDHA_ROLE:-}" in
  worker)
    chown root:postgres /data/logs
    chmod 0775 /data/logs
    /opt/medha/scripts/init-postgres.sh
    exec /usr/bin/supervisord -c /etc/supervisor/worker.conf
    ;;
  storage)
    exec /usr/bin/supervisord -c /etc/supervisor/storage.conf
    ;;
  *)
    echo "MEDHA_ROLE must be either worker or storage" >&2
    exit 64
    ;;
esac
