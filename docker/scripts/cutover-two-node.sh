#!/bin/bash
set -euo pipefail

[[ "${CONFIRM_CUTOVER:-}" == "yes" ]] || {
  echo "Set CONFIRM_CUTOVER=yes to run the production cutover" >&2
  exit 64
}

worker=medha-worker@10.0.0.10
ssh_opts=(-i /home/medha-storage/.ssh/id_ed25519 -o BatchMode=yes \
  -o UserKnownHostsFile=/home/medha-storage/.ssh/known_hosts)
old_container=medha
switched_storage=false
completed=false

worker_ssh() {
  ssh "${ssh_opts[@]}" "$worker" "$@"
}

wait_for() {
  local description="$1"; shift
  for _ in $(seq 1 30); do
    if "$@"; then return 0; fi
    sleep 2
  done
  echo "Timed out waiting for $description" >&2
  return 1
}

rollback() {
  local status=$?
  [[ "$completed" == true ]] && return
  echo "Cutover failed; restoring the original single-container deployment" >&2
  set +e
  if [[ "$switched_storage" == true ]]; then
    sudo systemctl stop medha-storage.service
  fi
  worker_ssh sudo systemctl stop medha-worker.service
  if ! sudo docker ps --format '{{.Names}}' | grep -qx "$old_container"; then
    sudo docker start "$old_container"
  fi
  sleep 12
  sudo docker exec "$old_container" supervisorctl start all
  exit "$status"
}
trap rollback ERR INT TERM

hostname -I | tr ' ' '\n' | grep -qx 10.0.0.20
worker_ssh "hostname -I | tr ' ' '\\n' | grep -qx 10.0.0.10"
sudo docker ps --format '{{.Names}}' | grep -qx "$old_container"
curl -fsS -H 'Host: api-dev.medha.dev' http://127.0.0.1/health >/dev/null
curl -fsS -H 'Host: api.medha.dev' http://127.0.0.1/health >/dev/null
worker_ssh sudo docker image inspect medha-split:20260820.1 >/dev/null

echo "Stopping API writers and stateful worker services in the old container"
sudo docker exec "$old_container" supervisorctl stop backend-dev backend-prod
sudo docker exec "$old_container" supervisorctl stop redis-dev redis-prod
sudo docker exec "$old_container" supervisorctl stop postgres-dev postgres-prod

sudo docker exec -u postgres "$old_container" \
  /usr/lib/postgresql/17/bin/pg_controldata /data/postgres-dev | grep -q 'Database cluster state:.*shut down'
sudo docker exec -u postgres "$old_container" \
  /usr/lib/postgresql/17/bin/pg_controldata /data/postgres-prod | grep -q 'Database cluster state:.*shut down'

echo "Performing final consistent database/cache synchronization"
for name in postgres-dev postgres-prod redis-dev redis-prod; do
  sudo rsync -aHAX --numeric-ids --delete \
    -e "ssh ${ssh_opts[*]}" --rsync-path='sudo rsync' \
    "/opt/medha/data/$name/" "$worker:/opt/medha/data/$name/"
  mismatch="$(sudo rsync -aHAXnc --numeric-ids --delete \
    -e "ssh ${ssh_opts[*]}" --rsync-path='sudo rsync' \
    "/opt/medha/data/$name/" "$worker:/opt/medha/data/$name/")"
  if [[ -n "$mismatch" ]]; then
      echo "Verification mismatch for $name" >&2
      exit 1
  fi
done

echo "Starting and validating worker"
worker_ssh sudo systemctl start medha-worker.service
wait_for worker-health worker_ssh sudo docker exec medha-worker /opt/medha/scripts/healthcheck.sh
curl -fsS http://10.0.0.10:18082/health >/dev/null
curl -fsS http://10.0.0.10:18083/health >/dev/null

echo "Switching storage edge to the storage role"
sudo docker stop --time 90 "$old_container"
switched_storage=true
sudo systemctl start medha-storage.service
wait_for storage-health sudo docker exec medha-storage /opt/medha/scripts/healthcheck.sh

curl -fsS -H 'Host: api-dev.medha.dev' http://127.0.0.1/health >/dev/null
curl -fsS -H 'Host: api.medha.dev' http://127.0.0.1/health >/dev/null
curl -fsS -H 'Host: s3-dev.medha.dev' http://127.0.0.1/status >/dev/null
curl -fsS -H 'Host: s3.medha.dev' http://127.0.0.1/status >/dev/null

worker_ssh sudo systemctl enable medha-worker.service
sudo systemctl enable medha-storage.service
completed=true
trap - ERR INT TERM
echo "Two-node cutover completed successfully"
