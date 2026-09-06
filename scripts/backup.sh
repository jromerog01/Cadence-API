#!/usr/bin/env bash
# Dumps Postgres (schema + data) to backups/, gzip'd and timestamped.
# Cron example (daily at 3am): 0 3 * * * cd /path/to/cadenceAPI && ./scripts/backup.sh >> backups/backup.log 2>&1
#
# Restore with:
#   gunzip -c backups/cadence-<timestamp>.sql.gz | docker compose exec -T postgres psql -U "$POSTGRES_USER" "$POSTGRES_DB"
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

mkdir -p backups
stamp=$(date +%Y%m%d-%H%M%S)
out="backups/cadence-${stamp}.sql.gz"

docker compose exec -T postgres pg_dump -U "${POSTGRES_USER:-cadence}" "${POSTGRES_DB:-cadence}" | gzip > "$out"
echo "$out"
