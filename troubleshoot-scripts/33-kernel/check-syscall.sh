#!/bin/bash

PID="${1:-}"

echo -e "\033[34m[INFO] Checking system call status\033[0m"

echo -e "\n\033[34m[INFO] System call availability:\033[0m"
ls /sys/kernel/debug/tracing/events/syscalls/ 2>/dev/null | grep -E "sys_enter_|sys_exit_" | head -10 || echo "Tracing not available"

if [ -n "$PID" ] && command -v strace &> /dev/null; then
    echo -e "\n\033[34m[INFO] Tracing syscalls for PID: $PID\033[0m"
    if ps -p "$PID" > /dev/null; then
        echo -e "\033[32m[OK] Process $PID exists\033[0m"
        echo -e "\033[34m[INFO] Top syscalls (press Ctrl+C to stop)...\033[0m"
        timeout 3 strace -p "$PID" -c 2>/dev/null | head -20
    else
        echo -e "\033[31m[FAIL] Process $PID not found\033[0m"
    fi
elif [ -n "$PID" ]; then
    echo -e "\n\033[33m[WARN] strace not installed, cannot trace syscalls\033[0m"
fi

echo -e "\n\033[34m[INFO] Checking system call table...\033[0m"
if [ -f /proc/kallsyms ]; then
    syscall_count=$(grep -c sys_call_table /proc/kallsyms)
    echo "sys_call_table found: $syscall_count entries"
else
    echo "/proc/kallsyms not available"
fi

echo -e "\n\033[34m[INFO] Checking seccomp status...\033[0m"
grep -r seccomp /proc/sys/kernel/ 2>/dev/null || echo "Seccomp info not available"