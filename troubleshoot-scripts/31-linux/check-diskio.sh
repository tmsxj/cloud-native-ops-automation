#!/bin/bash

DEVICE="${1:-}"

echo -e "\033[34m[INFO] Checking disk I/O status\033[0m"

echo -e "\n\033[34m[INFO] Disk usage:\033[0m"
df -h

echo -e "\n\033[34m[INFO] Disk I/O statistics:\033[0m"
iostat -x 1 1 | grep -A10 "^Device"

if [ -n "$DEVICE" ]; then
    echo -e "\n\033[34m[INFO] Checking specific device: $DEVICE\033[0m"
    iostat -x "$DEVICE" 1 1 | grep -v "^$" | grep -v Linux
fi

echo -e "\n\033[34m[INFO] Checking disk wait status...\033[0m"
vmstat 1 1 | tail -1 | awk '{print "wa (I/O wait): " $16 "%"}'

echo -e "\n\033[34m[INFO] Top I/O processes:\033[0m"
iotop -bn1 | head -10