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

DOCKER_AVAILABLE=0
DOCKER_DAEMON=0
DOCKER_BIN=""

# functions

check_docker() {
    if ! have_cmd docker; then
        DOCKER_AVAILABLE=0
        return
    fi

    DOCKER_AVAILABLE=1
    DOCKER_BIN="$(command -v docker)"

    if docker info >/dev/null 2>&1; then
        DOCKER_DAEMON=1
    else
        DOCKER_DAEMON=0
    fi
}

show_docker_status() {
    section "Docker Status"

    if [[ "$DOCKER_AVAILABLE" -eq 0 ]]; then
        echo "Docker is not installed"
        echo
        return
    fi

    echo -e "${BWHITE}${UWHITE}Docker binary${NC}: $DOCKER_BIN"

    if [[ "$DOCKER_DAEMON" -eq 1 ]]; then
        echo -e "${GREEN}[OK]${NC} Docker daemon is reachable"
    else
        echo -e "${RED}[FAIL]${NC} Docker daemon is not reachable"
    fi

    echo
}

show_running_containers() {
    section "Running Containers"

    if [[ "$DOCKER_AVAILABLE" -eq 0 ]]; then
        echo "Docker is not installed"
        echo
        return
    fi

    if [[ "$DOCKER_DAEMON" -eq 0 ]]; then
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

show_problem_containers() {
    section "Problem Containers"

    if [[ "$DOCKER_AVAILABLE" -eq 0 ]]; then
        echo "Docker is not installed"
        echo
        return
    fi

    if [[ "$DOCKER_DAEMON" -eq 0 ]]; then
        echo "Docker daemon is not reachable"
        echo
        return
    fi

    local found=0
    local stopped_output
    local unhealthy_output

    echo -e "${BWHITE}${UWHITE}Stopped / non-running containers${NC}:"
    stopped_output="$(docker ps -a \
        --filter "status=exited" \
        --filter "status=created" \
        --filter "status=dead" \
        --filter "status=restarting" \
        --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null)"

    if [[ -n "$(echo "$stopped_output" | tail -n +2)" ]]; then
        echo "$stopped_output"
        found=1
    else
        echo "None"
    fi

    echo
    echo -e "${BWHITE}${UWHITE}Unhealthy containers${NC}:"

    unhealthy_output="$(docker ps \
        --filter "health=unhealthy" \
        --format "{{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null)"

    if [[ -n "$unhealthy_output" ]]; then
        printf "%-20s %-30s %-30s\n" "NAME" "IMAGE" "STATUS"
        printf "%-20s %-30s %-30s\n" "----" "-----" "------"

        while IFS=$'\t' read -r name image status; do
            printf "%-20s %-30s %-30s\n" "$name" "$image" "$status"
        done <<< "$unhealthy_output"

        echo
        echo -e "${UYELLOW}Hint${NC}: Check logs with:"
        while IFS=$'\t' read -r name image status; do
            echo "  docker logs $name"
        done <<< "$unhealthy_output"

        found=1
    else
        echo "None"
    fi

    echo

    if [[ "$found" -eq 0 ]]; then
        echo -e "${GREEN}[OK]${NC} No stopped or unhealthy containers detected"
        echo
    fi
}

# build main
main() {
    title "Docker Summary"
    check_docker
    show_docker_status
    show_running_containers 
    show_problem_containers   
}

# call main
main "$@"