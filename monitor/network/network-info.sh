#!/usr/bin/env bash

# network-info.sh
# Network summary script (TUI-ready, modular)
# Author: costin.serbanoiu@gmail.com
# Version: 0.1
# Updated: 18 Feb 2026

#smarter error logging-if any command in a pipe fails it logs it 
#not just the last pipe 
#it returns exit status in $? (echo $?) (above 128)
#to debug exitcode do "echo $(($?-128))" and then "trap -l" to list all signals
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
    ip -br link
  else
    echo "N/A (missing: ip)"
  fi
  echo
}

get_primary_iface() {
  # interface used for default route (best guess)
  if have_cmd ip; then
    ip route show default 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}'
  fi
}


show_ip_addresses() {
  local primary
  primary="$(get_primary_iface)"
  section "IP Addresses"
  if [[ -n "$primary" ]]; then
    echo -e "${BWHITE}${UWHITE}Primary interface${NC}: $primary"
  else
    echo -e "${BWHITE}${UWHITE}Primary interface${NC}: N/A"
  fi
  echo

  if have_cmd ip; then
    echo -e "${BWHITE}${UWHITE}IPv4 (per interface)${NC}:"
    ip -br -4 addr
    echo

    echo -e "${BWHITE}${UWHITE}IPv6 (per interface)${NC}:"
    ip -br -6 addr
  else
    echo "N/A (missing: ip)"
  fi
  echo
}

show_routes() {
  section "Routing"
  if have_cmd ip; then
    local gw iface
    gw="$(ip route show default 2>/dev/null | awk '{print $3; exit}')"
    iface="$(ip route show default 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"

    echo -e "${BWHITE}${UWHITE}Default route${NC}:"
    if ip route show default >/dev/null 2>&1; then
      ip route show default
    else
      echo "N/A"
    fi
    echo

    echo -e "${BWHITE}${UWHITE}Gateway${NC}: ${gw:-N/A}"
    echo -e "${BWHITE}${UWHITE}Gateway interface${NC}: ${iface:-N/A}"
    echo

    echo -e "${BWHITE}${UWHITE}Route table (summary)${NC}:"
    ip route
  else
    echo "N/A (missing: ip)"
  fi
  echo
}

show_dns() {
  section "DNS"
  echo -e "${BWHITE}${UWHITE}/etc/resolv.conf${NC}:"
  if [[ -r /etc/resolv.conf ]]; then
    # show nameserver/search/options
    grep -E '^(nameserver|search|options)\b' /etc/resolv.conf 2>/dev/null || cat /etc/resolv.conf
  else
    echo "N/A"
  fi
  echo

  # If systemd-resolved is in use, /etc/resolv.conf may point to stub.
  if have_cmd resolvectl; then
    echo -e "${BWHITE}${UWHITE}resolvectl status (summary)${NC}:"
    # shortening output
    resolvectl status 2>/dev/null | sed -n '1,120p'
    echo
  elif have_cmd systemd-resolve; then
    echo -e "${BWHITE}${UWHITE}systemd-resolve --status (summary)${NC}:"
    systemd-resolve --status 2>/dev/null | sed -n '1,120p'
    echo
  fi

  echo -e "${BWHITE}${UWHITE}DNS resolution test${NC}:"
  dns_test "github.com"
  dns_test "google.com"
  echo
}

dns_test() {
  local host="$1"
  local result=""

  if have_cmd getent; then
    result="$(getent ahosts "$host" 2>/dev/null | awk '{print $1}' | head -n 1)"
  elif have_cmd dig; then
    result="$(dig +time=2 +tries=1 +short "$host" 2>/dev/null | head -n 1)"
  elif have_cmd nslookup; then
    result="$(nslookup -timeout=2 "$host" 2>/dev/null | awk '/^Address: /{print $2; exit}')"
  fi

  if [[ -n "$result" ]]; then
    echo -e "  ${GREEN}[OK]${NC} $host -> $result"
  else
    echo -e "  ${RED}[FAIL]${NC} $host (cannot resolve)"
  fi
}

show_connectivity() {
  section "Connectivity"

  # --- Ping test (ICMP) ---
  if have_cmd ping; then
    if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
      echo -e "  ${GREEN}[OK]${NC} ICMP to 1.1.1.1"
    else
      echo -e "  ${RED}[FAIL]${NC} ICMP to 1.1.1.1"
    fi
  else
    echo "  N/A (missing: ping)"
  fi

# --- HTTPS test ---
if have_cmd curl; then
  status_line="$(curl -Is --max-time 3 --connect-timeout 2 https://github.com 2>/dev/null | head -n 1)"
  if echo "$status_line" | grep -qiE '^HTTP/([0-9]+\.[0-9]+|2|3)[[:space:]]+[23][0-9]{2}'; then
    echo -e "  ${GREEN}[OK]${NC} HTTPS to github.com ($status_line)"
  else
    echo -e "  ${RED}[FAIL]${NC} HTTPS to github.com"
    [[ -n "$status_line" ]] && echo -e "    ${UYELLOW}Got${NC}: $status_line"
  fi
else
  echo "  N/A (missing: curl)"
fi

  echo
}

#main script
main() {
  title "Network Summary"
  show_interfaces
  show_ip_addresses
  show_routes
  show_dns
  show_connectivity
}
#call main script
main "$@"
