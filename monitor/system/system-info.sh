#!/usr/bin/env bash

# system-info.sh
# Portable system summary script
# Author: costin.serbanoiu@gmail.com
# Version: 1.1
# Updated: 08 Feb 2026

IS_ROOT=0

[[ $EUID -eq 0 ]] && IS_ROOT=1

if [[ $IS_ROOT -eq 0 ]]; then
    echo -e "${UYELLOW}Warning:${NC} running without root privileges."
    echo -e "${UYELLOW}Some hardware details may be unavailable.${NC}"
    printf "\n"
fi

if [[ $IS_ROOT -eq 1 ]] && have_cmd dmidecode; then
    RAMSLOTS=$(dmidecode -t memory 2>/dev/null | grep -i "Size:" | wc -l)
else
    RAMSLOTS="N/A (run as root)"
fi

if [[ $IS_ROOT -eq 1 ]] && have_cmd smartctl; then
    HDDMODEL=$(smartctl -i /dev/sda | grep "Device Model" | awk '{print $3, $4}')
    HDDTYPE=$(smartctl -i /dev/sda | grep "Model Family" | awk '{print $3, $4, $5}')
    HDDCAPACITY=$(smartctl -i /dev/sda | grep "User Capacity" | awk '{print $5, $6}')
else
    HDDMODEL="N/A (run as root)"
    HDDTYPE="N/A (run as root)"
    HDDCAPACITY="N/A (run as root)"
fi

set -o pipefail

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

#create functions to make script quieta and check for path

#check program exists
have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

#if command does not exist print N/A and not hang
safe_run() {
  "$@" 2>/dev/null || echo "N/A"
}


printf %"s\n"
echo -e "${GREEN}Computer Summary${NC}"
printf %"s\n"
printf %"s\n"

#variables used for info
cpu_model=$(lscpu | grep 'Model name' | cut -f 2 -d ":" | awk '{$1=$1}1')
cpu_architecture=$(lscpu | grep 'Architecture' | cut -f 2 -d ":" | awk '{$1=$1}1')
cpu_load=$(cat <(grep 'cpu ' /proc/stat) <(sleep 1 && grep 'cpu ' /proc/stat) | awk -v RS="" '{print ($13-$2+$15-$4)*100/($13-$2+$15-$4+$16-$5) "%"}')
system_name=$(awk -F 'NAME' '{print $0}' /etc/*-release | grep  "^NAME")
OSVersion=$(awk -F 'NAME' '{print $0}' /etc/*-release | grep  "^VERSION=")
printf %"s\n"
OSInfo=$(uname -srmo)
UPTIME=$(uptime -p)
DATE=$(date)
MEMTOTAL=$(cat /proc/meminfo | grep MemTotal | cut -f 2 -d ":" | awk '{$1=$1}1')
FREEMEM=$(cat /proc/meminfo | grep MemFree | cut -f 2 -d ":" | awk '{$1=$1}1')
USEDMEM=$(free | grep "Mem:"  | awk '{print $2}')
AVAILMEM=$(cat /proc/meminfo | grep MemAvailable | cut -f 2 -d ":" | awk '{$1=$1}1')
RAMSLOTS=$(sudo dmidecode -t memory | grep -i size | wc -l)
INSTALLEDRAM=$(sudo dmidecode -t memory | grep -i size)
HDDMODEL=$(smartctl -i /dev/sda | grep "Device Model" | awk '{print $3, $4}')
HDDTYPE=$(smartctl -i /dev/sda | grep "Model Family" | awk '{print $3, $4, $5}')
HDDCAPACITY=$(smartctl -i /dev/sda | grep "User Capacity" | awk '{print $5, $6}')
HDDUSED=$(df -H --total | grep -i total | awk '{print $3}')
HDDAVAIL=$(df -H --total | grep -i total | awk '{print $4}')
DOCKERIMAGES=$(docker ps -q | wc -l)
DOCKER=$(which docker)
GPU=$(lspci | grep -i vga)


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

echo -e "${UYELLOW}disclaimer${NC}: if Docker is installed the location under which docker resides is shown as 'overlay' under df with the full total space and added to the total size/used/available"

echo -e "${UYELLOW}Docker installed under${NC}: $DOCKER"
echo -e "${UYELLOW}Docker images running${NC}: $DOCKERIMAGES"
printf %"s\n"


#GPU
echo -e "${RED}Graphic Processor${NC}: $GPU"
printf %"s\n"

#Uptiime
echo -e "${RED}Uptime${NC}: date is $DATE and system has been $UPTIME"
printf %"s\n"