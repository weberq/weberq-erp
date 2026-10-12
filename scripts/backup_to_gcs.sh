#!/usr/bin/env bash
# =============================================================================
# WeberQ ERP — Off-site Backup
# Dumps the Odoo database and its filestore, checks the dump is readable and
# uploads both to Cloud Storage. Runs on the VM as root (cron); the VM's
# service account writes to the bucket.
#
# Layout:  <BUCKET>/daily/YYYY-MM-DD/<timestamp>/   kept KEEP_DAYS days
#          <BUCKET>/monthly/YYYY-MM/                first backup of each month,
#                                                   kept KEEP_MONTHS months
#          <BUCKET>/LATEST                          where the last good one is
#
# Install on the VM:
#   sudo install -m 750 scripts/backup_to_gcs.sh /usr/local/sbin/weberq-erp-backup
#   echo '30 20 * * * root /usr/local/sbin/weberq-erp-backup >> /var/log/weberq-erp-backup.log 2>&1' \
#     | sudo tee /etc/cron.d/weberq-erp-backup
#
# Usage: weberq-erp-backup [database]          (default: weberq)
# =============================================================================

set -euo pipefail
export PATH="/snap/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

DB="${1:-weberq}"
BUCKET="${BUCKET:-gs://weberq-db-backups/weberqerp}"
KEEP_DAYS="${KEEP_DAYS:-30}"
KEEP_MONTHS="${KEEP_MONTHS:-13}"
DB_CONTAINER="${DB_CONTAINER:-odoo-db}"
DATA_VOLUME="${DATA_VOLUME:-odoo_data}"

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
DAY=$(date -u +%Y-%m-%d)
MONTH=$(date -u +%Y-%m)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
log() { echo "$(date -u '+%F %T') [backup] $*"; }

log "database $DB"
docker exec "$DB_CONTAINER" pg_dump -U odoo -Fc "$DB" > "$WORK/$DB.dump"
TABLES=$(docker exec -i "$DB_CONTAINER" pg_restore -l < "$WORK/$DB.dump" | grep -c "TABLE DATA" || true)
[ "$TABLES" -gt 0 ] || { log "dump has no table data, aborting"; exit 1; }

FILESTORE="$(docker volume inspect -f '{{.Mountpoint}}' "$DATA_VOLUME")/filestore/$DB"
if [ -d "$FILESTORE" ]; then
  tar -C "$FILESTORE" -czf "$WORK/$DB-filestore.tar.gz" .
else
  log "no filestore at $FILESTORE"
fi
(cd "$WORK" && sha256sum ./* > SHA256SUMS)
log "dump $(du -h "$WORK/$DB.dump" | cut -f1) ($TABLES tables), filestore $(du -h "$WORK/$DB-filestore.tar.gz" 2>/dev/null | cut -f1 || echo none)"

DEST="$BUCKET/daily/$DAY/$STAMP"
gcloud storage cp --quiet "$WORK"/* "$DEST/"
if ! gcloud storage ls "$BUCKET/monthly/$MONTH/" >/dev/null 2>&1; then
  gcloud storage cp --quiet "$WORK"/* "$BUCKET/monthly/$MONTH/"
  log "monthly copy $MONTH"
fi
printf '%s\n%s\n' "$DEST" "$STAMP" | gcloud storage cp --quiet - "$BUCKET/LATEST"
log "uploaded to $DEST"

# Retention, by the dates in the object paths
CUTOFF_DAY=$(date -u -d "-$KEEP_DAYS days" +%Y-%m-%d)
CUTOFF_MONTH=$(date -u -d "-$KEEP_MONTHS months" +%Y-%m)
for dir in $(gcloud storage ls "$BUCKET/daily/" 2>/dev/null); do
  d=$(basename "$dir")
  if [[ "$d" < "$CUTOFF_DAY" ]]; then gcloud storage rm -r --quiet "$dir"; log "expired $d"; fi
done
for dir in $(gcloud storage ls "$BUCKET/monthly/" 2>/dev/null); do
  m=$(basename "$dir")
  if [[ "$m" < "$CUTOFF_MONTH" ]]; then gcloud storage rm -r --quiet "$dir"; log "expired $m"; fi
done
log "done"
