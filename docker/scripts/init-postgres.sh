#!/bin/bash
set -euo pipefail

if [[ -f /opt/medha/config/.env ]]; then
  set -a
  # shellcheck disable=SC1091
  source /opt/medha/config/.env
  set +a
fi

init_pg() {
  local pgdata="$1" db="$2" user="$3" pass="$4" port="$5"
  if [[ -f "$pgdata/PG_VERSION" ]]; then
    [[ "$(<"$pgdata/PG_VERSION")" == "17" ]] || {
      echo "Refusing PostgreSQL major-version mismatch in $pgdata" >&2
      exit 1
    }
    chown -R postgres:postgres "$pgdata"
    return
  fi

  [[ -z "$(find "$pgdata" -mindepth 1 -maxdepth 1 -print -quit)" ]] || {
    echo "Refusing to initialize non-empty PostgreSQL directory $pgdata" >&2
    exit 1
  }

  echo "Initializing PostgreSQL 17 at $pgdata"
  chown -R postgres:postgres "$pgdata"
  su -s /bin/bash postgres -c "/usr/lib/postgresql/17/bin/initdb -D '$pgdata' --auth-host=scram-sha-256"
  su -s /bin/bash postgres -c "/usr/lib/postgresql/17/bin/pg_ctl -D '$pgdata' -o '-p $port' -l /data/logs/pg-init-$port.log start"
  trap 'su -s /bin/bash postgres -c "/usr/lib/postgresql/17/bin/pg_ctl -D \"$pgdata\" stop" || true' RETURN
  psql -p "$port" -U postgres -v ON_ERROR_STOP=1 \
    --set=db_user="$user" --set=db_password="$pass" --set=db_name="$db" <<'SQL'
CREATE USER :"db_user" WITH PASSWORD :'db_password';
CREATE DATABASE :"db_name" OWNER :"db_user";
SQL
  PGPASSWORD="$pass" psql -h 127.0.0.1 -p "$port" -U "$user" -d "$db" -v ON_ERROR_STOP=1 \
    -c 'CREATE EXTENSION IF NOT EXISTS postgis;'
  su -s /bin/bash postgres -c "/usr/lib/postgresql/17/bin/pg_ctl -D '$pgdata' stop"
  trap - RETURN
}

: "${DEV_POSTGRES_DB:?missing DEV_POSTGRES_DB}"
: "${DEV_POSTGRES_USER:?missing DEV_POSTGRES_USER}"
: "${DEV_POSTGRES_PASSWORD:?missing DEV_POSTGRES_PASSWORD}"
: "${PROD_POSTGRES_DB:?missing PROD_POSTGRES_DB}"
: "${PROD_POSTGRES_USER:?missing PROD_POSTGRES_USER}"
: "${PROD_POSTGRES_PASSWORD:?missing PROD_POSTGRES_PASSWORD}"

init_pg /data/postgres-dev "$DEV_POSTGRES_DB" "$DEV_POSTGRES_USER" "$DEV_POSTGRES_PASSWORD" 5432
init_pg /data/postgres-prod "$PROD_POSTGRES_DB" "$PROD_POSTGRES_USER" "$PROD_POSTGRES_PASSWORD" 5433
