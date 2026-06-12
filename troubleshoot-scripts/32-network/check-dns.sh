#!/bin/bash

DOMAIN="${1:-example.com}"

echo -e "\033[34m[INFO] Checking DNS resolution for $DOMAIN\033[0m"

echo -e "\n\033[34m[INFO] Using dig to resolve...\033[0m"
if command -v dig &> /dev/null; then
    dig_result=$(dig "$DOMAIN" +short 2>&1)
    if [ -n "$dig_result" ]; then
        echo -e "\033[32m[OK] DNS resolution successful\033[0m"
        echo "IP addresses: $dig_result"
    else
        echo -e "\033[31m[FAIL] DNS resolution failed\033[0m"
        exit 1
    fi
else
    echo -e "\n\033[34m[INFO] Using nslookup...\033[0m"
    nslookup_result=$(nslookup "$DOMAIN" 2>&1)
    if echo "$nslookup_result" | grep -q "Address"; then
        echo -e "\033[32m[OK] DNS resolution successful\033[0m"
        echo "$nslookup_result" | grep "Address"
    else
        echo -e "\033[31m[FAIL] DNS resolution failed\033[0m"
        exit 1
    fi
fi

echo -e "\n\033[34m[INFO] Checking /etc/resolv.conf...\033[0m"
cat /etc/resolv.conf 2>/dev/null | grep nameserver

echo -e "\n\033[34m[INFO] Checking DNS cache status...\033[0m"
if command -v systemd-resolve &> /dev/null; then
    systemd-resolve --status 2>/dev/null | grep -A5 "DNS Servers"
fi