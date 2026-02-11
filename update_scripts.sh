#!/usr/bin/env bash

# update_scripts.sh
# Force-sync repo from GitHub with interactive credentials
# Logging + rollback (rollback survives git clean)
# 10 Feb 2026

set -o pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BRANCH="main"
REMOTE_NAME="${REMOTE_NAME:-origin}"

cd "$REPO_DIR" || exit 1

if [[ ! -d .git ]]; then
  echo "ERROR: Not a git repository."
  exit 1
fi

# Store rollback/state inside .git so git clean -fd won't delete it
STATE_DIR="$REPO_DIR/.git/monitor_state"
ROLLBACK_FILE="$STATE_DIR/rollback_commit"

# Public log location (we exclude logs/ from git clean)
LOG_DIR="$REPO_DIR/logs"
PUBLIC_LOG="$LOG_DIR/update_scripts.log"
STATE_LOG="$STATE_DIR/state.log"

mkdir -p "$STATE_DIR" "$LOG_DIR"

ts() { date "+%Y-%m-%d %H:%M:%S"; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

log() {
  local level="$1"; shift
  local msg="$*"
  local line
  line="$(ts) [$level] $msg"

  echo "$line" | tee -a "$PUBLIC_LOG" >/dev/null
  echo "$line"
}

require_valid_github_identity() {
  have_cmd curl || die "curl is required to validate GitHub credentials."

  # Validate token and get username
  local response login
  response="$(curl -s \
    -H "Authorization: Bearer $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    https://api.github.com/user)"

  login="$(echo "$response" | sed -n 's/.*"login":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"

  if [[ -z "$login" ]]; then
    die "GitHub token validation failed (invalid or expired token)."
  fi

  if [[ "$login" != "$GH_USER" ]]; then
    die "GitHub username '$GH_USER' does not match token owner '$login'."
  fi
}

die() {
  log "ERROR" "$*"
  exit 1
}

rotate_logs_if_needed() {
  local archive_date
  archive_date="$(date +%Y-%m-%d)"

  if [[ -f "$PUBLIC_LOG" ]] && find "$PUBLIC_LOG" -mtime +0 -print -quit | grep -q .; then
    local archived
    archived="$LOG_DIR/update_scripts_$archive_date.log"
    mv "$PUBLIC_LOG" "$archived"
  fi
}

rotate_logs_if_needed

get_remote_https_url() {
  # Returns an HTTPS URL like: https://github.com/user/repo.git
  local url
  url="$(git remote get-url "$REMOTE_NAME" 2>/dev/null)" || return 1

  # If already https://... keep it
  if [[ "$url" =~ ^https?:// ]]; then
    echo "$url"
    return 0
  fi

  # Convert SSH forms:
  # git@github.com:user/repo.git  -> https://github.com/user/repo.git
  # ssh://git@github.com/user/repo.git -> https://github.com/user/repo.git
  url="$(echo "$url" \
    | sed -E 's#^ssh://git@github.com/#https://github.com/#' \
    | sed -E 's#^git@github.com:#https://github.com/#')"

  if [[ "$url" =~ ^https://github\.com/ ]]; then
    echo "$url"
    return 0
  fi

  return 1
}

prompt_credentials_and_build_auth_url() {
  read -rp "GitHub username: " GH_USER
  read -rsp "GitHub token: " GH_TOKEN
  echo
  echo

  [[ -n "$GH_USER" ]]  || die "GitHub username cannot be empty."
  [[ -n "$GH_TOKEN" ]] || die "GitHub token cannot be empty."

  require_valid_github_identity

  local base_url
  base_url="$(get_remote_https_url)" || die "Cannot determine HTTPS remote URL."

  AUTH_URL="$(echo "$base_url" | sed -E "s#^https://#https://${GH_USER}:${GH_TOKEN}@#")"
}

save_rollback_point() {
  local commit
  commit="$(git rev-parse --verify HEAD 2>/dev/null)" || die "Cannot determine current commit (no HEAD?)"
  echo "$commit" > "$ROLLBACK_FILE"
  log "INFO" "Saved rollback commit: $commit"
}

do_update() {
  log "INFO" "Command: update"
  log "INFO" "Starting update to branch '$BRANCH' (FORCE)."
  log "WARN" "This will overwrite ALL local changes and remove untracked files."

  save_rollback_point
  prompt_credentials_and_build_auth_url

  log "INFO" "Fetching from GitHub (interactive authentication)..."

  # Force git to use ONLY the provided creds (no helpers, no prompts)
  FETCH_OUT="$(
    GIT_TERMINAL_PROMPT=0 \
    GIT_ASKPASS=/bin/false \
    git -c credential.helper= -c core.askPass= \
      fetch "$AUTH_URL" 2>&1
  )"
  FETCH_RC=$?

  if [[ $FETCH_RC -ne 0 ]]; then
    log "ERROR" "Fetch failed (bad token / network / URL)."
    log "ERROR" "$FETCH_OUT"
    exit 1
  fi

  log "INFO" "$FETCH_OUT"

  log "INFO" "Resetting local branch to fetched HEAD..."
  RESET_OUT="$(git reset --hard FETCH_HEAD 2>&1)" || { log "ERROR" "$RESET_OUT"; die "git reset failed."; }
  log "INFO" "$RESET_OUT"

  log "INFO" "Removing untracked files (excluding .git and logs/)..."
  CLEAN_OUT="$(git clean -fd -e logs/ 2>&1)" || { log "ERROR" "$CLEAN_OUT"; die "git clean failed."; }
  [[ -n "$CLEAN_OUT" ]] && log "INFO" "$CLEAN_OUT"

  log "INFO" "Update complete. Current commit: $(git rev-parse --short HEAD 2>/dev/null || echo UNKNOWN)"
}

do_rollback() {
  log "INFO" "Command: rollback"

  [[ -f "$ROLLBACK_FILE" ]] || die "No rollback point found (run update first)."

  local target
  target="$(cat "$ROLLBACK_FILE")"
  [[ -n "$target" ]] || die "Rollback file is empty."

  log "WARN" "Rolling back to commit: $target"
  log "WARN" "This will overwrite ALL local changes and remove untracked files."

  #ask auth for github
  prompt_credentials_and_build_auth_url

  log "INFO" "Fetching from GitHub before rollback (interactive authentication)..."
  FETCH_OUT="$(
    GIT_TERMINAL_PROMPT=0 \
    GIT_ASKPASS=/bin/false \
    git -c credential.helper= -c core.askPass= \
      fetch "$AUTH_URL" 2>&1
  )"
  FETCH_RC=$?

  if [[ $FETCH_RC -ne 0 ]]; then
    log "ERROR" "Fetch failed (bad token / network / URL). Rollback aborted."
    log "ERROR" "$FETCH_OUT"
    exit 1
  fi
  log "INFO" "$FETCH_OUT"

  #rollback locally
  git cat-file -e "$target^{commit}" 2>/dev/null || die "Rollback commit not found locally (even after fetch): $target"

  RESET_OUT="$(git reset --hard "$target" 2>&1)" || { log "ERROR" "$RESET_OUT"; die "Rollback reset failed."; }
  log "INFO" "$RESET_OUT"

  CLEAN_OUT="$(git clean -fd -e logs/ 2>&1)" || { log "ERROR" "$CLEAN_OUT"; die "Rollback clean failed."; }
  [[ -n "$CLEAN_OUT" ]] && log "INFO" "$CLEAN_OUT"

  log "INFO" "Rollback complete. Current commit: $(git rev-parse --short HEAD 2>/dev/null || echo UNKNOWN)"
}

do_status() {
  log "INFO" "Command: status"
  local cur rb
  cur="$(git rev-parse --short HEAD 2>/dev/null || echo UNKNOWN)"
  rb="$(cat "$ROLLBACK_FILE" 2>/dev/null || echo NONE)"
  echo "Repository status:"
  echo "  Current commit : $cur"
  echo "  Rollback point : $rb"
  echo "  Log file       : $PUBLIC_LOG"
  echo "  Rollback file  : $ROLLBACK_FILE"
}

usage() {
  cat <<EOF
Usage:
  $0 [command]

Commands:
  update        Force-sync repository from GitHub \
               - prompts for GitHub username and token
               - fails if token is empty/invalid
               - uses current git remote '$REMOTE_NAME' (supports forks/renames)

  rollback      Roll back to the commit saved before last update
  status        Show current commit, rollback point, and log locations

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
