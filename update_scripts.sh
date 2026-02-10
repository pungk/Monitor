#!/usr/bin/env bash

# update_scripts.sh
# Force-sync repo from GitHub with interactive credentials
# Adds logging + rollback (rollback survives git clean)
# 10 Feb 2026

set -o pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BRANCH="main"

cd "$REPO_DIR" || exit 1

if [[ ! -d .git ]]; then
  echo "ERROR: Not a git repository."
  exit 1
fi

# Store state inside .git so git clean won't delete it
STATE_DIR="$REPO_DIR/.git/monitor_state"

LOG_DIR="$REPO_DIR/logs"
ROLLBACK_FILE="$STATE_DIR/rollback_commit"

STATE_LOG="$STATE_DIR/state.log"
PUBLIC_LOG="$LOG_DIR/update_scripts.log"

mkdir -p "$STATE_DIR" "$LOG_DIR"

ts() { date "+%Y-%m-%d %H:%M:%S"; }


rotate_logs_if_needed() {
  # If log file is older than 1 day, archive it
  local archive_date
  archive_date="$(date +%Y-%m-%d)"

  for f in "$STATE_LOG" "$PUBLIC_LOG"; do
    if [[ -f "$f" ]] && find "$f" -mtime +0 -print -quit | grep -q .; then
      local dir base archived
      dir="$(dirname "$f")"
      base="$(basename "$f" .log)"
      archived="$dir/${base}_$archive_date.log"
      mv "$f" "$archived"
    fi
  done
}

rotate_logs_if_needed

log() {
  local level="$1"; shift
  local msg="$*"
  echo "$(ts) [$level] $msg" | tee -a "$STATE_LOG" "$PUBLIC_LOG" >/dev/null
  echo "$(ts) [$level] $msg"
}

die() {
  log "ERROR" "$*"
  exit 1
}

prompt_credentials() {
  read -rp "GitHub username: " GH_USER
  read -rsp "GitHub token: " GH_TOKEN
  echo
  echo
  AUTH_URL="https://${GH_USER}:${GH_TOKEN}@github.com/pungk/Monitor.git"
}

save_rollback_point() {
  local commit
  commit="$(git rev-parse --verify HEAD 2>/dev/null)" || die "Cannot determine current commit (no HEAD?)"
  echo "$commit" > "$ROLLBACK_FILE"
  log "INFO" "Saved rollback commit: $commit"
}


do_update() {
  log "INFO" "Starting update to branch '$BRANCH' (FORCE)."
  log "WARN" "This will overwrite ALL local changes and remove untracked files."

  save_rollback_point
  prompt_credentials

  log "INFO" "Fetching from GitHub (interactive authentication)..."
  git fetch "$AUTH_URL" || die "Authentication failed or fetch error."

  log "INFO" "Resetting local branch to fetched HEAD..."
  git reset --hard FETCH_HEAD || die "git reset failed."

  log "INFO" "Removing untracked files (excluding .git)..."
  git clean -fd -e logs/ || die "git clean failed."

  log "INFO" "Update complete. Current commit: $(git rev-parse --short HEAD 2>/dev/null || echo UNKNOWN)"
}

do_rollback() {
  [[ -f "$ROLLBACK_FILE" ]] || die "No rollback point found (run update first)."
  local target
  target="$(cat "$ROLLBACK_FILE")"
  [[ -n "$target" ]] || die "Rollback file is empty."

  log "WARN" "Rolling back to commit: $target"
  log "WARN" "This will overwrite ALL local changes and remove untracked files."

  git cat-file -e "$target^{commit}" 2>/dev/null || die "Rollback commit not found locally."

  git reset --hard "$target" || die "Rollback reset failed."
  git clean -fd || die "Rollback clean failed."

  log "INFO" "Rollback complete. Current commit: $(git rev-parse --short HEAD 2>/dev/null || echo UNKNOWN)"
}

do_status() {
  local cur rb
  cur="$(git rev-parse --short HEAD 2>/dev/null || echo UNKNOWN)"
  rb="$(cat "$ROLLBACK_FILE" 2>/dev/null || echo NONE)"
  echo "Repository status:"
  echo "  Current commit : $cur"
  echo "  Rollback point : $rb"
  echo "  Log file       : $LOG_FILE"
}

usage() {
  cat <<EOF
Usage:
  $0 [command]

Commands:
  update        Force-sync repository from GitHub 
  rollback      Roll back to the commit saved before last update
  status        Show current commit and rollback point

Options:
  -h, --help    Show this help message
EOF
}

case "${1:-update}" in
  update|"")
    do_update
    ;;
  rollback)
    do_rollback
    ;;
  status)
    do_status
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unknown command: $1"
    echo
    usage
    exit 2
    ;;
esac
