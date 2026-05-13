#!/bin/bash

###############################################################################
# 脚本名称：disk-clean.sh
# 功能说明：磁盘空间清理脚本
# 适用场景：磁盘空间不足时进行快速清理
# 使用方法：sudo ./disk-clean.sh
# 注意事项：需要 root 权限执行
###############################################################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo -e "  磁盘空间清理脚本"
echo -e "==========================================${NC}"
echo ""

#-------------------------------------------------------------------------------
# 1. 显示当前磁盘使用情况
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[1] 当前磁盘使用情况 ${NC}"
echo "----------------------------------------------"
df -h | grep -v "tmpfs\|devtmpfs\|loop"
echo ""

#-------------------------------------------------------------------------------
# 2. 清理系统日志
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[2] 清理系统日志 ${NC}"
echo "----------------------------------------------"

echo "清理 /var/log 目录..."
LOG_SIZE_BEFORE=$(du -sh /var/log | cut -f1)

# 清理旧日志文件
find /var/log -type f -name "*.log" -mtime +30 -delete
find /var/log -type f -name "*.gz" -mtime +14 -delete
find /var/log -type f -name "*.[0-9]" -mtime +7 -delete

# 清理空文件
find /var/log -type f -size 0 -delete

# 清理 journal 日志（保留7天）
if command -v journalctl &> /dev/null; then
    journalctl --vacuum-time=7d --vacuum-size=500M
fi

LOG_SIZE_AFTER=$(du -sh /var/log | cut -f1)
echo "清理前: $LOG_SIZE_BEFORE"
echo "清理后: $LOG_SIZE_AFTER"
echo -e "${GREEN}✓ 系统日志清理完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 3. 清理包管理器缓存
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[3] 清理包管理器缓存 ${NC}"
echo "----------------------------------------------"

if command -v apt &> /dev/null; then
    echo "清理 apt 缓存..."
    apt clean all
    apt autoremove -y
elif command -v yum &> /dev/null; then
    echo "清理 yum 缓存..."
    yum clean all
elif command -v dnf &> /dev/null; then
    echo "清理 dnf 缓存..."
    dnf clean all
fi
echo -e "${GREEN}✓ 包管理器缓存清理完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 4. 清理临时文件
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[4] 清理临时文件 ${NC}"
echo "----------------------------------------------"

echo "清理 /tmp 目录..."
find /tmp -type f -atime +7 -delete
find /tmp -type d -empty -delete

echo "清理 /var/tmp 目录..."
find /var/tmp -type f -atime +7 -delete
find /var/tmp -type d -empty -delete
echo -e "${GREEN}✓ 临时文件清理完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 5. 清理用户缓存
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[5] 清理用户缓存 ${NC}"
echo "----------------------------------------------"

echo "清理用户缓存目录..."
for userdir in /home/*; do
    if [ -d "$userdir" ]; then
        # 清理浏览器缓存
        find "$userdir/.cache" -type f -atime +30 -delete 2>/dev/null
        
        # 清理下载目录中超过30天的文件
        find "$userdir/Downloads" -type f -atime +30 -delete 2>/dev/null
    fi
done
echo -e "${GREEN}✓ 用户缓存清理完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 6. 清理已删除但仍被占用的文件
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[6] 清理已删除但仍被占用的文件 ${NC}"
echo "----------------------------------------------"

echo "查找已删除但仍被进程占用的文件..."
if command -v lsof &> /dev/null; then
    DELETED_FILES=$(lsof +L1 2>/dev/null | grep -E "^COMMAND|deleted")
    if [ -n "$DELETED_FILES" ]; then
        echo "$DELETED_FILES"
        echo ""
        echo "提示：这些文件已被删除但仍被进程占用，重启相关进程可释放空间"
    else
        echo "无已删除但被占用的文件"
    fi
else
    echo "lsof 未安装，跳过此检查"
fi
echo ""

#-------------------------------------------------------------------------------
# 7. 清理 Docker 资源（如安装）
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[7] 清理 Docker 资源 ${NC}"
echo "----------------------------------------------"

if command -v docker &> /dev/null; then
    echo "清理 Docker 未使用的资源..."
    docker system prune -a -f --volumes
    echo -e "${GREEN}✓ Docker 资源清理完成${NC}"
else
    echo "Docker 未安装，跳过"
fi
echo ""

#-------------------------------------------------------------------------------
# 8. 清理旧内核（如适用）
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[8] 清理旧内核 ${NC}"
echo "----------------------------------------------"

if command -v apt &> /dev/null; then
    echo "清理旧内核..."
    dpkg --list | grep linux-image | awk '{print $2}' | grep -v $(uname -r) | xargs apt-get purge -y 2>/dev/null || echo "无旧内核可清理"
elif command -v yum &> /dev/null; then
    echo "清理旧内核..."
    package-cleanup --oldkernels --count=1 -y 2>/dev/null || echo "无旧内核可清理"
fi
echo -e "${GREEN}✓ 旧内核清理完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 9. 显示清理后的磁盘使用情况
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[9] 清理后的磁盘使用情况 ${NC}"
echo "----------------------------------------------"
df -h | grep -v "tmpfs\|devtmpfs\|loop"
echo ""

#-------------------------------------------------------------------------------
# 完成总结
#-------------------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo -e "  磁盘清理完成"
echo -e "==========================================${NC}"
echo ""

echo "已完成以下清理:"
echo "  ✓ 系统日志 (保留最近30天)"
echo "  ✓ 包管理器缓存"
echo "  ✓ 临时文件 (超过7天)"
echo "  ✓ 用户缓存"
echo "  ✓ Docker 资源"
echo "  ✓ 旧内核"
echo ""

echo "建议后续操作:"
echo "  1. 定期运行此脚本（可加入 cron）"
echo "  2. 配置 logrotate 自动轮转日志"
echo "  3. 设置磁盘空间告警"
echo ""

echo -e "${BLUE}==========================================${NC}"