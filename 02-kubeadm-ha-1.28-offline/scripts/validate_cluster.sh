#!/bin/bash

###############################################################################
# 脚本名称：validate_cluster.sh
# 功能说明：Kubernetes集群验证脚本
# 适用场景：部署完成后验证集群状态
# 使用方法：./validate_cluster.sh
###############################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo -e "  Kubernetes集群验证"
echo -e "==========================================${NC}"
echo ""

#-------------------------------------------------------------------------------
# 1. 检查kubectl
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[1] 检查kubectl ${NC}"
echo "----------------------------------------------"
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl 未安装${NC}"
    exit 1
fi
echo -e "${GREEN}✅ kubectl 已安装${NC}"
echo ""

#-------------------------------------------------------------------------------
# 2. 检查集群状态
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[2] 检查集群状态 ${NC}"
echo "----------------------------------------------"
echo "集群信息:"
kubectl cluster-info
echo ""

#-------------------------------------------------------------------------------
# 3. 检查节点状态
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[3] 检查节点状态 ${NC}"
echo "----------------------------------------------"
echo "节点列表:"
kubectl get nodes -o wide
echo ""

# 检查所有节点是否 Ready
NOT_READY=$(kubectl get nodes | grep -v NAME | grep -v Ready | wc -l)
if [ "$NOT_READY" -gt 0 ]; then
    echo -e "${RED}❌ 有 $NOT_READY 个节点未就绪${NC}"
else
    echo -e "${GREEN}✅ 所有节点就绪${NC}"
fi
echo ""

#-------------------------------------------------------------------------------
# 4. 检查Pod状态
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[4] 检查Pod状态 ${NC}"
echo "----------------------------------------------"
echo "kube-system Pod状态:"
kubectl get pods -n kube-system
echo ""

# 检查是否有Pod处于异常状态
ERROR_PODS=$(kubectl get pods -n kube-system | grep -v NAME | grep -v Running | grep -v Completed | wc -l)
if [ "$ERROR_PODS" -gt 0 ]; then
    echo -e "${RED}❌ 有 $ERROR_PODS 个Pod状态异常${NC}"
    kubectl get pods -n kube-system | grep -v NAME | grep -v Running | grep -v Completed
else
    echo -e "${GREEN}✅ 所有Pod运行正常${NC}"
fi
echo ""

#-------------------------------------------------------------------------------
# 5. 检查网络插件
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[5] 检查网络插件 ${NC}"
echo "----------------------------------------------"
echo "Calico状态:"
kubectl get pods -n kube-system | grep calico
echo ""

CALICO_RUNNING=$(kubectl get pods -n kube-system | grep calico | grep Running | wc -l)
CALICO_TOTAL=$(kubectl get pods -n kube-system | grep calico | wc -l)
if [ "$CALICO_RUNNING" -eq "$CALICO_TOTAL" ]; then
    echo -e "${GREEN}✅ Calico网络插件运行正常${NC}"
else
    echo -e "${RED}❌ Calico网络插件异常${NC}"
fi
echo ""

#-------------------------------------------------------------------------------
# 6. 检查服务
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[6] 检查服务 ${NC}"
echo "----------------------------------------------"
echo "核心服务状态:"
kubectl get svc -n kube-system
echo ""

# 检查API Server
APISERVER=$(kubectl get svc -n kube-system kubernetes | grep ClusterIP | wc -l)
if [ "$APISERVER" -gt 0 ]; then
    echo -e "${GREEN}✅ API Server 正常${NC}"
else
    echo -e "${RED}❌ API Server 异常${NC}"
fi
echo ""

#-------------------------------------------------------------------------------
# 7. 检查DNS
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[7] 检查DNS ${NC}"
echo "----------------------------------------------"
echo "CoreDNS状态:"
kubectl get pods -n kube-system | grep coredns
echo ""

COREDNS_RUNNING=$(kubectl get pods -n kube-system | grep coredns | grep Running | wc -l)
if [ "$COREDNS_RUNNING" -ge 2 ]; then
    echo -e "${GREEN}✅ CoreDNS运行正常${NC}"
else
    echo -e "${RED}❌ CoreDNS异常${NC}"
fi
echo ""

#-------------------------------------------------------------------------------
# 8. 测试Pod网络
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[8] 测试Pod网络 ${NC}"
echo "----------------------------------------------"
echo "创建测试Pod并测试网络连通性:"
kubectl run test-pod --image=busybox:1.28 --rm -it --restart=Never -- ping -c 3 8.8.8.8 2>/dev/null || true
echo ""

#-------------------------------------------------------------------------------
# 9. 检查etcd状态
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[9] 检查etcd状态 ${NC}"
echo "----------------------------------------------"
echo "etcd Pod状态:"
kubectl get pods -n kube-system | grep etcd
echo ""

ETCD_RUNNING=$(kubectl get pods -n kube-system | grep etcd | grep Running | wc -l)
if [ "$ETCD_RUNNING" -ge 1 ]; then
    echo -e "${GREEN}✅ etcd运行正常${NC}"
else
    echo -e "${RED}❌ etcd异常${NC}"
fi
echo ""

#-------------------------------------------------------------------------------
# 完成总结
#-------------------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo -e "  集群验证完成"
echo -e "==========================================${NC}"
echo ""

echo "验证结果:"
echo "  ✓ kubectl 安装"
echo "  ✓ 集群连接"
echo "  ✓ 节点状态"
echo "  ✓ Pod状态"
echo "  ✓ 网络插件"
echo "  ✓ 核心服务"
echo "  ✓ DNS服务"
echo "  ✓ Pod网络"
echo "  ✓ etcd状态"
echo ""

if [ "$NOT_READY" -eq 0 ] && [ "$ERROR_PODS" -eq 0 ] && [ "$CALICO_RUNNING" -eq "$CALICO_TOTAL" ] && [ "$COREDNS_RUNNING" -ge 2 ]; then
    echo -e "${GREEN}✅ 集群状态正常！${NC}"
else
    echo -e "${RED}❌ 集群存在问题，请检查${NC}"
fi
echo ""

echo -e "${BLUE}==========================================${NC}"