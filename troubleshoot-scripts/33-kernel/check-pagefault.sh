#!/bin/bash

PID="${1:-}"

echo -e "\033[34m[INFO] Checking page fault status\033[0m"

echo -e "\n\033[34m[INFO] System-wide page faults:\033[0m"
vmstat 1 1 | tail -1 | awk '{print "Page in: " $8 ", Page out: " $9}'

echo -e "\n\033[34m[INFO] Checking /proc/vmstat...\033[0m"
grep -E "(pgfault|pgmajfault|pgalloc|pgfree)" /proc/vmstat 2>/dev/null

if [ -n "$PID" ]; then
    echo -e "\n\033[34m[INFO] Checking page faults for PID: $PID\033[0m"
    if ps -p "$PID" > /dev/null; then
        echo -e "\033[32m[OK] Process $PID exists\033[0m"
        faults=$(cat /proc/"$PID"/status 2>/dev/null | grep -E "(Minflt|Majflt)")
        echo "$faults"
        
        minflt=$(echo "$faults" | grep Minflt | awk '{print $2}')
        majflt=$(echo "$faults" | grep Majflt | awk '{print $2}')
        
        if [ "$majflt" -gt 1000 ]; then
            echo -e "\033[31m[FAIL] High major page faults detected: $majflt\033[0m"
        elif [ "$majflt" -gt 100 ]; then
            echo -e "\033[33m[WARN] Moderate major page faults: $majflt\033[0m"
        else
            echo -e "\033[32m[OK] Major page faults are normal: $majflt\033[0m"
        fi
    else
        echo -e "\033[31m[FAIL] Process $PID not found\033[0m"
    fi
fi

echo -e "\n\033[34m[INFO] Checking swap usage...\033[0m"
free -h | grep Swap