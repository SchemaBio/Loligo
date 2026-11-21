#!/bin/sh
set -eu

psql --set=ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --set=loligo_password="$LOLIGO_DB_PASSWORD" \
  --file=/docker-entrypoint-initdb.d/10-init-databases.sql.template
