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
#   ./recover_filestore.sh --apply    Merge them into odoo_data
# =============================================================================

set -euo pipefail

APP_NAME="${APP_NAME:-weberq-erp}"
DATA_VOLUME="${DATA_VOLUME:-odoo_data}"
APPLY=false
[[ "${1:-}" == "--apply" ]] && APPLY=true

docker volume inspect "$DATA_VOLUME" >/dev/null 2>&1 \
  || { echo "Volume $DATA_VOLUME not found. Run a deploy first, it creates the volume."; exit 1; }

# Use the running ERP image so the odoo user and GNU cp are available
IMAGE="$(docker inspect -f '{{.Config.Image}}' "$APP_NAME")"

in_image() {
  docker run --rm --user root --entrypoint bash "$@"
}

found=0
for vol in $(docker volume ls -q -f dangling=true); do
  files=$(in_image -v "$vol":/src:ro "$IMAGE" \
    -c 'if [ -d /src/filestore ]; then find /src/filestore -type f | wc -l; else echo -1; fi')
  [[ "$files" == "-1" ]] && continue
  found=$((found + 1))
  echo "$vol: $files filestore files"
  if $APPLY; then
    in_image -v "$vol":/src:ro -v "$DATA_VOLUME":/dst "$IMAGE" \
      -c 'mkdir -p /dst/filestore && cp -a --update=none /src/filestore/. /dst/filestore/ && chown -R odoo:odoo /dst/filestore'
    echo "  merged into $DATA_VOLUME"
  fi
done

if [[ $found -eq 0 ]]; then
  echo "No dangling volumes with a filestore found."
elif ! $APPLY; then
  echo "Dry run. Re-run with --apply to merge these into $DATA_VOLUME."
fi
