#!/bin/bash

NAMESPACE="${1:-default}"

echo -e "\033[34m[INFO] Checking pods with restarts in namespace: $NAMESPACE\033[0m"

kubectl get pods -n "$NAMESPACE" -o jsonpath='{range .items[*]}{@.status.containerStatuses[*].restartCount}{"\t"}{@.metadata.name}{"\n"}{end}' | \
    awk '$1 > 0 {print $2 " (" $1 " restarts)"}' | \
    while read -r pod_info; do
        if [ -n "$pod_info" ]; then
            echo -e "\033[33m[WARN] $pod_info\033[0m"
        fi
    done

echo -e "\n\033[34m[INFO] Checking CrashLoopBackOff pods...\033[0m"
crash_pods=$(kubectl get pods -n "$NAMESPACE" 2>/dev/null | grep -i CrashLoopBackOff | awk '{print $1}')

if [ -n "$crash_pods" ]; then
    echo -e "\033[31m[FAIL] Found CrashLoopBackOff pods:\033[0m"
    echo "$crash_pods" | while read -r pod; do
        echo -e "\033[31m- $pod\033[0m"
        kubectl describe pod "$pod" -n "$NAMESPACE" 2>/dev/null | grep -A5 "Last State"
    done
else
    echo -e "\033[32m[OK] No CrashLoopBackOff pods found\033[0m"
fi