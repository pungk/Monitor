#!/usr/bin/env bash

# storage-info.sh
# Storage summary script
# Author: costin.serbanoiu@gmail.com
# Version: 0.1
# Updated: 19 Feb 2026

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="$SCRIPT_DIR/../common/common.sh"

if [[ ! -f "$COMMON_LIB" ]]; then
    echo "ERROR: Missing common library: $COMMON_LIB" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$COMMON_LIB"

USE_COLOR=1
if [[ "${1:-}" == "--no-color" ]]; then
    USE_COLOR=0
fi

init_colors


# functions

show_block_devices() {
    section "Block Devices"

    if have_cmd lsblk; then
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
    else
        echo "N/A (missing: lsblk)"
    fi

    echo
}

show_mounted_filesystems() {
    section "Mounted Filesystems"

    if have_cmd df; then
        df -hT
    else
        echo "N/A (missing: df)"
    fi

    echo
}

show_usage_warnings() {
    section "Usage Warnings"

    if have_cmd df; then
        local found=0

        # Skip header, use POSIX-ish output for easier parsing
        while read -r filesystem type size used avail usep mountpoint; do
            # strip %
            usep_num="${usep%\%}"

            if [[ "$usep_num" -ge 90 ]]; then
                echo -e "${RED}[CRITICAL]${NC} $mountpoint is ${usep} used ($used / $size)"
                found=1
            elif [[ "$usep_num" -ge 10 ]]; then
                echo -e "${UYELLOW}[WARN]${NC} $mountpoint is ${usep} used ($used / $size)"
                found=1
            fi
        done < <(df -hT --output=source,fstype,size,used,avail,pcent,target 2>/dev/null | tail -n +2)

        if [[ "$found" -eq 0 ]]; then
            echo -e "${GREEN}[OK]${NC} No mounted filesystem is above 80% usage"
        fi
    else
        echo "N/A (missing: df)"
    fi

    echo
}


# build main
main() {
    title "Storage Summary"
    show_block_devices
    show_mounted_filesystems
    show_usage_warnings    
}

# call main
main "$@"