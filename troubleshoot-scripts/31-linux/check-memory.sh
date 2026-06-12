#!/bin/bash

PID="${1:-}"

echo -e "\033[34m[INFO] Checking memory usage\033[0m"

echo -e "\n\033[34m[INFO] Memory overview:\033[0m"
free -h

echo -e "\n\033[34m[INFO] Top memory consuming processes:\033[0m"
top -bn1 | grep -E "^ *[0-9]+.*[0-9.]%MEM" | head -10

if [ -n "$PID" ]; then
    echo -e "\n\033[34m[INFO] Checking memory for PID: $PID\033[0m"
    if ps -p "$PID" > /dev/null; then
        echo -e "\033[32m[OK] Process $PID exists\033[0m"
        cat /proc/"$PID"/status | grep -E "(VmSize|VmRSS|VmData|VmStk)"
    else
        echo -e "\033[31m[FAIL] Process $PID not found\033[0m"
    fi
fi

echo -e "\n\033[34m[INFO] Checking OOM killer status...\033[0m"
oom_count=$(dmesg 2>/dev/null | grep -c "Out of memory" || echo "0")
if [ "$oom_count" -gt 0 ]; then
    echo -e "\033[31m[FAIL] OOM killer triggered $oom_count times\033[0m"
    dmesg 2>/dev/null | grep "Out of memory" | tail -3
else
    echo -e "\033[32m[OK] No OOM killer events detected\033[0m"
fi