#!/bin/bash

###############################################################################
# 脚本名称：install.sh
# 功能说明：Harbor离线安装脚本
# 适用场景：在harbor节点（192.168.1.61）上安装Harbor私有仓库
# 使用方法：sudo ./install.sh
# 注意事项：需要先下载Harbor离线安装包
###############################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo -e "  Harbor离线安装脚本"
echo -e "==========================================${NC}"
echo ""

#-------------------------------------------------------------------------------
# 1. 安装Docker
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[1] 安装Docker ${NC}"
echo "----------------------------------------------"

# 添加Docker GPG密钥
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# 添加Docker仓库
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 更新并安装Docker
apt update -y
apt install -y docker-ce docker-ce-cli containerd.io

# 启动Docker并设置开机自启
systemctl start docker
systemctl enable docker

echo -e "${GREEN}✓ Docker安装完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 2. 创建Harbor目录并下载安装包
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[2] 下载Harbor离线安装包 ${NC}"
echo "----------------------------------------------"

HARBOR_VERSION="v2.9.0"
HARBOR_DIR="/data/harbor"
HARBOR_TAR="harbor-offline-installer-${HARBOR_VERSION}.tgz"

mkdir -p $HARBOR_DIR
cd $HARBOR_DIR

# 如果安装包不存在则下载
if [ ! -f $HARBOR_TAR ]; then
    echo "正在下载Harbor安装包..."
    wget -c --progress=bar "https://github.com/goharbor/harbor/releases/download/${HARBOR_VERSION}/${HARBOR_TAR}"
else
    echo "安装包已存在，跳过下载"
fi

# 解压安装包
echo "解压安装包..."
tar xzvf $HARBOR_TAR -C $HARBOR_DIR --strip-components=1

echo -e "${GREEN}✓ Harbor安装包准备完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 3. 生成Harbor配置文件
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[3] 生成Harbor配置文件 ${NC}"
echo "----------------------------------------------"

# 复制并修改配置文件
cp harbor.yml.tmpl harbor.yml

# 修改配置
sed -i "s/hostname: reg.mydomain.com/hostname: 192.168.1.61/" harbor.yml
sed -i "s/port: 443/# port: 443/" harbor.yml
sed -i "s/port: 80/port: 80/" harbor.yml
sed -i "s/harbor_admin_password: Harbor12345/harbor_admin_password: Harbor12345/" harbor.yml
sed -i "s|data_volume: /data|data_volume: /data|" harbor.yml

# 显示配置文件
echo "Harbor配置文件内容:"
cat harbor.yml | grep -v "^#" | grep -v "^$"

echo -e "${GREEN}✓ Harbor配置文件生成完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 4. 安装Harbor
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[4] 安装Harbor ${NC}"
echo "----------------------------------------------"

# 执行安装
./install.sh

echo -e "${GREEN}✓ Harbor安装完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 5. 验证Harbor安装
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[5] 验证Harbor安装 ${NC}"
echo "----------------------------------------------"

# 查看容器状态
echo "Harbor容器状态:"
docker compose ps

# 本地访问测试
echo ""
echo "本地访问测试:"
curl -s http://127.0.0.1:80 | head -5

# 登录测试
echo ""
echo "登录测试:"
echo "Harbor12345" | docker login -u admin --password-stdin 192.168.1.61

echo -e "${GREEN}✓ Harbor验证完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 完成总结
#-------------------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo -e "  Harbor安装完成"
echo -e "==========================================${NC}"
echo ""

echo "Harbor配置信息:"
echo "  地址: http://192.168.1.61"
echo "  用户名: admin"
echo "  密码: Harbor12345"
echo "  数据目录: /data"
echo ""

echo "访问地址:"
echo "  浏览器访问: http://192.168.1.61"
echo ""

echo "管理命令:"
echo "  cd /data/harbor"
echo "  docker compose up -d      # 启动"
echo "  docker compose down       # 停止"
echo "  docker compose restart    # 重启"
echo ""

echo -e "${BLUE}==========================================${NC}"