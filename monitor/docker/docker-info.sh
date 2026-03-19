#!/usr/bin/env bash

# docker-info.sh
# Docker summary script
# Author: costin.serbanoiu@gmail.com
# Version: 0.1
# Updated: 19 Mar 2026

# Return non-zero if any command in a pipeline fails
set -o pipefail

# use unified commands
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="$SCRIPT_DIR/../common/common.sh"

#check if lib is missing
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
show_docker_status() {
    section "Docker Status"

    if ! have_cmd docker; then
        echo "Docker is not installed"
        echo
        return
    fi

    echo -e "${BWHITE}${UWHITE}Docker binary${NC}: $(command -v docker)"

    if docker info >/dev/null 2>&1; then
        echo -e "${GREEN}[OK]${NC} Docker daemon is reachable"
    else
        echo -e "${RED}[FAIL]${NC} Docker daemon is not reachable"
        echo
        return
    fi

    echo
}

show_running_containers() {
    section "Running Containers"

    if ! have_cmd docker; then
        echo "Docker is not installed"
        echo
        return
    fi

    if ! docker info >/dev/null 2>&1; then
        echo "Docker daemon is not reachable"
        echo
        return
    fi

    container_count=$(docker ps -q | wc -l)

    echo -e "${BWHITE}${UWHITE}Running containers${NC}: $container_count"
    echo

    if [[ "$container_count" -eq 0 ]]; then
        echo "No running containers"
        echo
        return
    fi

    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
    echo
}

# build main
main() {
    title "Docker Summary"
    show_docker_status
    show_running_containers    
}

# call main
main "$@"