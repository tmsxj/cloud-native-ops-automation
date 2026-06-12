#!/bin/bash

PID="${1:-}"

echo -e "\033[34m[INFO] Checking CPU usage\033[0m"

echo -e "\n\033[34m[INFO] Overall CPU usage:\033[0m"
top -bn1 | head -5

echo -e "\n\033[34m[INFO] Top CPU consuming processes:\033[0m"
top -bn1 | grep -A10 "^PID"

if [ -n "$PID" ]; then
    echo -e "\n\033[34m[INFO] Checking specific PID: $PID\033[0m"
    if ps -p "$PID" > /dev/null; then
        echo -e "\033[32m[OK] Process $PID exists\033[0m"
        top -bn1 -p "$PID" | tail -5
    else
        echo -e "\033[31m[FAIL] Process $PID not found\033[0m"
    fi
fi

echo -e "\n\033[34m[INFO] CPU cores and load average:\033[0m"
echo "CPU cores: $(nproc)"
echo "Load average: $(cat /proc/loadavg | awk '{print $1", "$2", "$3}')"