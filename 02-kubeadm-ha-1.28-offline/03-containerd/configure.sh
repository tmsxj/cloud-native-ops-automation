#!/bin/bash

###############################################################################
# 脚本名称：configure.sh
# 功能说明：Containerd配置脚本
# 适用场景：在所有K8s节点上配置containerd使用Harbor镜像
# 使用方法：sudo ./configure.sh
###############################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo -e "  Containerd配置脚本"
echo -e "==========================================${NC}"
echo ""

#-------------------------------------------------------------------------------
# 1. 配置containerd config.toml
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[1] 配置containerd config.toml ${NC}"
echo "----------------------------------------------"

# 修改 sandbox_image 指向Harbor
sed -i 's|sandbox_image = ".*"|sandbox_image = "192.168.1.61/registry.k8s.io/pause:3.9"|' /etc/containerd/config.toml

# 设置 SystemdCgroup = true
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# 设置 registry config_path
sed -i 's|config_path = ""|config_path = "/etc/containerd/certs.d"|' /etc/containerd/config.toml

# 设置 transfer config_path
sed -i '/\[plugins."io.containerd.transfer.v1.local"\]/,/^$/ s|config_path = ""|config_path = "/etc/containerd/certs.d"|' /etc/containerd/config.toml

echo "containerd配置修改完成"
echo ""

#-------------------------------------------------------------------------------
# 2. 配置Harbor仓库的hosts.toml
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[2] 配置Harbor仓库hosts.toml ${NC}"
echo "----------------------------------------------"

HARBOR_CERTS_DIR="/etc/containerd/certs.d/192.168.1.61"
mkdir -p $HARBOR_CERTS_DIR

cat > ${HARBOR_CERTS_DIR}/hosts.toml << 'EOF'
server = "http://192.168.1.61"

[host."http://192.168.1.61"]
  capabilities = ["pull", "resolve"]
EOF

echo "Harbor仓库配置完成"
echo ""

#-------------------------------------------------------------------------------
# 3. 重启containerd服务
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[3] 重启containerd服务 ${NC}"
echo "----------------------------------------------"

systemctl restart containerd
systemctl enable containerd

echo -e "${GREEN}✓ containerd服务已重启${NC}"
echo ""

#-------------------------------------------------------------------------------
# 4. 验证配置
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[4] 验证containerd配置 ${NC}"
echo "----------------------------------------------"

# 查看配置
echo "containerd配置验证:"
cat /etc/containerd/config.toml | grep -E "sandbox_image|SystemdCgroup|config_path"

echo ""
echo "hosts.toml内容:"
cat /etc/containerd/certs.d/192.168.1.61/hosts.toml

echo ""
echo "containerd状态:"
systemctl status containerd | grep Active

echo -e "${GREEN}✓ containerd配置验证完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 完成总结
#-------------------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo -e "  Containerd配置完成"
echo -e "==========================================${NC}"
echo ""

echo "已完成以下配置:"
echo "  ✓ sandbox_image: 192.168.1.61/registry.k8s.io/pause:3.9"
echo "  ✓ SystemdCgroup: true"
echo "  ✓ registry config_path: /etc/containerd/certs.d"
echo "  ✓ Harbor仓库配置: /etc/containerd/certs.d/192.168.1.61/hosts.toml"
echo ""

echo "配置说明:"
echo "  - sandbox_image 指向本地Harbor的pause镜像"
echo "  - SystemdCgroup与kubelet cgroup驱动一致"
echo "  - hosts.toml允许通过HTTP访问Harbor"
echo ""

echo -e "${BLUE}==========================================${NC}"