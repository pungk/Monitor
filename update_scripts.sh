#!/usr/bin/env bash

# update_scripts.sh
# Force-sync repo from GitHub with interactive credentials
# Adds logging + rollback
# 10 Feb 2026

set -o pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BRANCH="main"
REMOTE_URL="https://github.com/pungk/Monitor.git"

LOG_DIR="$REPO_DIR/logs"
STATE_DIR="$REPO_DIR/state"
LOG_FILE="$LOG_DIR/update_scripts.log"
ROLLBACK_FILE="$STATE_DIR/rollback_commit"

mkdir -p "$LOG_DIR" "$STATE_DIR"

ts() { date "+%Y-%m-%d %H:%M:%S"; }

log() {
  local level="$1"; shift
  local msg="$*"
  echo "$(ts) [$level] $msg" | tee -a "$LOG_FILE"
}

die() {
  log "ERROR" "$*"
  exit 1
}

ensure_repo() {
  cd "$REPO_DIR" || die "Cannot cd to repo dir: $REPO_DIR"
  [[ -d .git ]] || die "Not a git repository: $REPO_DIR"
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
  ensure_repo

  log "INFO" "Starting update to branch '$BRANCH' (FORCE)."
  log "WARN" "This will overwrite ALL local changes and remove untracked files."

  save_rollback_point
  prompt_credentials

  log "INFO" "Fetching from GitHub (interactive authentication)..."
  git fetch "$AUTH_URL" || die "Authentication failed or fetch error."

  log "INFO" "Resetting local branch to fetched HEAD..."
  git reset --hard FETCH_HEAD || die "git reset failed."

  log "INFO" "Removing untracked files..."
  git clean -fd || die "git clean failed."

  log "INFO" "Update complete. Current commit: $(git rev-parse --short HEAD 2>/dev/null || echo UNKNOWN)"
}

do_rollback() {
  ensure_repo

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
  ensure_repo
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
                - Prompts for GitHub username and token
                - Overwrites ALL local changes
                - Saves rollback point

  rollback      Roll back to the commit saved before last update
                - Overwrites ALL local changes

  status        Show current commit and last rollback commit

Options:
  -h, --help    Show this help message

Examples:
  $0
  $0 update
  $0 rollback
  $0 status
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
