#!/usr/bin/env bash

# storage-info.sh
# Storage summary script
# Author: costin.serbanoiu@gmail.com
# Version: 1.0
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

        while read -r filesystem fstype size used avail usep mountpoint; do
            usep_num="${usep%\%}"

            if [[ "$usep_num" -ge 90 ]]; then
                echo -e "${RED}[CRITICAL]${NC} $mountpoint is ${usep} used ($used / $size)"
                found=1
            elif [[ "$usep_num" -ge 80 ]]; then
                echo -e "${UYELLOW}[WARN]${NC} $mountpoint is ${usep} used ($used / $size)"
                found=1
            fi
        done < <(df -h --output=source,fstype,size,used,avail,pcent,target 2>/dev/null | tail -n +2)

        if [[ "$found" -eq 0 ]]; then
            echo -e "${GREEN}[OK]${NC} No mounted filesystem is above 80% usage"
        fi
    else
        echo "N/A (missing: df)"
    fi

    echo
}

show_physical_disks() {
    section "Physical Disks"

    if have_cmd lsblk; then
        printf "%-12s %-10s %-8s %-10s %-40s\n" "Device" "Size" "Type" "Transport" "Model"
        printf "%-12s %-10s %-8s %-10s %-40s\n" "------" "----" "----" "---------" "-----"

        lsblk -d -P -o NAME,SIZE,MODEL,ROTA,TRAN,TYPE | while read -r line; do
            eval "$line"

            [[ "$TYPE" != "disk" ]] && continue

            disk_type="Unknown"
            if [[ "$ROTA" == "0" ]]; then
                disk_type="SSD"
            elif [[ "$ROTA" == "1" ]]; then
                disk_type="HDD"
            fi

            [[ -z "$TRAN" ]] && TRAN="N/A"
            [[ -z "$MODEL" ]] && MODEL="N/A"

            printf "%-12s %-10s %-8s %-10s %-40s\n" "$NAME" "$SIZE" "$disk_type" "$TRAN" "$MODEL"
        done
    else
        echo "N/A (missing: lsblk)"
    fi

    echo
}

show_top_space_consumers() {
    section "Top Space Consumers (/)"

    if have_cmd du && have_cmd sort && have_cmd head; then
        echo -e "${BWHITE}${UWHITE}Largest directories under / (depth 1)${NC}:"

        du -x -h --max-depth=1 / 2>/dev/null \
            | grep -Ev '^/(proc|sys|run|dev|tmp)$' \
            | sort -hr \
            | head -n 10

        echo
        echo -e "${UYELLOW}Note${NC}: system directories excluded (proc, sys, run, dev, tmp)"
    else
        echo "N/A (missing: du / sort / head)"
        echo
    fi
}

show_inode_usage() {
    section "Inode Usage"

    if have_cmd df; then
        local found=0

        while read -r filesystem inodes iused ifree iuse mountpoint; do
            iuse_num="${iuse%\%}"

            if [[ "$iuse_num" -ge 90 ]]; then
                echo -e "${RED}[CRITICAL]${NC} $mountpoint inode usage is ${iuse}"
                found=1
            elif [[ "$iuse_num" -ge 80 ]]; then
                echo -e "${UYELLOW}[WARN]${NC} $mountpoint inode usage is ${iuse}"
                found=1
            fi
        done < <(df -i --output=source,itotal,iused,iavail,pcent,target 2>/dev/null | tail -n +2)

        if [[ "$found" -eq 0 ]]; then
            echo -e "${GREEN}[OK]${NC} No inode exhaustion detected"
        fi
    else
        echo "N/A (missing: df)"
    fi

    echo
}

show_smart_health() {
    section "Disk Health (SMART)"

    if [[ $EUID -ne 0 ]]; then
        echo "Run as root to see SMART data"
        echo
        return
    fi

    if ! have_cmd smartctl; then
        echo "N/A (missing: smartctl)"
        echo
        return
    fi

    if ! have_cmd lsblk; then
        echo "N/A (missing: lsblk)"
        echo
        return
    fi

    lsblk -d -n -o NAME,TYPE | while read -r name type; do
        [[ "$type" != "disk" ]] && continue

        device="/dev/$name"

        health=$(smartctl -H "$device" 2>/dev/null | grep -i "overall-health" | awk -F: '{print $2}' | xargs)

        if [[ -z "$health" ]]; then
            health="Unknown"
        fi

        if echo "$health" | grep -qi "PASSED"; then
            echo -e "${GREEN}[OK]${NC} $device: $health"
        else
            echo -e "${RED}[WARN]${NC} $device: $health"
        fi
    done

    echo
}


# build main
main() {
    title "Storage Summary"
    show_block_devices
    show_mounted_filesystems
    show_usage_warnings 
    show_physical_disks
    show_top_space_consumers 
    show_inode_usage
    show_smart_health  
}

# call main
main "$@"