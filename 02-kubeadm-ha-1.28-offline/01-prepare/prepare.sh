#!/bin/bash

###############################################################################
# 脚本名称：prepare.sh
# 功能说明：所有节点环境准备脚本
# 适用场景：新服务器初始化，配置主机名、时区、依赖等
# 使用方法：在所有节点上执行，或通过Ansible批量执行
###############################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo -e "  环境准备脚本"
echo -e "==========================================${NC}"
echo ""

#-------------------------------------------------------------------------------
# 1. 更新系统
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[1] 更新系统软件包 ${NC}"
echo "----------------------------------------------"
apt update -y
echo -e "${GREEN}✓ 系统更新完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 2. 安装依赖包
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[2] 安装依赖包 ${NC}"
echo "----------------------------------------------"
apt install -y apt-transport-https ca-certificates curl software-properties-common \
    vim tree htop net-tools iproute2 sysstat lsof tcpdump ntpdate
echo -e "${GREEN}✓ 依赖包安装完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 3. 关闭防火墙和SELinux
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[3] 关闭防火墙和SELinux ${NC}"
echo "----------------------------------------------"

# 关闭 ufw
if command -v ufw &> /dev/null; then
    ufw disable || true
fi

# 关闭 firewalld
if command -v firewall-cmd &> /dev/null; then
    systemctl stop firewalld || true
    systemctl disable firewalld || true
fi

# 关闭 SELinux
if command -v setenforce &> /dev/null; then
    setenforce 0 || true
    sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config || true
fi

echo -e "${GREEN}✓ 防火墙和SELinux已关闭${NC}"
echo ""

#-------------------------------------------------------------------------------
# 4. 配置内核参数
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[4] 配置内核参数 ${NC}"
echo "----------------------------------------------"

cat > /etc/sysctl.d/99-k8s.conf << 'EOF'
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
vm.swappiness = 0
EOF

sysctl --system
echo -e "${GREEN}✓ 内核参数配置完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 5. 禁用swap
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[5] 禁用swap ${NC}"
echo "----------------------------------------------"
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
echo -e "${GREEN}✓ swap已禁用${NC}"
echo ""

#-------------------------------------------------------------------------------
# 6. 配置时区
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[6] 配置时区 ${NC}"
echo "----------------------------------------------"
timedatectl set-timezone Asia/Shanghai
timedatectl set-ntp true
echo "当前时区: $(timedatectl show --property=Timezone --value)"
echo -e "${GREEN}✓ 时区配置完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 7. 配置SSH免密登录（可选）
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[7] 配置SSH免密登录 ${NC}"
echo "----------------------------------------------"
echo "请确保已手动配置SSH免密登录到所有节点"
echo "或使用以下命令生成密钥对:"
echo "  ssh-keygen -t rsa -b 4096 -N ''"
echo "  ssh-copy-id user@node-ip"
echo -e "${GREEN}✓ SSH配置提示完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 8. 安装containerd依赖
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[8] 安装containerd依赖 ${NC}"
echo "----------------------------------------------"
apt install -y containerd.io
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
echo -e "${GREEN}✓ containerd依赖安装完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 完成总结
#-------------------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo -e "  环境准备完成"
echo -e "==========================================${NC}"
echo ""

echo "已完成以下配置:"
echo "  ✓ 系统更新"
echo "  ✓ 依赖包安装"
echo "  ✓ 防火墙和SELinux关闭"
echo "  ✓ 内核参数配置"
echo "  ✓ swap禁用"
echo "  ✓ 时区配置（Asia/Shanghai）"
echo "  ✓ containerd依赖安装"
echo ""

echo "下一步:"
echo "  1. 配置主机名（根据节点角色）"
echo "  2. 在harbor节点部署Harbor"
echo "  3. 配置containerd使用Harbor镜像"
echo ""

echo -e "${BLUE}==========================================${NC}"