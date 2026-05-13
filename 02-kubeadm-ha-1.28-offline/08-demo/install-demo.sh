#!/bin/bash

###############################################################################
# 脚本名称：install-demo.sh
# 功能说明：OpenTelemetry演示应用部署脚本
# 适用场景：部署OpenTelemetry Astronomy Shop Demo
# 使用方法：在master1上执行
###############################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo -e "  OpenTelemetry演示应用部署"
echo -e "==========================================${NC}"
echo ""

#-------------------------------------------------------------------------------
# 1. 添加OpenTelemetry Helm仓库
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[1] 添加OpenTelemetry Helm仓库 ${NC}"
echo "----------------------------------------------"

helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

echo -e "${GREEN}✓ Helm仓库添加完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 2. 创建演示命名空间
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[2] 创建演示命名空间 ${NC}"
echo "----------------------------------------------"

kubectl create namespace demo || true

echo -e "${GREEN}✓ 命名空间创建完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 3. 部署OpenTelemetry Demo
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[3] 部署OpenTelemetry Demo ${NC}"
echo "----------------------------------------------"

helm install my-otel-demo open-telemetry/opentelemetry-demo \
    --namespace demo \
    --version 0.40.0

echo -e "${GREEN}✓ OpenTelemetry Demo部署完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 4. 等待部署完成
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[4] 等待部署完成 ${NC}"
echo "----------------------------------------------"

echo "等待frontend Pod启动..."
kubectl wait --namespace demo \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/name=frontend \
    --timeout=300s

echo -e "${GREEN}✓ 部署完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 5. 配置Ingress
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[5] 配置Ingress ${NC}"
echo "----------------------------------------------"

cat > frontend-ingress.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: frontend-ingress
  namespace: demo
spec:
  ingressClassName: nginx
  rules:
  - host: shop.example.com
    http:
      paths:
      - pathType: Prefix
        path: /
        backend:
          service:
            name: frontend
            port:
              number: 80
EOF

kubectl apply -f frontend-ingress.yaml

echo -e "${GREEN}✓ Ingress配置完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 6. 验证部署
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[6] 验证部署 ${NC}"
echo "----------------------------------------------"

echo "查看演示应用Pod状态:"
kubectl get pods -n demo

echo ""
echo "查看演示应用服务:"
kubectl get svc -n demo

echo ""
echo "访问地址:"
echo "  http://shop.example.com (需要配置hosts)"
echo "  在本地hosts添加: 192.168.1.51 shop.example.com"

echo -e "${GREEN}✓ 验证完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 完成总结
#-------------------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo -e "  演示应用部署完成"
echo -e "==========================================${NC}"
echo ""

echo "已部署组件:"
echo "  ✓ OpenTelemetry Demo - 演示应用"
echo "  ✓ frontend - 前端服务"
echo "  ✓ 后端微服务组件"
echo ""

echo "访问地址:"
echo "  http://shop.example.com"
echo ""

echo "配置说明:"
echo "  在本地电脑的hosts文件中添加:"
echo "    192.168.1.51 shop.example.com"
echo ""

echo -e "${BLUE}==========================================${NC}"