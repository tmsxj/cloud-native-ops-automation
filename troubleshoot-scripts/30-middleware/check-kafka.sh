#!/bin/bash

BOOTSTRAP_SERVER="${1:-localhost:9092}"

echo -e "\033[34m[INFO] Checking Kafka: $BOOTSTRAP_SERVER\033[0m"

if ! command -v kafka-topics.sh &> /dev/null; then
    echo -e "\033[31m[FAIL] kafka-topics.sh not found in PATH\033[0m"
    exit 1
fi

echo -e "\033[34m[INFO] Testing broker connection...\033[0m"
result=$(kafka-topics.sh --list --bootstrap-server "$BOOTSTRAP_SERVER" 2>&1 | head -5)

if echo "$result" | grep -q "Error"; then
    echo -e "\033[31m[FAIL] Kafka connection failed: $result\033[0m"
    exit 1
fi

echo -e "\033[32m[OK] Kafka connection successful\033[0m"

echo -e "\n\033[34m[INFO] List of topics:\033[0m"
kafka-topics.sh --list --bootstrap-server "$BOOTSTRAP_SERVER" 2>/dev/null | head -10

echo -e "\n\033[34m[INFO] Checking broker health...\033[0m"
kafka-topics.sh --describe --bootstrap-server "$BOOTSTRAP_SERVER" --topic "__consumer_offsets" 2>/dev/null | head -5 || echo "Cannot check __consumer_offsets topic"