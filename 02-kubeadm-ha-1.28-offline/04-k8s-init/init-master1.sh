#!/bin/bash

###############################################################################
# 脚本名称：init-master1.sh
# 功能说明：Kubernetes集群初始化脚本（在master1上执行）
# 适用场景：初始化第一个控制平面节点
# 使用方法：sudo ./init-master1.sh
###############################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo -e "  Kubernetes集群初始化"
echo -e "==========================================${NC}"
echo ""

#-------------------------------------------------------------------------------
# 1. 创建kubeadm配置文件
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[1] 创建kubeadm配置文件 ${NC}"
echo "----------------------------------------------"

cat > kubeadm-config.yaml << 'EOF'
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "192.168.1.51"
  bindPort: 6443
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.28.0
imageRepository: 192.168.1.61/registry.k8s.io
networking:
  podSubnet: "10.244.0.0/16"
etcd:
  local:
    dataDir: /data/etcd
    extraArgs:
      snapshot-count: "10000"
      auto-compaction-retention: "1"
      quota-backend-bytes: "4294967296"
dns:
  imageRepository: 192.168.1.61/registry.k8s.io/coredns
  imageTag: v1.10.1
EOF

echo "kubeadm-config.yaml 创建完成"
cat kubeadm-config.yaml
echo ""

#-------------------------------------------------------------------------------
# 2. 初始化集群
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[2] 初始化Kubernetes集群 ${NC}"
echo "----------------------------------------------"

# 如果之前有配置，先清理
kubeadm reset -f || true
rm -rf /etc/kubernetes /var/lib/etcd /var/lib/kubelet ~/.kube
iptables -F && iptables -t nat -F && iptables -t mangle -F

# 初始化集群
kubeadm init --config kubeadm-config.yaml --upload-certs

echo -e "${GREEN}✓ 集群初始化完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 3. 配置kubectl
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[3] 配置kubectl ${NC}"
echo "----------------------------------------------"

mkdir -p ~/.kube
cp /etc/kubernetes/admin.conf ~/.kube/config
chown $(id -u):$(id -g) ~/.kube/config

# 验证kubectl
kubectl get nodes

echo -e "${GREEN}✓ kubectl配置完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 4. 显示加入命令
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[4] 显示节点加入命令 ${NC}"
echo "----------------------------------------------"

echo "Worker节点加入命令:"
kubeadm token create --print-join-command

echo ""
echo "控制平面节点加入命令（需要证书密钥）:"
CERT_KEY=$(kubeadm init phase upload-certs --upload-certs | tail -1)
echo "kubeadm join 192.168.1.51:6443 --token <token> \\"
echo "    --discovery-token-ca-cert-hash sha256:<hash> \\"
echo "    --control-plane --certificate-key $CERT_KEY"

echo -e "${GREEN}✓ 加入命令已生成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 完成总结
#-------------------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo -e "  Kubernetes初始化完成"
echo -e "==========================================${NC}"
echo ""

echo "下一步操作:"
echo "  1. 在其他master节点执行控制平面加入命令"
echo "  2. 在worker节点执行worker加入命令"
echo "  3. 安装Calico网络插件"
echo ""

echo "管理命令:"
echo "  kubectl get nodes        # 查看节点"
echo "  kubectl get pods -A      # 查看所有Pod"
echo "  kubectl cluster-info     # 集群信息"
echo ""

echo -e "${BLUE}==========================================${NC}"