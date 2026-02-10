#!/usr/bin/env bash

# system-info.sh
# Portable system summary script
# Author: costin.serbanoiu@gmail.com
# Version: 1.1
# Updated: 08 Feb 2026

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

#create functions to make script quiet exit and check for path

#check program exists
have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

#if command does not exist print N/A and not hang
safe_run() {
  "$@" 2>/dev/null || echo "N/A"
}

#create get_primary_disk function
get_primary_disk() {
    lsblk -dn -o NAME,TYPE 2>/dev/null | awk '$2=="disk"{print "/dev/"$1; exit}'
}


printf %"s\n"
echo -e "${GREEN}Computer Summary${NC}"
printf %"s\n"
printf %"s\n"

#variables used for info

#cpu_info
if have_cmd lscpu; then
    cpu_model=$(lscpu | grep 'Model name' | cut -f 2 -d ":" | awk '{$1=$1}1')
    cpu_architecture=$(lscpu | grep 'Architecture' | cut -f 2 -d ":" | awk '{$1=$1}1')
else
    cpu_model="N/A"
    cpu_architecture=$(uname -m)
fi

cpu_load=$(cat <(grep 'cpu ' /proc/stat) <(sleep 1 && grep 'cpu ' /proc/stat) | awk -v RS="" '{print ($13-$2+$15-$4)*100/($13-$2+$15-$4+$16-$5) "%"}')

#os info + uptime+date
OSInfo=$(uname -srmo)
UPTIME=$(uptime -p)
DATE=$(date)

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    system_name="$NAME"
    OSVersion="$VERSION"
else
    system_name=$(uname -s)
    OSVersion=$(uname -r)
fi

#ram info
if have_cmd dmidecode; then
    RAMSLOTS=$(dmidecode -t memory 2>/dev/null | grep -i "Size:" | wc -l)
    INSTALLEDRAM=$(dmidecode -t memory 2>/dev/null | grep -i "Size:")
else
    RAMSLOTS="N/A"
    INSTALLEDRAM="N/A"
fi

MEMTOTAL=$(cat /proc/meminfo | grep MemTotal | cut -f 2 -d ":" | awk '{$1=$1}1')
FREEMEM=$(cat /proc/meminfo | grep MemFree | cut -f 2 -d ":" | awk '{$1=$1}1')
USEDMEM=$(free | grep "Mem:"  | awk '{print $2}')
AVAILMEM=$(cat /proc/meminfo | grep MemAvailable | cut -f 2 -d ":" | awk '{$1=$1}1')

#hdd info
PRIMARY_DISK=$(get_primary_disk)

if have_cmd smartctl && [[ -n "$PRIMARY_DISK" && -b "$PRIMARY_DISK" ]]; then
    HDDMODEL=$(smartctl -i "$PRIMARY_DISK" 2>/dev/null | awk -F: '/Device Model|Model Number/{print $2}' | xargs)
    HDDTYPE=$(smartctl -i "$PRIMARY_DISK" 2>/dev/null | awk -F: '/Model Family/{print $2}' | xargs)
    HDDCAPACITY=$(smartctl -i "$PRIMARY_DISK" 2>/dev/null | awk -F: '/User Capacity/{print $2}' | xargs)
else
    HDDMODEL="N/A"
    HDDTYPE="N/A"
    HDDCAPACITY="N/A"
fi

HDDUSED=$(df -H --total | grep -i total | awk '{print $3}')
HDDAVAIL=$(df -H --total | grep -i total | awk '{print $4}')

#docker info

if have_cmd docker; then
    DOCKER=$(command -v docker)

    if [[ -S /var/run/docker.sock ]]; then
        if docker info >/dev/null 2>&1; then
            DOCKER_STATUS="Running"
            DOCKERIMAGES=$(docker ps -q | wc -l)

            # List running containers: name (image)
            DOCKER_CONTAINERS=$(docker ps \
                --format '{{.Names}} ({{.Image}})' 2>/dev/null)

            # Fallback if none running
            [[ -z "$DOCKER_CONTAINERS" ]] && DOCKER_CONTAINERS="None running"
        else
            DOCKER_STATUS="Socket exists but daemon not responding"
            DOCKERIMAGES="N/A"
            DOCKER_CONTAINERS="N/A"
        fi
    else
        DOCKER_STATUS="Docker installed, socket missing"
        DOCKERIMAGES="N/A"
        DOCKER_CONTAINERS="N/A"
    fi
else
    DOCKER="N/A"
    DOCKER_STATUS="Docker not installed"
    DOCKERIMAGES="N/A"
    DOCKER_CONTAINERS="N/A"
fi

#gpu info
if have_cmd lspci; then
    GPU=$(lspci | grep -iE 'vga|3d' \
        | head -n 1 \
        | sed -E 's/^.*: //' \
        | sed -E 's/ \(rev.*\)//')
else
    GPU="N/A"
fi

# Detect GPU type
    if echo "$GPU_RAW" | grep -qiE 'intel'; then
        GPU_TYPE="Integrated"
    elif echo "$GPU_RAW" | grep -qiE 'nvidia'; then
        GPU_TYPE="Dedicated"
    elif echo "$GPU_RAW" | grep -qiE 'amd|ati'; then
        if echo "$GPU_RAW" | grep -qiE 'rx|radeon pro|firepro'; then
            GPU_TYPE="Dedicated"
        else
            GPU_TYPE="Integrated"
        fi
    else
        GPU_TYPE="Unknown"
    fi
else
    GPU="N/A"
    GPU_TYPE="N/A"
fi
########### run ############


#CPU
echo -e "${RED}CPU Info${NC}:"
printf %"s\n"


echo -e "${BWHITE}${UWHITE}Model${NC}: $cpu_model"


echo -e "${BWHITE}${UWHITE}Architecture${NC}: $cpu_architecture"


echo -e "${BWHITE}${UWHITE}CPU current load${NC}: $cpu_load"
printf %"s\n"


#OS
echo -e "${RED}Operating system${NC}:"
printf %"s\n"

echo -e "${BWHITE}${UWHITE}$system_name $OSVersion${NC}"
echo -e "${BWHITE}${UWHITE}OS Info${NC}: $OSInfo"
printf %"s\n"

#Memory
echo -e "${RED}Memory${NC}:"
printf %"s\n"

echo -e "${BWHITE}${UWHITE}Total Memory${NC}: $MEMTOTAL"
echo -e "${BWHITE}${UWHITE}Ram Slots${NC}: $RAMSLOTS"
echo -e "${BWHITE}${UWHITE}Used Memory${NC}: $USEDMEM kB"
echo -e "${BWHITE}${UWHITE}Available Memory${NC}: $AVAILMEM"
echo -e "${BWHITE}${UWHITE}Free Memory${NC}: $FREEMEM"
printf %"s\n"

#Storage
echo -e "${RED}Storage${NC}:"
printf %"s\n"

echo -e "${BWHITE}${UWHITE}Model${NC}: $HDDMODEL"
echo -e "${BWHITE}${UWHITE}Type${NC}: $HDDTYPE"
echo -e "${BWHITE}${UWHITE}Capacity${NC}: $HDDCAPACITY"
echo -e "${BWHITE}${UWHITE}Space used${NC}: $HDDUSED"
echo -e "${BWHITE}${UWHITE}Space available${NC}: $HDDAVAIL"
printf %"s\n"

#docker
echo -e "${UYELLOW}disclaimer${NC}: if Docker is installed the location under which docker resides is shown as 'overlay' under df with the full total space and added to the total size/used/available"

echo -e "${UYELLOW}Docker installed under${NC}: $DOCKER"
echo -e "${UYELLOW}Docker status${NC}: $DOCKER_STATUS"
echo -e "${UYELLOW}Docker images running${NC}: $DOCKERIMAGES"
echo -e "${UYELLOW}Running containers${NC}:"
while read -r line; do
    echo -e "  - $line"
done <<< "$DOCKER_CONTAINERS"
printf %"s\n"


#GPU
echo -e "${RED}Graphic Processor${NC}: $GPU"
echo -e "${BWHITE}${UWHITE}GPU Type${NC}: $GPU_TYPE"
printf %"s\n"

#Uptime
echo -e "${RED}Uptime${NC}: date is $DATE and system has been $UPTIME"
printf %"s\n"