#!/bin/bash

HOST="${1:-127.0.0.1}"
PORT="${2:-6379}"
PASSWORD="${3:-}"

echo -e "\033[34m[INFO] Checking Redis connection: $HOST:$PORT\033[0m"

if ! command -v redis-cli &> /dev/null; then
    echo -e "\033[31m[FAIL] redis-cli not found\033[0m"
    exit 1
fi

if [ -n "$PASSWORD" ]; then
    REDIS_CMD="redis-cli -h $HOST -p $PORT -a $PASSWORD"
else
    REDIS_CMD="redis-cli -h $HOST -p $PORT"
fi

echo -e "\033[34m[INFO] Testing connection...\033[0m"
result=$($REDIS_CMD ping 2>&1)

if [ "$result" = "PONG" ]; then
    echo -e "\033[32m[OK] Redis connection successful\033[0m"
    
    echo -e "\n\033[34m[INFO] Checking memory usage...\033[0m"
    $REDIS_CMD info memory | grep -E "(used_memory_human|used_memory_peak_human|maxmemory_human)"
    
    echo -e "\n\033[34m[INFO] Checking connected clients...\033[0m"
    $REDIS_CMD info clients | grep connected_clients
    
    echo -e "\n\033[34m[INFO] Checking replication status...\033[0m"
    role=$($REDIS_CMD role 2>/dev/null | head -n1)
    echo "Role: $role"
    
else
    echo -e "\033[31m[FAIL] Redis connection failed: $result\033[0m"
    exit 1
fi