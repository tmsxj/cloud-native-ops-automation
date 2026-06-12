#!/bin/bash

HOST="${1:-127.0.0.1}"
PORT="${2:-3306}"
USER="${3:-root}"
PASSWORD="${4:-}"

echo -e "\033[34m[INFO] Checking MySQL connection: $HOST:$PORT\033[0m"

if ! command -v mysql &> /dev/null; then
    echo -e "\033[31m[FAIL] mysql client not found\033[0m"
    exit 1
fi

if [ -n "$PASSWORD" ]; then
    MYSQL_CMD="mysql -h $HOST -P $PORT -u $USER -p$PASSWORD"
else
    MYSQL_CMD="mysql -h $HOST -P $PORT -u $USER"
fi

echo -e "\033[34m[INFO] Testing connection...\033[0m"
result=$($MYSQL_CMD -e "SELECT 1" 2>&1)

if [ $? -eq 0 ]; then
    echo -e "\033[32m[OK] MySQL connection successful\033[0m"
    
    echo -e "\n\033[34m[INFO] Checking slow queries...\033[0m"
    slow_queries=$($MYSQL_CMD -e "SHOW GLOBAL STATUS LIKE 'Slow_queries'" 2>/dev/null | grep -v Variable_name | awk '{print $2}')
    echo "Slow queries: $slow_queries"
    
    echo -e "\n\033[34m[INFO] Checking connection count...\033[0m"
    connections=$($MYSQL_CMD -e "SHOW GLOBAL STATUS LIKE 'Threads_connected'" 2>/dev/null | grep -v Variable_name | awk '{print $2}')
    max_connections=$($MYSQL_CMD -e "SHOW VARIABLES LIKE 'max_connections'" 2>/dev/null | grep -v Variable_name | awk '{print $2}')
    echo "Current connections: $connections / $max_connections"
    
else
    echo -e "\033[31m[FAIL] MySQL connection failed: $result\033[0m"
    exit 1
fi