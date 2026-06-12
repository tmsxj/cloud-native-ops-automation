#!/bin/bash

SERVICE_NAME="$1"
NAMESPACE="${2:-default}"

if [ -z "$SERVICE_NAME" ]; then
    echo -e "\033[31m[FAIL] Usage: $0 <service-name> [namespace]\033[0m"
    exit 1
fi

echo -e "\033[34m[INFO] Checking service: $SERVICE_NAME in namespace: $NAMESPACE\033[0m"

kubectl get service "$SERVICE_NAME" -n "$NAMESPACE" -o wide 2>/dev/null || {
    echo -e "\033[31m[FAIL] Service $SERVICE_NAME not found\033[0m"
    exit 1
}

echo -e "\n\033[34m[INFO] Checking endpoints...\033[0m"
kubectl get endpoints "$SERVICE_NAME" -n "$NAMESPACE" -o yaml 2>/dev/null | grep -A10 "subsets:"

echo -e "\n\033[34m[INFO] Checking service type and clusterIP...\033[0m"
kubectl get service "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.type} {.spec.clusterIP}'