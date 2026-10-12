#!/usr/bin/env bash
# =============================================================================
# WeberQ ERP — Staging Refresh
# Rebuilds the staging copy of production on the VM: database weberq_staging
# and its filestore, neutralized (no outgoing or incoming mail, no scheduled
# actions, no payment providers), served on 127.0.0.1:18069 only.
#
# Run on the VM as root:   staging_refresh.sh [--keep-db] [image]
#                            image defaults to the one prod runs; --keep-db
#                            only recreates the container
# Reach it from a laptop:  ssh -N -L 18069:127.0.0.1:18069 <user>@<vm>
#                          then http://localhost:18069
#
# Modules under $DEV_ADDONS (default /opt/weberq-dev/addons) are mounted over
# the ones of the image, to try changes before they are released.
# =============================================================================

set -euo pipefail

PROD_DB=weberq
STAGING_DB=weberq_staging
CONTAINER=weberq-erp-staging
VOLUME=odoo_staging_data
KEEP_DB=false
[ "${1:-}" = "--keep-db" ] && { KEEP_DB=true; shift; }
IMAGE="${1:-$(docker inspect -f '{{.Config.Image}}' weberq-erp)}"
DEV_ADDONS="${DEV_ADDONS:-/opt/weberq-dev/addons}"
log() { echo "$(date -u '+%T') [staging] $*"; }

env_of_prod() { docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' weberq-erp | sed -n "s/^$1=//p"; }
DB_PASSWORD=$(env_of_prod PASSWORD)

log "stop staging"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

MOUNTS=()
for module in "$DEV_ADDONS"/*/; do
  [ -f "$module/__manifest__.py" ] || continue
  MOUNTS+=(-v "${module%/}:/opt/odoo/custom_addons/$(basename "$module"):ro")
  log "dev module $(basename "$module")"
done

run_staging() {
  docker run --network web_network --memory 1536m -v "$VOLUME":/var/lib/odoo "${MOUNTS[@]}" \
    -e HOST=odoo-db -e USER=odoo -e PASSWORD="$DB_PASSWORD" -e DB_NAME="$STAGING_DB" \
    -e WORKERS=0 -e MAX_CRON_THREADS=0 "$@"
}

if ! $KEEP_DB; then
  log "copy database $PROD_DB -> $STAGING_DB"
  docker exec odoo-db dropdb -U odoo --if-exists "$STAGING_DB"
  docker exec odoo-db createdb -U odoo "$STAGING_DB"
  docker exec odoo-db sh -c "pg_dump -U odoo -Fc $PROD_DB | pg_restore -U odoo --no-owner -d $STAGING_DB"

  log "copy filestore"
  docker volume create "$VOLUME" >/dev/null
  docker run --rm --user root --entrypoint bash -v odoo_data:/src:ro -v "$VOLUME":/dst "$IMAGE" -c "
    rm -rf /dst/filestore/$STAGING_DB /dst/sessions && mkdir -p /dst/filestore &&
    cp -a /src/filestore/$PROD_DB /dst/filestore/$STAGING_DB && chown -R odoo:odoo /dst"

  log "neutralize"
  run_staging --rm "$IMAGE" neutralize --config=/etc/odoo/odoo.conf -d "$STAGING_DB" 2>&1 | grep -E "ERROR|neutraliz" || true
fi

log "start $IMAGE"
run_staging -d --name "$CONTAINER" --restart unless-stopped -p 127.0.0.1:18069:8069 \
  "$IMAGE" --config=/etc/odoo/odoo.conf >/dev/null
for i in $(seq 1 40); do
  curl -fsS -m 5 -o /dev/null http://127.0.0.1:18069/web/login 2>/dev/null && { log "up on 127.0.0.1:18069"; exit 0; }
  sleep 3
done
log "staging did not come up"; docker logs --tail 30 "$CONTAINER"; exit 1
