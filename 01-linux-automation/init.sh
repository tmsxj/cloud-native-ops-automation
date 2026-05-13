#!/bin/bash

###############################################################################
# 脚本名称：init.sh
# 功能说明：Linux 系统初始化脚本
# 适用场景：新服务器部署后进行基础配置
# 使用方法：sudo ./init.sh
# 注意事项：需要 root 权限执行
###############################################################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo -e "  Linux 系统初始化脚本"
echo -e "==========================================${NC}"
echo ""

#-------------------------------------------------------------------------------
# 1. 配置主机名
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[1] 配置主机名 ${NC}"
echo "----------------------------------------------"
read -p "请输入主机名 (默认: $(hostname)): " HOSTNAME
HOSTNAME=${HOSTNAME:-$(hostname)}

echo "设置主机名为: $HOSTNAME"
hostnamectl set-hostname "$HOSTNAME"
echo "$HOSTNAME" > /etc/hostname

echo -e "${GREEN}✓ 主机名配置完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 2. 配置时区
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[2] 配置时区 ${NC}"
echo "----------------------------------------------"
echo "当前时区: $(timedatectl show --property=Timezone --value)"
echo ""
echo "可用时区列表（常用）:"
echo "  Asia/Shanghai    - 上海"
echo "  Asia/Beijing     - 北京"
echo "  UTC              - 协调世界时"
read -p "请输入时区 (默认: Asia/Shanghai): " TIMEZONE
TIMEZONE=${TIMEZONE:-Asia/Shanghai}

echo "设置时区为: $TIMEZONE"
timedatectl set-timezone "$TIMEZONE"
timedatectl set-ntp true

echo -e "${GREEN}✓ 时区配置完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 3. 更新系统软件
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[3] 更新系统软件 ${NC}"
echo "----------------------------------------------"
read -p "是否更新系统软件包? (y/N): " UPDATE
if [[ "$UPDATE" =~ ^[Yy]$ ]]; then
    echo "正在更新软件包..."
    if command -v apt &> /dev/null; then
        apt update -y && apt upgrade -y
    elif command -v yum &> /dev/null; then
        yum update -y
    elif command -v dnf &> /dev/null; then
        dnf update -y
    fi
    echo -e "${GREEN}✓ 系统更新完成${NC}"
else
    echo "跳过系统更新"
fi
echo ""

#-------------------------------------------------------------------------------
# 4. 安装常用工具
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[4] 安装常用工具 ${NC}"
echo "----------------------------------------------"

TOOLS=(
    "curl" "wget" "vim" "git" "tree" "htop"
    "net-tools" "iproute2" "sysstat" "lsof" "tcpdump"
)

for tool in "${TOOLS[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        echo "安装 $tool..."
        if command -v apt &> /dev/null; then
            apt install -y "$tool"
        elif command -v yum &> /dev/null; then
            yum install -y "$tool"
        elif command -v dnf &> /dev/null; then
            dnf install -y "$tool"
        fi
    else
        echo "$tool 已安装"
    fi
done

echo -e "${GREEN}✓ 常用工具安装完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 5. 配置 SSH
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[5] 配置 SSH ${NC}"
echo "----------------------------------------------"

read -p "是否禁用密码登录? (y/N): " DISABLE_PASSWORD
if [[ "$DISABLE_PASSWORD" =~ ^[Yy]$ ]]; then
    echo "禁用密码登录..."
    sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#PasswordAuthentication no/PasswordAuthentication no/' /etc/ssh/sshd_config
    systemctl restart sshd
    echo -e "${GREEN}✓ 密码登录已禁用${NC}"
else
    echo "保留密码登录"
fi

read -p "是否修改 SSH 端口? (y/N): " CHANGE_PORT
if [[ "$CHANGE_PORT" =~ ^[Yy]$ ]]; then
    read -p "请输入新的 SSH 端口: " SSH_PORT
    sed -i "s/^Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
    sed -i "s/^#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
    
    # 如果启用了防火墙，开放新端口
    if command -v ufw &> /dev/null; then
        ufw allow "$SSH_PORT"/tcp
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --add-port="$SSH_PORT"/tcp --permanent
        firewall-cmd --reload
    fi
    
    systemctl restart sshd
    echo -e "${GREEN}✓ SSH 端口已修改为 $SSH_PORT${NC}"
else
    echo "保持默认 SSH 端口"
fi
echo ""

#-------------------------------------------------------------------------------
# 6. 配置防火墙
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[6] 配置防火墙 ${NC}"
echo "----------------------------------------------"

read -p "是否启用防火墙? (y/N): " ENABLE_FIREWALL
if [[ "$ENABLE_FIREWALL" =~ ^[Yy]$ ]]; then
    if command -v ufw &> /dev/null; then
        echo "启用 ufw 防火墙..."
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow ssh
        ufw allow http
        ufw allow https
        ufw enable
    elif command -v firewall-cmd &> /dev/null; then
        echo "启用 firewalld 防火墙..."
        firewall-cmd --set-default-zone=public
        firewall-cmd --add-service=ssh --permanent
        firewall-cmd --add-service=http --permanent
        firewall-cmd --add-service=https --permanent
        firewall-cmd --reload
        systemctl enable --now firewalld
    fi
    echo -e "${GREEN}✓ 防火墙配置完成${NC}"
else
    echo "跳过防火墙配置"
fi
echo ""

#-------------------------------------------------------------------------------
# 7. 创建普通用户
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[7] 创建普通用户 ${NC}"
echo "----------------------------------------------"

read -p "是否创建普通用户? (y/N): " CREATE_USER
if [[ "$CREATE_USER" =~ ^[Yy]$ ]]; then
    read -p "请输入用户名: " USERNAME
    read -p "请输入用户密码: " -s PASSWORD
    echo ""
    
    useradd -m -s /bin/bash "$USERNAME"
    echo "$USERNAME:$PASSWORD" | chpasswd
    
    # 添加到 sudoers
    usermod -aG sudo "$USERNAME"
    
    echo -e "${GREEN}✓ 用户 $USERNAME 创建完成${NC}"
else
    echo "跳过用户创建"
fi
echo ""

#-------------------------------------------------------------------------------
# 8. 配置内核参数
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[8] 配置内核参数 ${NC}"
echo "----------------------------------------------"

read -p "是否优化内核参数? (y/N): " TUNE_KERNEL
if [[ "$TUNE_KERNEL" =~ ^[Yy]$ ]]; then
    echo "配置网络相关内核参数..."
    
    cat >> /etc/sysctl.conf << 'EOF'
# 网络优化
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_max_syn_backlog = 65535
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 262144

# 文件描述符
fs.file-max = 1000000
fs.nr_open = 1000000

# 内存优化
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
EOF
    
    sysctl -p
    echo -e "${GREEN}✓ 内核参数配置完成${NC}"
else
    echo "跳过内核参数优化"
fi
echo ""

#-------------------------------------------------------------------------------
# 9. 配置时间同步
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[9] 配置时间同步 ${NC}"
echo "----------------------------------------------"

echo "配置 NTP 时间同步..."
if command -v chronyd &> /dev/null; then
    systemctl enable --now chronyd
elif command -v ntpd &> /dev/null; then
    systemctl enable --now ntpd
else
    if command -v apt &> /dev/null; then
        apt install -y chrony
        systemctl enable --now chronyd
    elif command -v yum &> /dev/null; then
        yum install -y chrony
        systemctl enable --now chronyd
    fi
fi

timedatectl status
echo -e "${GREEN}✓ 时间同步配置完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 完成总结
#-------------------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo -e "  系统初始化完成"
echo -e "==========================================${NC}"
echo ""

echo "已完成以下配置:"
echo "  ✓ 主机名: $HOSTNAME"
echo "  ✓ 时区: $TIMEZONE"
echo "  ✓ 常用工具安装"
echo "  ✓ SSH 配置"
echo "  ✓ 防火墙配置"
echo "  ✓ 内核参数优化"
echo "  ✓ 时间同步配置"
echo ""

echo "建议后续操作:"
echo "  1. 配置 SSH 密钥登录"
echo "  2. 安装 fail2ban 防暴力破解"
echo "  3. 配置日志轮转"
echo "  4. 设置监控告警"
echo ""

echo -e "${BLUE}==========================================${NC}"