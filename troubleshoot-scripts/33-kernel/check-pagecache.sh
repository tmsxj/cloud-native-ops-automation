#!/bin/bash

echo -e "\033[34m[INFO] Checking PageCache status\033[0m"

echo -e "\n\033[34m[INFO] PageCache statistics:\033[0m"
cat /proc/meminfo | grep -E "(Cached|Buffers|Active|Inactive)"

echo -e "\n\033[34m[INFO] Checking dirty pages...\033[0m"
dirty_ratio=$(cat /proc/sys/vm/dirty_ratio 2>/dev/null)
dirty_background_ratio=$(cat /proc/sys/vm/dirty_background_ratio 2>/dev/null)
echo "dirty_ratio: $dirty_ratio%"
echo "dirty_background_ratio: $dirty_background_ratio%"

echo -e "\n\033[34m[INFO] Checking page cache pressure...\033[0m"
echo "vm.swappiness: $(cat /proc/sys/vm/swappiness 2>/dev/null)"
echo "vm.vfs_cache_pressure: $(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null)"

echo -e "\n\033[34m[INFO] Checking page cache operations...\033[0m"
grep -E "(pgpgin|pgpgout|pswpin|pswpout)" /proc/vmstat 2>/dev/null

echo -e "\n\033[34m[INFO] Checking slab cache...\033[0m"
slabtop -o -s c | head -15