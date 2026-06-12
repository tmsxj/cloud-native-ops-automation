#!/bin/bash

echo -e "\033[34m[INFO] Checking Nginx status\033[0m"

if ! command -v nginx &> /dev/null; then
    echo -e "\033[31m[FAIL] nginx command not found\033[0m"
    exit 1
fi

echo -e "\033[34m[INFO] Checking nginx configuration...\033[0m"
result=$(nginx -t 2>&1)

if echo "$result" | grep -q "test is successful"; then
    echo -e "\033[32m[OK] Nginx configuration is valid\033[0m"
else
    echo -e "\033[31m[FAIL] Nginx configuration error: $result\033[0m"
    exit 1
fi

echo -e "\n\033[34m[INFO] Checking nginx process...\033[0m"
if ps aux | grep -v grep | grep -q nginx; then
    echo -e "\033[32m[OK] Nginx is running\033[0m"
    
    echo -e "\n\033[34m[INFO] Checking connection status...\033[0m"
    if command -v ss &> /dev/null; then
        connections=$(ss -tlnp | grep nginx | wc -l)
        echo "Nginx listening ports: $connections"
    fi
    
    echo -e "\n\033[34m[INFO] Checking worker processes...\033[0m"
    workers=$(ps aux | grep -v grep | grep nginx | grep -c worker)
    echo "Worker processes: $workers"
    
else
    echo -e "\033[31m[FAIL] Nginx is not running\033[0m"
    exit 1
fi