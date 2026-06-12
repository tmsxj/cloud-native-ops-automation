#!/bin/bash

TARGET_HOST="${1:-8.8.8.8}"

echo -e "\033[34m[INFO] Checking network latency to $TARGET_HOST\033[0m"

echo -e "\n\033[34m[INFO] Pinging $TARGET_HOST...\033[0m"
ping_result=$(ping -c 5 "$TARGET_HOST" 2>&1)

if echo "$ping_result" | grep -q "100% packet loss"; then
    echo -e "\033[31m[FAIL] 100% packet loss to $TARGET_HOST\033[0m"
    exit 1
fi

echo "$ping_result"

avg_latency=$(echo "$ping_result" | grep "avg" | awk -F '/' '{print $5}')
echo -e "\n\033[34m[INFO] Average latency: $avg_latency ms\033[0m"

if [ -n "$avg_latency" ] && [ "$(echo "$avg_latency > 100" | bc)" -eq 1 ]; then
    echo -e "\033[33m[WARN] High latency detected\033[0m"
else
    echo -e "\033[32m[OK] Latency is acceptable\033[0m"
fi

echo -e "\n\033[34m[INFO] Checking network interfaces...\033[0m"
ip addr show | grep -E "^[0-9]:" | awk '{print $2, $NF}'

echo -e "\n\033[34m[INFO] Checking routing...\033[0m"
ip route | grep default