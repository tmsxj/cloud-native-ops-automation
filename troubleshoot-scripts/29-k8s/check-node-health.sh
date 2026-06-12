#!/bin/bash

echo -e "\033[34m[INFO] Checking node health status\033[0m"

nodes=$(kubectl get nodes -o json 2>/dev/null)

if [ -z "$nodes" ] || [ "$nodes" = "{}" ]; then
    echo -e "\033[31m[FAIL] Unable to get node information\033[0m"
    exit 1
fi

echo -e "\n\033[34m[INFO] Node status overview:\033[0m"
kubectl get nodes -o wide

echo -e "\n\033[34m[INFO] Node conditions:\033[0m"
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .status.conditions[*]}{"\t"}{.type}{": "}{.status}{"\n"}{end}{end}' | \
    while read -r line; do
        if echo "$line" | grep -q "False"; then
            echo -e "\033[31m$line\033[0m"
        elif echo "$line" | grep -q "True"; then
            echo -e "\033[32m$line\033[0m"
        else
            echo "$line"
        fi
    done