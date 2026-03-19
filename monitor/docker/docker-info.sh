#!/usr/bin/env bash

# docker-info.sh
# Docker summary script
# Author: costin.serbanoiu@gmail.com
# Version: 0.1
# Updated: 19 Mar 2026

# Return non-zero if any command in a pipeline fails
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

main() {
    title "Docker Summary"
    echo "start script"
}

main "$@"