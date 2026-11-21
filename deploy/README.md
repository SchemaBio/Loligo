# SchemaBio self-hosted deployment

This is the production entry point for the self-hosted route. PostgreSQL and
ZhiJi run in Docker Compose. Loligo runs as the host systemd service
`zhiji-loligo` so it can call the operator-installed miniwdl and read the
workflow output tree. Sepiida Server and the Sepiida agent are an existing
external shared service. This deployment does not create, build, or restart
them, and it does not generate Sepiida database passwords, query keys, agent
keys, or signing secrets. When `SEPIIDA_ENABLED=true`, `SEPIIDA_URL` and
`SEPIIDA_QUERY_KEY` must be supplied from that external service. Workflows that
need an agent must use an agent that is already managed outside this
repository.

Host paths are `/opt/zhiji` and `/var/lib/zhiji`. Compose publishes PostgreSQL
on `127.0.0.1:54322` and ZhiJi on `127.0.0.1:3002`. The host Loligo process
listens on `LOLIGO_PORT` (default `8082`). ZhiJi inside Compose still listens
on container port 3000. This Compose file does not define a Loligo container.
`ZHIJI_SERVER_API_URL` is
`http://host.docker.internal:${LOLIGO_PORT:-8082}/api`. The ZhiJi service maps
`host.docker.internal` to `host-gateway` so Linux Docker Engine resolves that
name to the host. Browsers keep the same-origin `/api` contract:
`ZHIJI_API_URL` stays `/api`. API cookies remain `access_token`,
`refresh_token`, and `csrf_token`. Use a separate hostname when this line runs
beside the genetic product line.

## ZhiJi interface language

Set `ZHIJI_DEFAULT_LOCALE` in the deployment `.env` to `zh-CN` (default),
`zh-Hant`, `en`, or `es-419`. Recreate the ZhiJi container after changing it;
the image does not need rebuilding. A browser's saved language takes priority.
Users choose their preference under Settings → Personal settings → Interface language
and click Save. The preference is retained in that browser after logout.

## Requirements

- Linux with systemd, Docker Engine, Docker Compose v2, Bash, and OpenSSL
- The Loligo, ZhiJi, and Sepiida repositories checked out as siblings
- miniwdl installed on the host
- A workflow catalog containing `conf/local.cfg`

The `schemabio` service account is added to the Docker group. Docker group
membership is effectively root-equivalent access; only trusted code and users
may modify the workflow catalog, miniwdl executable, or service environment.

## Install

```sh
cd Loligo/deploy
bash ./deploy.sh init
# Edit .env: set PUBLIC_ORIGIN and, if needed, workflow/miniwdl paths.
bash ./deploy.sh check
sudo bash ./deploy.sh install
bash ./deploy.sh credentials
```

`install` builds Loligo from its application image directly into `INSTALL_ROOT/bin`.
It does not compile or install a Sepiida agent. The command then creates data
directories, writes the `zhiji-loligo` systemd unit, starts the Compose
dependencies, and starts the Loligo host service. Generated Loligo and
PostgreSQL credentials are stored in `.generated/runtime.env` with mode `0600`
and remain stable across repeated initialization. Sepiida credentials are
never written there.

Use `sudo bash ./deploy.sh up|down`, `bash ./deploy.sh status`, and
`bash ./deploy.sh credentials` for ongoing operation.

## COS Parquet and SVC engines

SaaS deployments can merge `saas-parquet-query.override.yaml` with their
existing Compose file. The override mounts writable Parquet cache and assessment
directories for Loligo UID/GID 1000 and initializes their permissions. Query,
preparation, export, schema and pinned SVC scoring run inside Loligo's pure Go
process. Python and DuckDB are not runtime dependencies. The override filename
is retained for existing deployment commands; it no longer adds a query service
or dedicated network. Ordinary SaaS auth/workflow dependencies remain unchanged.

Build and apply it from the SaaS deployment directory with
`LOLIGO_IMAGE` set to the image tag built from this repository. That command
selects the Loligo service in the existing SaaS Compose file. It does not add
a Loligo container to this directory's self-hosted Compose file. Remove
`PARQUET_QUERY_URL`, `RESULT_ENGINE_BACKEND` and `SVC_ENGINE_BACKEND` from
Loligo's environment; startup rejects obsolete runtime settings explicitly:

```sh
docker compose -f compose.yaml \
  -f ../Loligo/deploy/saas-parquet-query.override.yaml \
  up -d loligo
```

`RESULT_ENGINE_TEMP_DIR` defaults to the cache's `tmp` subdirectory. Both data
directories must be writable; cache objects and existing assessments are retained.

## Reverse proxy contract

The deployment does not manage DNS, TLS, or a reverse proxy. Route `/api/*` to
the host Loligo listener `127.0.0.1:8082` (or `LOLIGO_PORT`) without rewriting
the path, and route all other application paths to `127.0.0.1:3002`. Browser
traffic stays on that proxy contract. `host.docker.internal` is only the ZhiJi
container's route to the host process. Sepiida is not bound by this deployment.
Reach it only through the external `SEPIIDA_URL`.

## Verify the deployment

Sign in to ZhiJi through `PUBLIC_ORIGIN`. Create a synthetic sample and
reload the Samples page to confirm it was saved. If Sepiida is enabled,
open the Runtime tab of a task reported by your Sepiida instance to check
its workflow status. If the query is temporarily unavailable, ZhiJi shows
the last saved task status. Refresh the Runtime tab once Sepiida is reachable.
