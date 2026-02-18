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

# Public log location 
LOG_DIR="$REPO_DIR/logs"
PUBLIC_LOG="$LOG_DIR/update_scripts.log"
STATE_LOG="$STATE_DIR/state.log"

#
NAME="update_scripts"
OLD_DIR="$LOG_DIR/old/$NAME"


mkdir -p "$OLD_DIR"

mkdir -p "$STATE_DIR" "$LOG_DIR"

ts() { date "+%Y-%m-%d %H:%M:%S"; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

require_repo_access() {
  have_cmd curl || die "curl is required to validate GitHub token/repo access."

  local code
  code="$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GH_OWNER}/${GH_REPO}")"

  case "$code" in
    200) return 0 ;;
    401|403) die "Token is invalid or forbidden (HTTP $code) for ${GH_OWNER}/${GH_REPO}." ;;
    404) die "Repo not found or no access (HTTP 404) for ${GH_OWNER}/${GH_REPO}." ;;
    *) die "Unexpected GitHub API response (HTTP $code) for ${GH_OWNER}/${GH_REPO}." ;;
  esac
}

prompt_repo_and_credentials() {
  read -rp "GitHub repo owner: " GH_OWNER
  read -rp "GitHub repo name: "  GH_REPO

  [[ -n "$GH_OWNER" ]] || die "Repo owner cannot be empty."
  [[ -n "$GH_REPO"  ]] || die "Repo name cannot be empty."

  read -rp "GitHub username: " GH_USER
  read -rsp "GitHub token: " GH_TOKEN
  echo; echo

  [[ -n "$GH_USER"  ]] || die "GitHub username cannot be empty."
  [[ -n "$GH_TOKEN" ]] || die "GitHub token cannot be empty."

  # 1) Validate username+token pairing (fails if username is "wrong")
  require_username_matches_token_owner

  # 2) Validate token has access to repo (private repo support)
  require_repo_access

  # Build remote URL dynamically
  BASE_URL="https://github.com/${GH_OWNER}/${GH_REPO}.git"
  AUTH_URL="https://${GH_USER}:${GH_TOKEN}@github.com/${GH_OWNER}/${GH_REPO}.git"
}

require_username_matches_token_owner() {
  have_cmd curl || die "curl is required to validate GitHub credentials."

  # Get token owner login
  local login
  login="$(
    curl -s \
      -H "Authorization: Bearer $GH_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      https://api.github.com/user \
    | sed -n 's/.*"login":[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n 1
  )"

  [[ -n "$login" ]] || die "Invalid GitHub token (or token expired)."

  # Enforce username/token pairing, but do NOT reveal token owner
  if [[ "$login" != "$GH_USER" ]]; then
    die "Invalid GitHub username/token combination."
  fi
}



log() {
  local level="$1"; shift
  local msg="$*"
  local line
  line="$(ts) [$level] $msg"

  echo "$line" | tee -a "$PUBLIC_LOG" >/dev/null
  echo "$line"
}

die() {
  log "ERROR" "$*"
  exit 1
}

rotate_logs_if_needed() {
  [[ -f "$PUBLIC_LOG" ]] || return 0

  # If log is older than 1 day, rotate it
  if find "$PUBLIC_LOG" -mtime +0 -print -quit | grep -q .; then
    local d archived
    d="$(date +%Y-%m-%d)"
    archived="$LOG_DIR/${NAME}_${d}.log"

    # avoid overwrite if already exists
    if [[ -e "$archived" ]]; then
      archived="$LOG_DIR/${NAME}_${d}_$(date +%H%M%S).log"
    fi

    mv "$PUBLIC_LOG" "$archived"
  fi
}


rotate_logs_if_needed


archive_old_logs() {
  # Zip rotated logs older than 7 days into logs/old/<name>/ and delete originals
  have_cmd zip || die "zip is required to archive logs older than 1 week." # die if zip is missing

  find "$LOG_DIR" -maxdepth 1 -type f -name "${NAME}_*.log" -mtime +7 -print0 \
    | while IFS= read -r -d '' f; do
        base="$(basename "$f" .log)"
        zip_path="$OLD_DIR/${base}.zip"

        # Create zip containing the .log
        zip -j -q "$zip_path" "$f" && rm -f "$f"
      done
}

archive_old_logs

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
  prompt_repo_and_credentials


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
  prompt_repo_and_credentials


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

  # Ask for repo + credentials
  prompt_repo_and_credentials

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
