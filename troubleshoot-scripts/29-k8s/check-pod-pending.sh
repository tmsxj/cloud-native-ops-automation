#!/bin/bash

NAMESPACE="${1:-default}"

echo -e "\033[34m[INFO] Checking pending pods in namespace: $NAMESPACE\033[0m"

pending_pods=$(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Pending -o json 2>/dev/null)

if [ -z "$pending_pods" ] || [ "$pending_pods" = "{}" ]; then
    echo -e "\033[32m[OK] No pending pods found in namespace $NAMESPACE\033[0m"
    exit 0
fi

echo -e "\033[33m[WARN] Found pending pods:\033[0m"
kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Pending -o wide

echo -e "\n\033[34m[INFO] Analyzing pending reasons...\033[0m"
kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Pending -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[*].message}{"\n"}{end}'