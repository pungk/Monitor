#!/usr/bin/env bash

# update_scripts.sh
# Force-sync repo from GitHub with interactive credentials
# Overwrites all local changes

set -o pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BRANCH="main"
REMOTE_URL="https://github.com/pungk/Monitor.git"

cd "$REPO_DIR" || exit 1

if [[ ! -d .git ]]; then
    echo "ERROR: Not a git repository."
    exit 1
fi

echo "This will overwrite ALL local changes."
echo

# --- FORCE INTERACTIVE AUTH ---
read -rp "GitHub username: " GH_USER
read -rsp "GitHub token: " GH_TOKEN
echo
echo

AUTH_URL="https://${GH_USER}:${GH_TOKEN}@github.com/pungk/Monitor.git"

echo "Fetching from GitHub..."
git fetch "$AUTH_URL" || {
    echo "ERROR: Authentication failed."
    exit 1
}

echo "Resetting local branch..."
git reset --hard FETCH_HEAD

echo "Removing untracked files..."
git clean -fd

echo
echo "Sync complete."
