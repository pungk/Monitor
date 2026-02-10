#!/usr/bin/env bash

# update_scripts.sh
# Force-sync local repository with GitHub
# Overwrites all local changes
# 08 Feb 2026

set -o pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BRANCH="main"
REMOTE="origin"

echo "Syncing repository from GitHub..."
echo "Repository: $REPO_DIR"
echo "Remote: $REMOTE"
echo "Branch: $BRANCH"
echo

cd "$REPO_DIR" || {
    echo "ERROR: Cannot access repository directory"
    exit 1
}

# Make sure this is a git repo
if [[ ! -d .git ]]; then
    echo "ERROR: This directory is not a git repository."
    exit 1
fi

echo "Fetching latest changes..."
git fetch --all --prune

echo "Resetting local branch to $REMOTE/$BRANCH..."
git reset --hard "$REMOTE/$BRANCH"

echo "Removing untracked files..."
git clean -fd

echo
echo "Sync complete."
echo "Repository is now identical to $REMOTE/$BRANCH"