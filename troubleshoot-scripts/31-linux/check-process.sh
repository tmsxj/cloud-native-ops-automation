#!/bin/bash

echo -e "\033[34m[INFO] Checking process status\033[0m"

echo -e "\n\033[34m[INFO] Zombie processes:\033[0m"
zombies=$(ps aux | grep -E "Z.*\<defunct\>" | grep -v grep)
if [ -n "$zombies" ]; then
    echo -e "\033[31m[FAIL] Found zombie processes:\033[0m"
    echo "$zombies"
else
    echo -e "\033[32m[OK] No zombie processes found\033[0m"
fi

echo -e "\n\033[34m[INFO] D-state (uninterruptible sleep) processes:\033[0m"
dstate=$(ps aux | grep -E "^[^ ]+ +[0-9]+ +[0-9.]+ +[0-9.]+ +.+D " | grep -v grep)
if [ -n "$dstate" ]; then
    echo -e "\033[33m[WARN] Found D-state processes:\033[0m"
    echo "$dstate" | awk '{print $2, $11}'
else
    echo -e "\033[32m[OK] No D-state processes found\033[0m"
fi

echo -e "\n\033[34m[INFO] Process count:\033[0m"
echo "Total processes: $(ps aux | wc -l)"
echo "Running: $(ps aux | grep -c " R ")"
echo "Sleeping: $(ps aux | grep -c " S ")"

echo -e "\n\033[34m[INFO] Checking max process limits...\033[0m"
echo "Max processes: $(cat /proc/sys/kernel/pid_max)"
echo "Current PID: $(cat /proc/sys/kernel/threads-max)"