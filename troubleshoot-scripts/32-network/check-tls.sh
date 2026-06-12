#!/bin/bash

HOST="${1:-}"
PORT="${2:-443}"

if [ -z "$HOST" ]; then
    echo -e "\033[31m[FAIL] Usage: $0 <host> [port]\033[0m"
    exit 1
fi

echo -e "\033[34m[INFO] Checking TLS connection to $HOST:$PORT\033[0m"

if ! command -v openssl &> /dev/null; then
    echo -e "\033[31m[FAIL] openssl not found\033[0m"
    exit 1
fi

echo -e "\n\033[34m[INFO] Testing TLS connection...\033[0m"
result=$(echo | openssl s_client -connect "$HOST:$PORT" 2>&1 | head -30)

if echo "$result" | grep -q "Verify return code: 0 (ok)"; then
    echo -e "\033[32m[OK] TLS connection successful\033[0m"
else
    echo -e "\033[31m[FAIL] TLS connection failed\033[0m"
    echo "$result"
    exit 1
fi

echo -e "\n\033[34m[INFO] Certificate information:\033[0m"
echo "$result" | grep -E "(Subject:|Issuer:|Not Before:|Not After:)"

echo -e "\n\033[34m[INFO] Supported TLS versions:\033[0m"
echo "$result" | grep -E "^Protocol|^Cipher"