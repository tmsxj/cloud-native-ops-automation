#!/bin/bash

###############################################################################
# 脚本名称：install-prometheus.sh
# 功能说明：Prometheus+Grafana监控部署脚本
# 适用场景：在Kubernetes集群中部署监控系统
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
echo -e "  Prometheus+Grafana监控部署"
echo -e "==========================================${NC}"
echo ""

#-------------------------------------------------------------------------------
# 1. 添加Helm仓库
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[1] 添加Helm仓库 ${NC}"
echo "----------------------------------------------"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

echo -e "${GREEN}✓ Helm仓库添加完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 2. 创建监控命名空间
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[2] 创建监控命名空间 ${NC}"
echo "----------------------------------------------"

kubectl create namespace monitoring || true

echo -e "${GREEN}✓ 命名空间创建完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 3. 安装kube-prometheus-stack
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[3] 安装kube-prometheus-stack ${NC}"
echo "----------------------------------------------"

helm install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --set prometheus.service.type=NodePort \
    --set grafana.service.type=NodePort \
    --set grafana.adminPassword=admin123 \
    --version 45.3.0

echo -e "${GREEN}✓ kube-prometheus-stack安装完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 4. 等待部署完成
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[4] 等待部署完成 ${NC}"
echo "----------------------------------------------"

echo "等待Prometheus Pod启动..."
kubectl wait --namespace monitoring \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/name=prometheus \
    --timeout=300s

echo "等待Grafana Pod启动..."
kubectl wait --namespace monitoring \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/name=grafana \
    --timeout=300s

echo -e "${GREEN}✓ 部署完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 5. 验证部署
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[5] 验证部署 ${NC}"
echo "----------------------------------------------"

echo "查看监控Pod状态:"
kubectl get pods -n monitoring

echo ""
echo "查看监控服务:"
kubectl get svc -n monitoring

echo ""
echo "Grafana访问地址:"
GRAFANA_PORT=$(kubectl get svc -n monitoring prometheus-grafana -o jsonpath='{.spec.ports[0].nodePort}')
echo "  http://192.168.1.51:${GRAFANA_PORT}"
echo "  用户名: admin"
echo "  密码: admin123"

echo -e "${GREEN}✓ 验证完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 完成总结
#-------------------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo -e "  监控部署完成"
echo -e "==========================================${NC}"
echo ""

echo "已部署组件:"
echo "  ✓ Prometheus - 指标收集"
echo "  ✓ Grafana - 可视化面板"
echo "  ✓ Alertmanager - 告警管理"
echo "  ✓ Node Exporter - 节点监控"
echo ""

echo "访问地址:"
echo "  Grafana: http://192.168.1.51:${GRAFANA_PORT}"
echo ""

echo "管理命令:"
echo "  kubectl get pods -n monitoring    # 查看Pod"
echo "  kubectl get svc -n monitoring     # 查看服务"
echo ""

echo -e "${BLUE}==========================================${NC}"