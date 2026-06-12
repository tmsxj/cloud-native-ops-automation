#!/bin/bash

PORT="${1:-}"

echo -e "\033[34m[INFO] Checking TCP connection status\033[0m"

echo -e "\n\033[34m[INFO] TCP connection status overview:\033[0m"
ss -tuln | head -20

echo -e "\n\033[34m[INFO] Connection counts by state:\033[0m"
ss -tan | awk '{print $1}' | sort | uniq -c | sort -rn

if [ -n "$PORT" ]; then
    echo -e "\n\033[34m[INFO] Checking port $PORT\033[0m"
    if ss -tuln | grep -q ":$PORT"; then
        echo -e "\033[32m[OK] Port $PORT is listening\033[0m"
        ss -tuln | grep ":$PORT"
    else
        echo -e "\033[31m[FAIL] Port $PORT is not listening\033[0m"
    fi
    
    echo -e "\n\033[34m[INFO] Connections on port $PORT:\033[0m"
    ss -tan | grep ":$PORT" | head -10
fi

echo -e "\n\033[34m[INFO] Listening ports:\033[0m"
ss -tln | grep -v "^State" | awk '{print $4}' | sort