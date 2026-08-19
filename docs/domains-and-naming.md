# Domains and service naming

| Service | Production | Development | Exposure |
|---|---|---|---|
| Web | `medha.dev` | `dev.medha.dev` | Public Worker |
| Web alias | `www.medha.dev` | - | Public Worker alias |
| API | `api.medha.dev` | `api-dev.medha.dev` | Public tunnel |
| Admin | `admin.medha.dev` | `admin-dev.medha.dev` | Cloudflare Access |
| S3 API | `s3.medha.dev` | `s3-dev.medha.dev` | Public when uploads require it |
| PostgreSQL | none | none | Namespace-private only |
| Redis | none | none | Namespace-private only |
| Argo CD | none | none | SSH local forward only |
| SSH | `ssh-master`, `ssh-worker`, `ssh-storage` | same operator plane | Cloudflare Access |

`s3*` always means the S3-compatible API (SeaweedFS), on port 8333. There is no
browser console hostname — bucket browsing goes through the admin panel's own
Bucket Manager (`/api/v2/admin/buckets*`), not a storage-vendor UI. The retired
`minio-console*` and `minio*`/`minio-dev*` names must not be reused.

Inside either namespace the names are exactly `backend`, `postgres`, `redis`,
and `seaweedfs`. Do not add environment suffixes to service names.
