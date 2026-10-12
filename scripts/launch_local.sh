#!/usr/bin/env bash
# =============================================================================
# WeberQ ERP — Local Launch Script
# Dynamically builds the Odoo addons-path including OCA multi-module repos
# =============================================================================

# Start with the standard Odoo addons paths
ADDONS_PATH="addons,custom_addons"

# Loop through all subdirectories inside custom_addons
for dir in custom_addons/*/; do
    # Strip the trailing slash
    dir=${dir%/}
    
    # If the directory exists AND does *not* contain an Odoo __manifest__.py directly,
    # it means this is a container repository (like an OCA repo) holding multiple modules inside it.
    if [ -d "$dir" ] && [ ! -f "$dir/__manifest__.py" ]; then
        ADDONS_PATH="${ADDONS_PATH},${dir}"
    fi
done

echo "========================================================"
echo "Starting Odoo locally for database: cottonseeds_test"
echo "Auto-updating module: weberq_branding"
echo "Compiled Addons Path:"
echo "  ->  ${ADDONS_PATH}"
echo "========================================================"

# Launch Odoo with the dynamic paths and pass any additional arguments provided
./odoo-bin --addons-path="$ADDONS_PATH" -d cottonseeds_test -u weberq_branding "$@"
