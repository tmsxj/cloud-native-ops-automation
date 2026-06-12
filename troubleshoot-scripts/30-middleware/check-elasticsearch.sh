#!/bin/bash

HOST="${1:-127.0.0.1}"
PORT="${2:-9200}"

echo -e "\033[34m[INFO] Checking Elasticsearch: $HOST:$PORT\033[0m"

if ! command -v curl &> /dev/null; then
    echo -e "\033[31m[FAIL] curl not found\033[0m"
    exit 1
fi

echo -e "\033[34m[INFO] Testing connection...\033[0m"
result=$(curl -s "http://$HOST:$PORT/_cluster/health" 2>/dev/null)

if [ -z "$result" ]; then
    echo -e "\033[31m[FAIL] Unable to connect to Elasticsearch\033[0m"
    exit 1
fi

status=$(echo "$result" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

case "$status" in
    green) echo -e "\033[32m[OK] Cluster status: $status\033[0m" ;;
    yellow) echo -e "\033[33m[WARN] Cluster status: $status\033[0m" ;;
    red) echo -e "\033[31m[FAIL] Cluster status: $status\033[0m" ;;
    *) echo -e "\033[34m[INFO] Cluster status: $status\033[0m" ;;
esac

echo -e "\n\033[34m[INFO] Cluster details:\033[0m"
echo "$result" | grep -E '"number_of_nodes"|"number_of_data_nodes"|"active_primary_shards"|"active_shards"|"unassigned_shards"'

echo -e "\n\033[34m[INFO] Checking unassigned shards...\033[0m"
unassigned=$(echo "$result" | grep -o '"unassigned_shards":[0-9]*' | cut -d: -f2)
if [ "$unassigned" -gt 0 ]; then
    echo -e "\033[31m[FAIL] Found $unassigned unassigned shards\033[0m"
else
    echo -e "\033[32m[OK] No unassigned shards\033[0m"
fi