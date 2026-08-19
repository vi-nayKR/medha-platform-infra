#!/usr/bin/env bash
# Mirrors object data from the retiring MinIO StatefulSet to the new SeaweedFS
# StatefulSet, bucket by bucket, then verifies object counts match.
#
# Buckets are discovered dynamically from the source (`mc ls old-minio`), not
# hardcoded — the app's four "managed" buckets (feeds, profiles,
# festival-logos, admin-media) are not the only ones live in this account.
# As of the last check, dev also has `medha-dev` (empty) and prod also has
# `medha-prod` (legacy pre-restructuring data) and `medha-releases` (the
# Android OTA APK — actively served, do not skip it). `mc mirror --preserve`
# copies each bucket's policy along with its objects.
#
# SEQUENCING — this script only works during the migration window:
#   1. Deploy kubernetes/base/seaweedfs.yaml (and seaweedfs-sealed-secret.yaml)
#      ALONGSIDE the still-running minio.yaml — do not delete minio.yaml yet.
#   2. Run this script for the target environment.
#   3. Verify the printed counts match for every bucket.
#   4. Only then merge the rest of the cutover (backend pointed at
#      S3_ENDPOINT=seaweedfs:8333, ingress repointed, minio.yaml removed).
#
# The OLD MinIO credentials are NOT read from this repo — this repo's
# SealedSecret no longer carries minio-access-key/minio-secret-key once the
# cutover manifests are merged. Supply them explicitly (from wherever they
# were originally stored) via OLD_MINIO_ACCESS_KEY / OLD_MINIO_SECRET_KEY.
# The NEW SeaweedFS credentials are fetched live from the cluster.
#
# Requires: kubectl (with access to the target namespace), and either a local
# `mc` (MinIO Client — despite the name, a generic S3 CLI) or network access
# to install it.
set -euo pipefail

env="${1:?usage: $0 <dev|prod>}"
case "$env" in
  dev|prod) ;;
  *) echo "env must be 'dev' or 'prod', got: $env" >&2; exit 1 ;;
esac

: "${OLD_MINIO_ACCESS_KEY:?set OLD_MINIO_ACCESS_KEY to the retiring MinIO access key}"
: "${OLD_MINIO_SECRET_KEY:?set OLD_MINIO_SECRET_KEY to the retiring MinIO secret key}"

minio_local_port=19000
seaweedfs_local_port=18333

mc_bin="mc"
if ! command -v mc >/dev/null 2>&1; then
  echo "mc not found on PATH — install it first: https://min.io/docs/minio/linux/reference/minio-mc.html" >&2
  exit 1
fi

echo "== fetching current SeaweedFS S3 credentials for $env from the cluster =="
new_access_key="$(kubectl get secret "backend-${env}-secrets" -n "$env" -o jsonpath='{.data.s3-access-key}' | base64 -d)"
new_secret_key="$(kubectl get secret "backend-${env}-secrets" -n "$env" -o jsonpath='{.data.s3-secret-key}' | base64 -d)"

echo "== port-forwarding to minio and seaweedfs services in namespace $env =="
kubectl port-forward -n "$env" svc/minio "${minio_local_port}:9000" >/tmp/pf-minio.log 2>&1 &
minio_pf_pid=$!
kubectl port-forward -n "$env" svc/seaweedfs "${seaweedfs_local_port}:8333" >/tmp/pf-seaweedfs.log 2>&1 &
seaweedfs_pf_pid=$!
trap 'kill "$minio_pf_pid" "$seaweedfs_pf_pid" 2>/dev/null || true' EXIT
sleep 3

"$mc_bin" alias set old-minio "http://127.0.0.1:${minio_local_port}" "$OLD_MINIO_ACCESS_KEY" "$OLD_MINIO_SECRET_KEY" >/dev/null
"$mc_bin" alias set new-seaweedfs "http://127.0.0.1:${seaweedfs_local_port}" "$new_access_key" "$new_secret_key" >/dev/null

mapfile -t buckets < <("$mc_bin" ls old-minio | awk '{print $NF}' | sed 's:/$::')
if [ "${#buckets[@]}" -eq 0 ]; then
  echo "no buckets found on old-minio — nothing to migrate, check credentials/connectivity" >&2
  exit 1
fi
echo "== discovered buckets: ${buckets[*]} =="

overall_ok=true
for bucket in "${buckets[@]}"; do
  "$mc_bin" mb --ignore-existing "new-seaweedfs/${bucket}" >/dev/null

  echo "== mirroring bucket: $bucket (objects + policy) =="
  "$mc_bin" mirror --overwrite --preserve "old-minio/${bucket}" "new-seaweedfs/${bucket}"

  src_count="$("$mc_bin" ls --recursive "old-minio/${bucket}" 2>/dev/null | wc -l | tr -d ' ')"
  dst_count="$("$mc_bin" ls --recursive "new-seaweedfs/${bucket}" 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$src_count" = "$dst_count" ]; then
    echo "OK   ${bucket}: ${src_count} objects on both sides"
  else
    echo "FAIL ${bucket}: source=${src_count} dest=${dst_count} — counts do not match" >&2
    overall_ok=false
  fi

  # mc mirror --preserve does not transfer bucket-level policy (only object
  # metadata/ACLs) — copy the policy document explicitly.
  src_policy="$("$mc_bin" anonymous get-json "old-minio/${bucket}" 2>/dev/null || echo "{}")"
  if [ "$src_policy" != "{}" ]; then
    policy_file="$(mktemp)"
    echo "$src_policy" > "$policy_file"
    "$mc_bin" anonymous set-json "$policy_file" "new-seaweedfs/${bucket}" >/dev/null
    rm -f "$policy_file"
  fi

  # JSON gets re-serialized on the way through (single-item arrays become
  # bare strings), so compare presence/absence rather than exact bytes.
  dst_policy="$("$mc_bin" anonymous get-json "new-seaweedfs/${bucket}" 2>/dev/null || echo "{}")"
  if [ "$src_policy" != "{}" ] && [ "$dst_policy" = "{}" ]; then
    echo "FAIL ${bucket}: bucket policy did not carry over as expected" >&2
    overall_ok=false
  fi
done

if [ "$overall_ok" = true ]; then
  echo "== all buckets verified — safe to complete the cutover for $env =="
else
  echo "== one or more buckets mismatched — do NOT complete the cutover yet ==" >&2
  exit 1
fi
