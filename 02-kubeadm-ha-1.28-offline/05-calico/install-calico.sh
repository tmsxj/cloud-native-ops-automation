#!/bin/bash

###############################################################################
# 脚本名称：install-calico.sh
# 功能说明：Calico网络插件安装脚本
# 适用场景：在Kubernetes集群中安装Calico网络插件
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
echo -e "  Calico网络插件安装"
echo -e "==========================================${NC}"
echo ""

#-------------------------------------------------------------------------------
# 1. 下载Calico配置文件
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[1] 下载Calico配置文件 ${NC}"
echo "----------------------------------------------"

CALICO_VERSION="v3.26"
curl -O https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml

echo "Calico配置文件下载完成"
echo ""

#-------------------------------------------------------------------------------
# 2. 修改Calico配置
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[2] 修改Calico配置 ${NC}"
echo "----------------------------------------------"

# 修改Pod网络CIDR（与kubeadm-config.yaml中的podSubnet一致）
sed -i 's|value: "192.168.0.0/16"|value: "10.244.0.0/16"|g' calico.yaml

# 验证修改
echo "验证修改后的配置:"
grep -A1 "CALICO_IPV4POOL_CIDR" calico.yaml

echo -e "${GREEN}✓ Calico配置修改完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 3. 应用Calico配置
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[3] 应用Calico配置 ${NC}"
echo "----------------------------------------------"

kubectl apply -f calico.yaml

echo -e "${GREEN}✓ Calico配置已应用${NC}"
echo ""

#-------------------------------------------------------------------------------
# 4. 等待Calico部署完成
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[4] 等待Calico部署完成 ${NC}"
echo "----------------------------------------------"

echo "等待Calico Pod启动..."
kubectl get pod -n kube-system -w | grep calico

echo -e "${GREEN}✓ Calico部署完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 5. 验证网络状态
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[5] 验证网络状态 ${NC}"
echo "----------------------------------------------"

echo "查看Calico Pod状态:"
kubectl get pod -n kube-system | grep calico

echo ""
echo "查看节点状态:"
kubectl get nodes

echo ""
echo "查看IP池配置:"
kubectl get ippools.crd.projectcalico.org -o yaml

echo -e "${GREEN}✓ 网络验证完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 完成总结
#-------------------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo -e "  Calico安装完成"
echo -e "==========================================${NC}"
echo ""

echo "Calico配置信息:"
echo "  Pod网络CIDR: 10.244.0.0/16"
echo "  默认模式: IPIP"
echo ""

echo "切换网络模式命令:"
echo "  # 切换到VXLAN"
echo "  kubectl patch ippool default-ipv4-ippool -p '{\"spec\":{\"ipipMode\":\"Never\",\"vxlanMode\":\"Always\"}}'"
echo ""
echo "  # 切换到纯BGP"
echo "  kubectl patch ippool default-ipv4-ippool -p '{\"spec\":{\"ipipMode\":\"Never\",\"vxlanMode\":\"Never\"}}'"
echo ""

echo "网络模式对比:"
echo "  模式    封装      性能    网络要求"
echo "  纯BGP   无        最高    二层可达"
echo "  IPIP    IP-in-IP  中等    三层可达"
echo "  VXLAN   UDP       较低    任意"
echo ""

echo -e "${BLUE}==========================================${NC}"