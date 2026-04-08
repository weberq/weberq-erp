#!/usr/bin/env bash
# =============================================================================
# WeberQ ERP - Submodule Manager
# Reads from submodules.manifest.json and manages git submodules in custom_addons/
#
# Usage:
#   ./scripts/submodules.sh <command> [submodule_name]
#
# Commands:
#   init      - Register + initialize all enabled submodules (first-time setup)
#   pull      - Pull latest changes for all (or a specific) enabled submodule
#   update    - Sync .gitmodules from manifest, then pull (full reconcile)
#   status    - Show status of all submodules
#   add <name> <repo> [branch] [desc]
#             - Add a new submodule entry to the manifest and initialize it
#   help      - Show this help message
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${PROJECT_ROOT}/submodules.manifest.json"

# ─── Color helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[info]${RESET}  $*"; }
success() { echo -e "${GREEN}[ok]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[warn]${RESET}  $*"; }
error()   { echo -e "${RED}[error]${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}${CYAN}══ $* ══${RESET}"; }

# ─── Dependency check ────────────────────────────────────────────────────────
require() {
  for cmd in "$@"; do
    command -v "$cmd" &>/dev/null || { error "Required command not found: $cmd"; exit 1; }
  done
}
require git jq

# ─── Manifest helpers ────────────────────────────────────────────────────────
check_manifest() {
  [[ -f "$MANIFEST" ]] || { error "Manifest not found: $MANIFEST"; exit 1; }
}

get_enabled_submodules() {
  jq -c '.submodules[] | select(.enabled == true)' "$MANIFEST"
}

get_submodule_by_name() {
  local name="$1"
  jq -c --arg name "$name" '.submodules[] | select(.name == $name)' "$MANIFEST"
}

# ─── Commands ────────────────────────────────────────────────────────────────

cmd_init() {
  local target="${1:-}"
  check_manifest
  header "Initializing submodules"

  cd "$PROJECT_ROOT"

  while IFS= read -r entry; do
    local name repo path branch
    name=$(echo "$entry"   | jq -r '.name')
    repo=$(echo "$entry"   | jq -r '.repo')
    path=$(echo "$entry"   | jq -r '.path')
    branch=$(echo "$entry" | jq -r '.branch // "main"')

    [[ -n "$target" && "$name" != "$target" ]] && continue

    info "Submodule: ${BOLD}$name${RESET} → $repo ($branch)"

    # Register in .gitmodules if not already present
    if ! git config --file .gitmodules --get "submodule.${path}.url" &>/dev/null; then
      git submodule add -b "$branch" "$repo" "$path"
      success "Added submodule: $name"
    else
      info "Already registered, initializing..."
      git submodule update --init --recursive -- "$path"
    fi

    # Ensure we're on the correct branch
    if [[ -d "$path" ]]; then
      git -C "$path" checkout "$branch" 2>/dev/null || warn "Could not switch to branch '$branch' for $name"
    fi
  done < <(get_enabled_submodules)

  success "Init complete."
}

cmd_pull() {
  local target="${1:-}"
  check_manifest
  header "Pulling latest changes"

  cd "$PROJECT_ROOT"

  while IFS= read -r entry; do
    local name path branch
    name=$(echo "$entry"   | jq -r '.name')
    path=$(echo "$entry"   | jq -r '.path')
    branch=$(echo "$entry" | jq -r '.branch // "main"')

    [[ -n "$target" && "$name" != "$target" ]] && continue

    if [[ ! -e "${PROJECT_ROOT}/${path}/.git" ]]; then
      warn "Submodule not initialized: $name. Run 'init' first."
      continue
    fi

    info "Pulling ${BOLD}$name${RESET} (branch: $branch)..."
    git -C "${PROJECT_ROOT}/${path}" fetch origin
    git -C "${PROJECT_ROOT}/${path}" checkout "$branch"
    git -C "${PROJECT_ROOT}/${path}" pull origin "$branch"
    success "$name is up to date."
  done < <(get_enabled_submodules)

  success "Pull complete."
}

cmd_update() {
  local target="${1:-}"
  check_manifest
  header "Updating submodules (sync manifest → .gitmodules → pull)"

  cd "$PROJECT_ROOT"

  # Reconcile .gitmodules with manifest for all enabled submodules
  while IFS= read -r entry; do
    local name repo path branch
    name=$(echo "$entry"   | jq -r '.name')
    repo=$(echo "$entry"   | jq -r '.repo')
    path=$(echo "$entry"   | jq -r '.path')
    branch=$(echo "$entry" | jq -r '.branch // "main"')

    [[ -n "$target" && "$name" != "$target" ]] && continue

    if ! git config --file .gitmodules --get "submodule.${path}.url" &>/dev/null; then
      info "Registering missing submodule: $name"
      git submodule add -b "$branch" "$repo" "$path" || true
    fi
  done < <(get_enabled_submodules)

  git submodule sync
  cmd_pull "$target"
}

cmd_status() {
  check_manifest
  header "Submodule Status"

  cd "$PROJECT_ROOT"

  printf "\n%-25s %-45s %-12s %-10s %s\n" "NAME" "REPO" "BRANCH" "ENABLED" "STATUS"
  printf '%.0s─' {1..120}; echo

  while IFS= read -r entry; do
    local name repo path branch enabled
    name=$(echo "$entry"    | jq -r '.name')
    repo=$(echo "$entry"    | jq -r '.repo')
    path=$(echo "$entry"    | jq -r '.path')
    branch=$(echo "$entry"  | jq -r '.branch // "main"')
    enabled=$(echo "$entry" | jq -r '.enabled')

    local status_str
    if [[ ! -e "${PROJECT_ROOT}/${path}/.git" ]]; then
      status_str="${RED}NOT INITIALIZED${RESET}"
    else
      local current_branch current_commit
      current_branch=$(git -C "${PROJECT_ROOT}/${path}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
      current_commit=$(git -C "${PROJECT_ROOT}/${path}" rev-parse --short HEAD 2>/dev/null || echo "?")
      local dirty=""
      git -C "${PROJECT_ROOT}/${path}" diff --quiet 2>/dev/null || dirty=" ${YELLOW}(dirty)${RESET}"
      status_str="${GREEN}${current_branch}@${current_commit}${RESET}${dirty}"
    fi

    local enabled_str
    [[ "$enabled" == "true" ]] && enabled_str="${GREEN}yes${RESET}" || enabled_str="${RED}no${RESET}"

    printf "%-25s %-45s %-12s %-10b %b\n" "$name" "$(basename "$repo" .git)" "$branch" "$enabled_str" "$status_str"
  done < <(jq -c '.submodules[]' "$MANIFEST")

  echo
}

cmd_add() {
  local name="${1:-}"
  local repo="${2:-}"
  local branch="${3:-main}"
  local desc="${4:-}"

  [[ -z "$name" || -z "$repo" ]] && {
    error "Usage: $0 add <name> <repo_url> [branch] [description]"
    exit 1
  }

  check_manifest

  # Check for duplicates
  local existing
  existing=$(get_submodule_by_name "$name")
  if [[ -n "$existing" ]]; then
    error "Submodule '$name' already exists in manifest."
    exit 1
  fi

  local path
  path="custom_addons/${name}"

  info "Adding '${name}' to manifest..."

  # Append to manifest using jq
  local tmp
  tmp=$(mktemp)
  jq --arg name "$name" \
     --arg repo "$repo" \
     --arg path "$path" \
     --arg branch "$branch" \
     --arg desc "$desc" \
     '.submodules += [{
       "name": $name,
       "repo": $repo,
       "path": $path,
       "branch": $branch,
       "description": $desc,
       "enabled": true
     }]' "$MANIFEST" > "$tmp" && mv "$tmp" "$MANIFEST"

  success "Added '$name' to manifest."

  # Now initialize it
  cmd_init "$name"
}

cmd_help() {
  echo -e "
${BOLD}WeberQ ERP — Submodule Manager${RESET}
Manifest: submodules.manifest.json

${BOLD}Usage:${RESET}
  ./scripts/submodules.sh <command> [options]

${BOLD}Commands:${RESET}
  ${CYAN}init${RESET}   [name]              Initialize all (or one) enabled submodule(s)
  ${CYAN}pull${RESET}   [name]              Pull latest from remote for all (or one)
  ${CYAN}update${RESET} [name]              Sync manifest → .gitmodules, then pull
  ${CYAN}status${RESET}                     Show status of all submodules
  ${CYAN}add${RESET}    <name> <repo> [branch] [desc]
                              Add a new submodule to manifest and init it
  ${CYAN}help${RESET}                       Show this message

${BOLD}Examples:${RESET}
  ./scripts/submodules.sh init
  ./scripts/submodules.sh pull weberq_branding
  ./scripts/submodules.sh add weberq_helpdesk git@github.com:weberq/erp_helpdesk.git main \"Helpdesk module\"
  ./scripts/submodules.sh status
"
}

# ─── Entry point ─────────────────────────────────────────────────────────────
COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
  init)   cmd_init   "${1:-}" ;;
  pull)   cmd_pull   "${1:-}" ;;
  update) cmd_update "${1:-}" ;;
  status) cmd_status ;;
  add)    cmd_add    "$@" ;;
  help|--help|-h) cmd_help ;;
  *)
    error "Unknown command: $COMMAND"
    cmd_help
    exit 1
    ;;
esac
