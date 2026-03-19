#!/usr/bin/env bash

# common.sh
# Shared helper functions for Monitor scripts

# ---------- Colors ----------
init_colors() {
  USE_COLOR="${USE_COLOR:-1}"

  if [[ "$USE_COLOR" -eq 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    NC='\033[0m'
    BWHITE='\033[1;37m'
    UWHITE='\033[4;37m'
    UYELLOW='\033[4;33m'
  else
    RED=''
    GREEN=''
    NC=''
    BWHITE=''
    UWHITE=''
    UYELLOW=''
  fi
}

# ---------- Helpers ----------
have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

hr() {
  printf "%s\n" "------------------------------------------------------------"
}

title() {
  hr
  echo -e "${GREEN}$1${NC}"
  hr
}

section() {
  echo -e "${RED}$1${NC}:"
}

die() {
  echo -e "${RED}ERROR${NC}: $*" >&2
  exit 1
}

warn() {
  echo -e "${UYELLOW}WARN${NC}: $*"
}

#check if run with root
require_root() {
  if [[ $EUID -ne 0 ]]; then
    die "This script must be run with elevated privileges."
  fi
}

#if command does not exist print N/A and not hang
safe_run() {
  "$@" 2>/dev/null || echo "N/A"
}