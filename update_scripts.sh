#!/usr/bin/env bash

# update_scripts.sh
# Force-sync local repository with GitHub (interactive auth)
# Overwrites all local changes
# 08 Feb 2026

set -o pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
REMOTE="origin"
BRANCH="main"

cd "$REPO_DIR" || exit 1

# Verify git repo
if [[ ! -d .git ]]; then
    echo "ERROR: This directory is not a git repository."
    exit 1
fi

echo "This will overwrite ALL local changes."
echo

# Force git to prompt for credentials
export GIT_TERMINAL_PROMPT=1
export GIT_ASKPASS=

# Disable credential helpers for this run
git config --local --unset-all credential.helper 2>/dev/null

echo "Fetching from GitHub..."
git fetch "$REMOTE" || {
    echo "ERROR: Authentication failed or fetch error."
    exit 1
}

echo "Resetting local branch to $REMOTE/$BRANCH..."
git reset --hard "$REMOTE/$BRANCH"

echo "Removing untracked files..."
git clean -fd

echo
echo "Sync complete."
