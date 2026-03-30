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

show_published_ports() {
    section "Published Ports"

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

    local port_output
    port_output="$(docker ps --format "{{.Names}}\t{{.Image}}\t{{.Ports}}" 2>/dev/null)"

    if [[ -z "$port_output" ]]; then
        echo "No running containers"
        echo
        return
    fi

    # Filter only containers that actually publish ports
    port_output="$(echo "$port_output" | awk -F'\t' '$3 != ""')"

    if [[ -z "$port_output" ]]; then
        echo "No published ports"
        echo
        return
    fi

    printf "%-22s %-30s %-40s\n" "CONTAINER" "IMAGE" "PORTS"
    printf "%-22s %-30s %-40s\n" "---------" "-----" "-----"

    while IFS=$'\t' read -r name image ports; do
        printf "%-22s %-30s %-40s\n" "$name" "$image" "$ports"
    done <<< "$port_output"

    echo
}

show_docker_networks() {
    section "Docker Networks"

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

    local network_output
    network_output="$(docker network ls --format "{{.Name}}\t{{.Driver}}\t{{.Scope}}" 2>/dev/null)"

    if [[ -z "$network_output" ]]; then
        echo "No Docker networks found"
        echo
        return
    fi

    echo -e "${BWHITE}${UWHITE}Defined networks${NC}:"
    printf "%-22s %-12s %-12s\n" "NAME" "DRIVER" "SCOPE"
    printf "%-22s %-12s %-12s\n" "----" "------" "-----"

    while IFS=$'\t' read -r name driver scope; do
        printf "%-22s %-12s %-12s\n" "$name" "$driver" "$scope"
    done <<< "$network_output"

    echo
    echo -e "${BWHITE}${UWHITE}Network membership${NC}:"

    while IFS=$'\t' read -r name driver scope; do
        containers="$(docker network inspect "$name" \
            --format '{{range $id, $c := .Containers}}{{printf "%s " $c.Name}}{{end}}' 2>/dev/null | xargs)"

        [[ -z "$containers" ]] && containers="None"

        printf "%-22s %s\n" "$name" "$containers"
    done <<< "$network_output"

    echo
}

show_docker_volumes() {
    section "Docker Volumes"

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

    local volume_names
    volume_names="$(docker volume ls --format "{{.Name}}" 2>/dev/null)"

    if [[ -z "$volume_names" ]]; then
        echo "No Docker volumes found"
        echo
        return
    fi

    echo -e "${BWHITE}${UWHITE}Defined volumes${NC}:"
    printf "%-28s %-60s\n" "NAME" "MOUNTPOINT"
    printf "%-28s %-60s\n" "----" "----------"

    while read -r vol; do
        [[ -z "$vol" ]] && continue
        mountpoint="$(docker volume inspect "$vol" --format '{{.Mountpoint}}' 2>/dev/null)"
        [[ -z "$mountpoint" ]] && mountpoint="Unknown"

        printf "%-28s %-60s\n" "$vol" "$mountpoint"
    done <<< "$volume_names"

    echo
    echo -e "${BWHITE}${UWHITE}Volume usage${NC}:"

    while read -r vol; do
        [[ -z "$vol" ]] && continue

        containers="$(docker ps -a --filter volume="$vol" --format '{{.Names}}' 2>/dev/null | xargs)"
        [[ -z "$containers" ]] && containers="None"

        printf "%-28s %s\n" "$vol" "$containers"
    done <<< "$volume_names"

    echo
}

show_docker_images() {
    section "Docker Images"

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

    local image_output
    local dangling_output

    echo -e "${BWHITE}${UWHITE}Available images${NC}:"
    image_output="$(docker images --format "{{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}" 2>/dev/null)"

    if [[ -n "$image_output" ]]; then
        printf "%-35s %-15s %-20s %-10s\n" "REPOSITORY" "TAG" "IMAGE ID" "SIZE"
        printf "%-35s %-15s %-20s %-10s\n" "----------" "---" "--------" "----"

        while IFS=$'\t' read -r repo tag id size; do
            printf "%-35s %-15s %-20s %-10s\n" "$repo" "$tag" "$id" "$size"
        done <<< "$image_output"
    else
        echo "No images found"
    fi

    echo
    echo -e "${BWHITE}${UWHITE}Dangling images${NC}:"
    dangling_output="$(docker images -f dangling=true --format "{{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}" 2>/dev/null)"

    if [[ -n "$dangling_output" ]]; then
        printf "%-35s %-15s %-20s %-10s\n" "REPOSITORY" "TAG" "IMAGE ID" "SIZE"
        printf "%-35s %-15s %-20s %-10s\n" "----------" "---" "--------" "----"

        while IFS=$'\t' read -r repo tag id size; do
            printf "%-35s %-15s %-20s %-10s\n" "$repo" "$tag" "$id" "$size"
        done <<< "$dangling_output"
    else
        echo "None"
    fi

    echo
}

# build main
main() {
    title "Docker Summary"
    check_docker
    show_docker_status
    show_running_containers 
    show_problem_containers   
    show_published_ports
    show_docker_networks
    show_docker_volumes
    show_docker_images
}

# call main
main "$@"