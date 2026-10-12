#!/usr/bin/env bash
# =============================================================================
# WeberQ ERP — Filestore Recovery (run on the VM)
# Before the odoo_data volume existed, every deploy started Odoo on a fresh
# anonymous volume, so attachments uploaded between deploys were stranded in
# now-dangling volumes. This merges the filestore of each of them into
# odoo_data. Filestore files are named by the hash of their content, so a
# no-overwrite copy can never replace one file with a different one.
#
# Usage:
#   ./recover_filestore.sh            List dangling volumes holding a filestore
#   ./recover_filestore.sh --apply    Merge them into odoo_data (created if missing)
# =============================================================================

set -euo pipefail

APP_NAME="${APP_NAME:-weberq-erp}"
DATA_VOLUME="${DATA_VOLUME:-odoo_data}"
APPLY=false
[[ "${1:-}" == "--apply" ]] && APPLY=true

# Run helpers in the ERP image so the odoo user and GNU cp are available: the
# image of the ERP container if there is one, else the newest ERP image
if [[ -z "${IMAGE:-}" ]]; then
  IMAGE="$(docker inspect -f '{{.Config.Image}}' "$APP_NAME" 2>/dev/null || true)"
  [[ -n "$IMAGE" ]] || IMAGE="$(docker images --format '{{.Repository}}:{{.Tag}}' ghcr.io/weberq/weberq-erp | awk 'NR==1')"
fi
[[ -n "$IMAGE" ]] || { echo "No ERP image found. Pull one or set IMAGE=..."; exit 1; }

in_image() {
  docker run --rm --user root --entrypoint bash "$@"
}

found=0
for vol in $(docker volume ls -q -f dangling=true); do
  # The target is dangling too while no container uses it
  [[ "$vol" == "$DATA_VOLUME" ]] && continue
  files=$(in_image -v "$vol":/src:ro "$IMAGE" \
    -c 'if [ -d /src/filestore ]; then find /src/filestore -type f | wc -l; else echo -1; fi')
  [[ "$files" == "-1" ]] && continue
  found=$((found + 1))
  echo "$vol: $files filestore files"
  if $APPLY; then
    # Creates $DATA_VOLUME on first use. Odoo writes sessions next to the
    # filestore, so the volume root must belong to odoo as well.
    in_image -v "$vol":/src:ro -v "$DATA_VOLUME":/dst "$IMAGE" \
      -c 'mkdir -p /dst/filestore && cp -a --update=none /src/filestore/. /dst/filestore/ && chown odoo:odoo /dst && chown -R odoo:odoo /dst/filestore'
    echo "  merged into $DATA_VOLUME"
  fi
done

if [[ $found -eq 0 ]]; then
  echo "No dangling volumes with a filestore found."
elif ! $APPLY; then
  echo "Dry run. Re-run with --apply to merge these into $DATA_VOLUME."
fi
