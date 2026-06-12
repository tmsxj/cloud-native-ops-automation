#!/bin/bash

echo -e "\033[34m[INFO] Checking boot status\033[0m"

echo -e "\n\033[34m[INFO] Recent boot time:\033[0m"
uptime -s

echo -e "\n\033[34m[INFO] Systemd service status:\033[0m"
failed_units=$(systemctl list-units --failed --type=service 2>/dev/null)
if echo "$failed_units" | grep -q "0 loaded units listed"; then
    echo -e "\033[32m[OK] All services running\033[0m"
else
    echo -e "\033[31m[FAIL] Found failed services:\033[0m"
    echo "$failed_units"
fi

echo -e "\n\033[34m[INFO] Checking journal for boot errors...\033[0m"
errors=$(journalctl -p err -n 20 2>/dev/null)
if [ -n "$errors" ]; then
    echo -e "\033[33m[WARN] Recent errors in journal:\033[0m"
    echo "$errors"
else
    echo -e "\033[32m[OK] No recent errors in journal\033[0m"
fi

echo -e "\n\033[34m[INFO] Checking fstab mounts...\033[0m"
mount | grep -E "^/dev/" | awk '{print $1, "->", $3}'

echo -e "\n\033[34m[INFO] Checking filesystem errors...\033[0m"
fsck_errors=$(dmesg 2>/dev/null | grep -i fsck | grep -i error)
if [ -n "$fsck_errors" ]; then
    echo -e "\033[31m[FAIL] Filesystem errors detected:\033[0m"
    echo "$fsck_errors"
else
    echo -e "\033[32m[OK] No filesystem errors detected\033[0m"
fi