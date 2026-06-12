#!/bin/bash

PID="${1:-}"

echo -e "\033[34m[INFO] Checking CPU scheduler status\033[0m"

echo -e "\n\033[34m[INFO] Current CPU governor:\033[0m"
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | uniq

echo -e "\n\033[34m[INFO] Checking context switches...\033[0m"
vmstat 1 1 | tail -1 | awk '{print "Context switches: " $12 "/s, Interrupts: " $14 "/s"}'

echo -e "\n\033[34m[INFO] Checking scheduler statistics:\033[0m"
cat /proc/schedstat 2>/dev/null | head -10

echo -e "\n\033[34m[INFO] Checking runqueue length...\033[0m"
vmstat 1 1 | tail -1 | awk '{print "Runqueue: " $1 " processes"}'

if [ -n "$PID" ]; then
    echo -e "\n\033[34m[INFO] Checking scheduler info for PID: $PID\033[0m"
    if ps -p "$PID" > /dev/null; then
        echo -e "\033[32m[OK] Process $PID exists\033[0m"
        cat /proc/"$PID"/sched 2>/dev/null | grep -E "(se.exec_start|se.sum_exec_runtime|policy|prio)" | head -10
    else
        echo -e "\033[31m[FAIL] Process $PID not found\033[0m"
    fi
fi

echo -e "\n\033[34m[INFO] Checking CPU topology...\033[0m"
lscpu | grep -E "(CPU\(s\)|Thread\(s\) per core|Core\(s\) per socket|Socket\(s\))"