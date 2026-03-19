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


# build main
main() {
    title "Storage Summary"
    echo "starting script"
}

# call main
main "$@"