#!/bin/bash

echo -e "\033[34m[INFO] Checking TIME_WAIT status\033[0m"

echo -e "\n\033[34m[INFO] TIME_WAIT count:\033[0m"
time_wait_count=$(ss -tan | grep TIME-WAIT | wc -l)
echo "TIME_WAIT connections: $time_wait_count"

if [ "$time_wait_count" -gt 1000 ]; then
    echo -e "\033[33m[WARN] High TIME_WAIT count detected\033[0m"
elif [ "$time_wait_count" -gt 5000 ]; then
    echo -e "\033[31m[FAIL] Very high TIME_WAIT count - may indicate port exhaustion\033[0m"
else
    echo -e "\033[32m[OK] TIME_WAIT count is normal\033[0m"
fi

echo -e "\n\033[34m[INFO] Current TCP TIME_WAIT settings:\033[0m"
echo "tcp_fin_timeout: $(cat /proc/sys/net/ipv4/tcp_fin_timeout 2>/dev/null || echo "N/A")"
echo "tcp_tw_reuse: $(cat /proc/sys/net/ipv4/tcp_tw_reuse 2>/dev/null || echo "N/A")"
echo "tcp_tw_recycle: $(cat /proc/sys/net/ipv4/tcp_tw_recycle 2>/dev/null || echo "N/A")"
echo "tcp_max_tw_buckets: $(cat /proc/sys/net/ipv4/tcp_max_tw_buckets 2>/dev/null || echo "N/A")"

echo -e "\n\033[34m[INFO] Top TIME_WAIT destinations:\033[0m"
ss -tan | grep TIME-WAIT | awk '{print $5}' | sort | uniq -c | sort -rn | head -10