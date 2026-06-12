#!/bin/bash

INGRESS_NAME="$1"
NAMESPACE="${2:-default}"

if [ -z "$INGRESS_NAME" ]; then
    echo -e "\033[31m[FAIL] Usage: $0 <ingress-name> [namespace]\033[0m"
    exit 1
fi

echo -e "\033[34m[INFO] Checking ingress: $INGRESS_NAME in namespace: $NAMESPACE\033[0m"

kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" -o yaml 2>/dev/null || {
    echo -e "\033[31m[FAIL] Ingress $INGRESS_NAME not found\033[0m"
    exit 1
}

echo -e "\n\033[34m[INFO] Checking backend services...\033[0m"
kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" -o jsonpath='{range .spec.rules[*].http.paths[*]}{.backend.service.name}{"\t"}{.path}{"\n"}{end}'

echo -e "\n\033[34m[INFO] Checking ingress controller pods...\033[0m"
kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx 2>/dev/null | grep -v NAME || echo "Ingress controller not found in ingress-nginx namespace"