#!/bin/bash

echo -e "\033[34m[INFO] Checking kernel health status\033[0m"

echo -e "\n\033[34m[INFO] Kernel version:\033[0m"
uname -a

echo -e "\n\033[34m[INFO] Checking kernel logs for errors...\033[0m"
errors=$(dmesg 2>/dev/null | grep -i error | tail -10)
if [ -n "$errors" ]; then
    echo -e "\033[31m[FAIL] Found errors in dmesg:\033[0m"
    echo "$errors"
else
    echo -e "\033[32m[OK] No errors in recent dmesg\033[0m"
fi

echo -e "\n\033[34m[INFO] Checking kernel panic history...\033[0m"
panic_count=$(grep -c "panic" /var/log/kern.log 2>/dev/null || grep -c "panic" /var/log/messages 2>/dev/null || echo "0")
if [ "$panic_count" -gt 0 ]; then
    echo -e "\033[31m[FAIL] Found $panic_count panic events\033[0m"
else
    echo -e "\033[32m[OK] No kernel panics detected\033[0m"
fi

echo -e "\n\033[34m[INFO] Checking loaded modules...\033[0m"
lsmod | head -10

echo -e "\n\033[34m[INFO] Checking kernel configuration...\033[0m"
echo "Config file: /boot/config-$(uname -r)"
if [ -f "/boot/config-$(uname -r)" ]; then
    echo "Kernel config exists"
else
    echo -e "\033[33m[WARN] Kernel config not found\033[0m"
fi

echo -e "\n\033[34m[INFO] Checking kernel parameters...\033[0m"
cat /proc/cmdline