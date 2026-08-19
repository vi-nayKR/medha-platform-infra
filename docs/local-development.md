# Local development

No prod credentials are ever needed for normal local work.

## medha-api

```bash
cd ../medha-api
../medha-infra/scripts/sync-env.sh api   # scaffold .env from .env.example, then fill dev values
make services-up                          # local postgres + redis
make dev                                  # air hot-reload
```

`.env` should have `ENVIRONMENT=development` and localhost / `-dev-` infra hosts.
The startup guard will refuse to boot if you point it at a `-prod-` host.

## medha-web / medha-admin-panel

```bash
bun install        # (web)   /   npm install --legacy-peer-deps  (admin)
bun run dev        # (web)   /   npm run dev  (admin)
```

`vite` runs in development mode → reads `.env.development` → talks to `api-dev.medha.dev`.
The dev API's CORS allows `localhost`, so no proxy is needed. For a temporary local
override in dev only, set `localStorage.medha_api_base` in the browser console.

## medha-android

```bash
./gradlew assembleDevDebug     # installs as com.medha.android(.dev), talks to api-dev
./gradlew assembleProdDebug    # prod API, for testing prod config
```

`dev` flavor → `api-dev.medha.dev`; `prod` flavor → `api.medha.dev`.
