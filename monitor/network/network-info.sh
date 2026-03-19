#!/usr/bin/env bash

# network-info.sh
# Network summary script (TUI-ready, modular)
# Author: costin.serbanoiu@gmail.com
# Version: 0.1
# Updated: 18 Feb 2026

# Return non-zero if any command in a pipeline fails
set -o pipefail

#set common.sh location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="$SCRIPT_DIR/../common/common.sh"

if [[ ! -f "$COMMON_LIB" ]]; then
  echo "ERROR: Missing common library: $COMMON_LIB" >&2
  exit 1
fi

#call common.sh
# shellcheck disable=SC1090
source "$COMMON_LIB"

USE_COLOR=1
if [[ "${1:-}" == "--no-color" ]]; then
  USE_COLOR=0
fi

init_colors
require_root

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
    echo -e "  ${GREEN}[OK]${NC} HTTPS to github.com"
  else
    echo -e "  ${RED}[FAIL]${NC} HTTPS to github.com"
    [[ -n "$status_line" ]] && echo -e "    ${UYELLOW}Got${NC}: $status_line"
  fi
else
  echo "  N/A (missing: curl)"
fi

  echo
}

show_listening_ports() {
  section "Listening Services (ports)"

  if have_cmd ss; then
    # -t tcp, -u udp, -l listening, -n numeric, -p process (needs root for full detail)
    ss -tulnp 2>/dev/null \
      | awk 'NR==1{print; next} {print}' \
      | sed -E 's/users:\(\("([^"]+)".*/process=\1/'
    echo
    echo -e "${UYELLOW}Tip${NC}: Run as root for full process names/PIDs (ss -p needs privileges)."
  elif have_cmd netstat; then
    netstat -tulnp 2>/dev/null
    echo
      if [[ $EUID -ne 0 ]]; then
        echo -e "${UYELLOW}Tip${NC}: Run as root for full process names/PIDs."
      fi
  else
    echo "N/A (missing: ss or netstat)"
  fi

  echo
}

show_exposure_summary() {
  section "Exposure Summary"

  if ! have_cmd ss; then
    echo "N/A (missing: ss)"
    echo
    return
  fi

  # parse tcp listeners(most relevant for exposure)
  ss -tlnp 2>/dev/null | awk '
    NR==1 { next }  # skip header
    {
      laddr=$4
      proc=$0

      # extract port from local address (handles IPv6 [::]:443)
      port=local
      sub(/^.*:/, "", port)

      # classify bind
      bind="UNKNOWN"
      if (local ~ /^127\.0\.0\.1:/ || local ~ /^\[::1\]:/) bind="LOCALHOST"
      else if (local ~ /^0\.0\.0\.0:/ || local ~ /^\[::\]:/ || local ~ /^\*:/) bind="PUBLIC"
      else bind="IFACE"

      # extract process name if present
      pname="N/A"
      if (match(proc, /users:\(\("([^"]+)"/, m)) pname=m[1]

      # print
      printf "  %-10s  %-6s  %s\n", bind, port, pname
    }
  ' | sort -u

  echo
  echo -e "${UYELLOW}PUBLIC${NC} = bound to 0.0.0.0/[::]/* (reachable from network)"
  echo -e "${UYELLOW}LOCALHOST${NC} = bound to 127.0.0.1/[::1] (local only)"
  echo
}


show_firewall_status() {
  section "Firewall Status"

  if have_cmd ufw; then
    echo -e "${BWHITE}${UWHITE}UFW${NC}:"
    ufw status 2>/dev/null || echo "Unable to read ufw status"
    echo

  elif have_cmd firewall-cmd; then
    echo -e "${BWHITE}${UWHITE}firewalld${NC}:"
    firewall-cmd --state 2>/dev/null || echo "Unable to determine firewalld state"
    echo

    echo -e "${BWHITE}${UWHITE}Active zones${NC}:"
    firewall-cmd --get-active-zones 2>/dev/null || echo "Unable to read active zones"
    echo

    echo -e "${BWHITE}${UWHITE}Allowed services${NC}:"
    firewall-cmd --list-services 2>/dev/null || echo "Unable to read allowed services"
    echo

    echo -e "${BWHITE}${UWHITE}Allowed ports${NC}:"
    firewall-cmd --list-ports 2>/dev/null || echo "Unable to read allowed ports"
    echo

  elif have_cmd nft; then
    echo -e "${BWHITE}${UWHITE}nftables${NC}:"
    nft list ruleset 2>/dev/null | sed -n '1,80p'
    echo
    echo -e "${UYELLOW}Note${NC}: showing first 80 lines only"
    echo

  elif have_cmd iptables; then
    echo -e "${BWHITE}${UWHITE}iptables${NC}:"
    iptables -S 2>/dev/null | sed -n '1,80p'
    echo
    echo -e "${UYELLOW}Note${NC}: showing first 80 lines only"
    echo

  else
    echo "No supported firewall tool found (ufw / firewalld / nft / iptables)"
    echo
  fi
}

show_gateway_ping() {
  section "Gateway Connectivity"

  if ! have_cmd ip; then
    echo "N/A (missing: ip command)"
    echo
    return
  fi

  local gateway
  gateway=$(ip route show default 2>/dev/null | awk '{print $3; exit}')

  if [[ -z "$gateway" ]]; then
    echo "No default gateway detected"
    echo
    return
  fi

  echo -e "${BWHITE}${UWHITE}Default gateway${NC}: $gateway"

  if have_cmd ping; then
    if ping -c 1 -W 2 "$gateway" >/dev/null 2>&1; then
      echo -e "  ${GREEN}[OK]${NC} Gateway reachable"
    else
      echo -e "  ${RED}[FAIL]${NC} Gateway unreachable"
    fi
  else
    echo "Ping command not available"
  fi

  echo
}

show_public_ip() {
  section "Public IP"

  if ! have_cmd curl; then
    echo "N/A (missing: curl)"
    echo
    return
  fi

  public_ip=""
  public_ip_service=""

  # Try a few providers with short timeouts
  for service in \
    "https://api.ipify.org" \
    "https://ifconfig.me/ip" \
    "https://icanhazip.com"
  do
    public_ip="$(curl -4 -s --max-time 3 --connect-timeout 2 "$service" 2>/dev/null | tr -d '[:space:]')"
    if [[ -n "$public_ip" ]]; then
      public_ip_service="$service"
      break
    fi
  done

  if [[ -n "$public_ip" ]]; then
    echo -e "${BWHITE}${UWHITE}Public IPv4${NC}: $public_ip"
    echo -e "${BWHITE}${UWHITE}Source${NC}: $public_ip_service"
  else
    echo -e "${RED}[FAIL]${NC} Could not determine public IPv4"
  fi

  echo
}

show_interface_stats() {
  section "Interface Traffic Stats"

  if [[ ! -r /proc/net/dev ]]; then
    echo "N/A (/proc/net/dev not readable)"
    echo
    return
  fi

  printf "%-15s %-15s %-15s %-15s %-15s\n" "Interface" "RX_Bytes" "TX_Bytes" "RX_Packets" "TX_Packets"
  printf "%-15s %-15s %-15s %-15s %-15s\n" "---------" "--------" "--------" "----------" "----------"

  awk -F '[: ]+' '
    NR > 2 {
      iface=$2
      rx_bytes=$3
      rx_packets=$4
      tx_bytes=$11
      tx_packets=$12

      # skip empty iface rows
      if (iface != "") {
        printf "%-15s %-15s %-15s %-15s %-15s\n", iface, rx_bytes, tx_bytes, rx_packets, tx_packets
      }
    }
  ' /proc/net/dev

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
  show_gateway_ping
  show_public_ip
  show_listening_ports
  show_exposure_summary  
  show_firewall_status
    show_interface_stats
}
#call main script
main "$@"
