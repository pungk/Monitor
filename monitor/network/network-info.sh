#!/usr/bin/env bash

# network-info.sh
# Network summary script (TUI-ready, modular)
# Author: costin.serbanoiu@gmail.com
# Version: 0.1
# Updated: 18 Feb 2026

#smarter error logging
set -o pipefail

# root check
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run with elevated priviledges."
    echo
    echo "Will exit now"
    exit 1
fi

#use color by default
USE_COLOR=1

#run script with --no-color option
if [[ "${1:-}" == "--no-color" ]]; then
    USE_COLOR=0
fi


#setting text color options
if [[ $USE_COLOR -eq 1 ]]; then
    RED='\033[0;31m' #Red color text
    GREEN='\033[0;32m' #Green color text
    NC='\033[0m' # No Color
    BWHITE='\033[1;37m' #Bold White text
    UWHITE='\033[4;37m' #White underlined text
    UYELLOW='\033[4;33m' #Yellow underlined text
fi

#mix helper functions 
have_cmd() { command -v "$1" >/dev/null 2>&1; }

hr() { printf "%s\n" "------------------------------------------------------------"; }

title() {
  hr
  echo -e "${GREEN}$1${NC}"
  hr
}

section() {
  echo -e "${RED}$1${NC}:"
}

#  Functions 
show_interfaces() {
  section "Interfaces (link state)"
  if have_cmd ip; then
    # concise view: IFACE STATE MAC MTU ...
    ip -br link
  else
    echo "N/A (missing: ip)"
  fi
  echo
}

main() {
  title "Network Summary"
  show_interfaces
}

main "$@"
