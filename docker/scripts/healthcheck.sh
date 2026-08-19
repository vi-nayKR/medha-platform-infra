#!/bin/bash
set -euo pipefail

case "${MEDHA_ROLE:-}" in
  worker)
    pg_isready -q -h 127.0.0.1 -p 5432
    pg_isready -q -h 127.0.0.1 -p 5433
    redis-cli -h 127.0.0.1 -p 6379 ping | grep -qx PONG
    redis-cli -h 127.0.0.1 -p 6380 ping | grep -qx PONG
    curl -fsS --max-time 5 http://127.0.0.1:18082/health >/dev/null
    curl -fsS --max-time 5 http://127.0.0.1:18083/health >/dev/null
    ;;
  storage)
    curl -fsS --max-time 5 http://127.0.0.1:8333/status >/dev/null
    curl -fsS --max-time 5 http://127.0.0.1:8334/status >/dev/null
    curl -fsS --max-time 5 -H 'Host: api-dev.medha.dev' http://127.0.0.1/health >/dev/null
    curl -fsS --max-time 5 -H 'Host: api.medha.dev' http://127.0.0.1/health >/dev/null
    ;;
  *) exit 1 ;;
esac
