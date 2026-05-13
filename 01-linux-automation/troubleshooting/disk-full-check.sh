#!/bin/bash

###############################################################################
# 脚本名称：disk-full-check.sh
# 功能说明：排查磁盘空间被写满的问题
# 适用场景：磁盘空间不足、无法写入文件、服务启动失败
# 使用方法：sudo ./disk-full-check.sh
# 输出说明：显示各分区的空间使用情况，异常项用红色标注
###############################################################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo -e "  磁盘空间使用情况排查"
echo -e "==========================================${NC}"
echo ""

#-------------------------------------------------------------------------------
# 检查1：查看所有分区的空间使用情况
# 目的：快速了解各分区的磁盘使用率
# 原理：df -h 显示每个挂载点的总空间、已用空间、可用空间和使用率
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[1] 所有分区空间使用概览 ${NC}"
echo "命令: df -h"
echo "----------------------------------------------"
df -h | grep -v "tmpfs\|devtmpfs\|loop\|squashfs" | column -t

echo ""
# 检查是否有分区使用率超过阈值
USAGE_THRESHOLD=90
echo "使用率超过 ${USAGE_THRESHOLD}% 的分区:"
df -h | grep -v "tmpfs\|devtmpfs\|loop\|squashfs" | tail -n +2 | while read line; do
    usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
    mount=$(echo "$line" | awk '{print $6}')
    if [ "$usage" -ge "$USAGE_THRESHOLD" ]; then
        echo -e "  ${RED}⚠ $mount: ${usage}%${NC}"
    fi
done
echo ""

#-------------------------------------------------------------------------------
# 检查2：查看 inode 使用情况
# 目的：小文件过多时，即使磁盘有空间也会因 inode 耗尽而无法创建文件
# 原理：df -i 显示 inode 使用情况
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[2] Inode 使用情况检查 ${NC}"
echo "命令: df -i"
echo "----------------------------------------------"
df -i | grep -v "tmpfs\|devtmpfs\|loop\|squashfs"

echo ""
INODE_THRESHOLD=90
echo "Inode 使用率超过 ${INODE_THRESHOLD}% 的分区:"
df -i | grep -v "tmpfs\|devtmpfs\|loop\|squashfs" | tail -n +2 | while read line; do
    usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
    mount=$(echo "$line" | awk '{print $6}')
    if [ "$usage" -ge "$INODE_THRESHOLD" ]; then
        echo -e "  ${RED}⚠ $mount inode: ${usage}%${NC}"
    fi
done
echo ""

#-------------------------------------------------------------------------------
# 检查3：查找占用空间最大的目录
# 目的：快速定位哪些目录占用了大量磁盘空间
# 原理：du -sh 列出各目录占用空间，按大小排序
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[3] 查找占用空间最大的目录 (深度1) ${NC}"
echo "命令: du -sh /* 2>/dev/null | sort -rh | head -20"
echo "----------------------------------------------"
du -sh /* 2>/dev/null | sort -rh | head -20
echo ""

#-------------------------------------------------------------------------------
# 检查4：查找大文件
# 目的：找出具体是哪些大文件占用了空间
# 原理：find 命令可以按大小筛选文件
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[4] 查找大文件 (超过100MB) ${NC}"
echo "命令: find / -type f -size +100M -exec ls -lh {} \\; 2>/dev/null | awk '{print \$5, \$9}'"
echo "----------------------------------------------"
echo "正在扫描系统中的大文件（可能需要一些时间）..."
find / -type f -size +100M -exec ls -lh {} \; 2>/dev/null | awk '{print $5, $9}' | sort -rh | head -30
echo ""

#-------------------------------------------------------------------------------
# 检查5：查找最近修改的大文件
# 目的：定位哪些最近变大的文件，可能是导致磁盘满的元凶
# 原理：find -mtime 查找指定时间内修改过的文件
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[5] 最近修改的大文件 (7天内，超过50MB) ${NC}"
echo "命令: find / -type f -mtime -7 -size +50M -exec ls -lht {} \\; 2>/dev/null"
echo "----------------------------------------------"
find / -type f -mtime -7 -size +50M -exec ls -lh {} \; 2>/dev/null | head -20
echo ""

#-------------------------------------------------------------------------------
# 检查6：检查系统日志目录大小
# 目的：日志文件是磁盘空间的主要消耗者
# 原理：/var/log 目录下通常存储系统日志，可能快速膨胀
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[6] 系统日志目录分析 ${NC}"
echo "命令: du -sh /var/log/* | sort -rh"
echo "----------------------------------------------"
if [ -d /var/log ]; then
    echo ">>> /var/log 目录大小:"
    du -sh /var/log/* 2>/dev/null | sort -rh | head -15
    echo ""

    # 查找异常大的日志文件
    echo ">>> 单文件超过100MB的日志文件:"
    find /var/log -type f -size +100M -exec ls -lh {} \; 2>/dev/null | awk '{print $5, $9}'
    echo ""

    # 检查日志增长速度（最近1小时的修改）
    echo ">>> 最近1小时内修改的日志文件:"
    find /var/log -type f -mmin -60 -exec ls -lh {} \; 2>/dev/null | awk '{print $6, $7, $8, $9}' | head -10
else
    echo "  /var/log 目录不存在或无权限访问"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查7：检查应用程序日志
# 目的：应用程序日志往往比系统日志更大
# 原理：常见应用日志位置：/opt、/home、/srv 等
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[7] 应用程序日志检查 ${NC}"
echo "----------------------------------------------"

# 检查常见应用日志位置
for path in /opt /srv /home; do
    if [ -d "$path" ]; then
        echo ">>> $path 下的大文件/目录:"
        du -sh $path/* 2>/dev/null | sort -rh | head -10
        echo ""
    fi
done

#-------------------------------------------------------------------------------
# 检查8：检查临时目录
# 目的：/tmp 和 /var/tmp 可能存储临时文件但未被清理
# 原理：检查临时目录大小和文件数量
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[8] 临时目录使用情况 ${NC}"
echo "----------------------------------------------"

for tmpdir in /tmp /var/tmp; do
    if [ -d "$tmpdir" ]; then
        echo ">>> $tmpdir:"
        echo "  总大小: $(du -sh $tmpdir 2>/dev/null | cut -f1)"
        echo "  文件数量: $(find $tmpdir -type f 2>/dev/null | wc -l)"
        echo "  旧文件 (>7天未访问): $(find $tmpdir -type f -atime +7 2>/dev/null | wc -l)"
    fi
done
echo ""

#-------------------------------------------------------------------------------
# 检查9：检查邮件队列
# 目的：邮件队列堆积也会占用大量磁盘空间
# 原理：Postfix/Sendmail 等邮件服务器的队列可能很大
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[9] 邮件队列检查 ${NC}"
echo "----------------------------------------------"

# Postfix 队列
if [ -d /var/spool/postfix ]; then
    echo "Postfix 邮件队列:"
    for queue in incoming active deferred hold; do
        if [ -d "/var/spool/postfix/$queue" ]; then
            count=$(find /var/spool/postfix/$queue -type f 2>/dev/null | wc -l)
            size=$(du -sh /var/spool/postfix/$queue 2>/dev/null | cut -f1)
            echo "  $queue: $count 封邮件 ($size)"
        fi
    done
fi

# 查看邮件日志大小
if [ -f /var/log/maillog ]; then
    echo ""
    echo "邮件日志: $(ls -lh /var/log/maillog 2>/dev/null | awk '{print $5, $9}')"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查10：检查数据库数据目录
# 目的：MySQL、PostgreSQL 等数据库数据目录可能很大
# 原理：检查数据库默认数据目录的大小
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[10] 数据库数据目录检查 ${NC}"
echo "----------------------------------------------"

# MySQL
if [ -d /var/lib/mysql ]; then
    echo "MySQL 数据目录: $(du -sh /var/lib/mysql 2>/dev/null | cut -f1)"
    echo "  MySQL 数据库大小:"
    du -sh /var/lib/mysql/* 2>/dev/null | sort -rh | head -10
fi

# PostgreSQL
if [ -d /var/lib/postgresql ]; then
    echo ""
    echo "PostgreSQL 数据目录: $(du -sh /var/lib/postgresql 2>/dev/null | cut -f1)"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查11：检查 Docker 相关空间占用
# 目的：Docker 的镜像、容器、数据卷可能占用大量空间
# 原理：docker system df 显示 Docker 空间使用情况
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[11] Docker 空间占用检查 ${NC}"
echo "命令: docker system df -v"
echo "----------------------------------------------"
if command -v docker &> /dev/null; then
    docker system df 2>/dev/null || echo "Docker 命令执行失败，可能需要root权限"
    echo ""
    echo "Docker 各类型资源:"
    docker system df 2>/dev/null | grep -E "TYPE|Images|Containers|Local Volumes|Build Cache"
else
    echo "Docker 未安装或不在PATH中"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查12：检查已删除但仍被占用的文件
# 目的：文件删除后，如果进程仍打开着，磁盘空间不会释放
# 原理：lsof +L1 列出已删除但仍被进程占用的文件
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[12] 已删除但仍被占用的文件 ${NC}"
echo "命令: lsof +L1 或 lsof | grep deleted"
echo "----------------------------------------------"
if command -v lsof &> /dev/null; then
    echo "已删除但仍被进程占用的文件（会占用磁盘空间）:"
    lsof +L1 2>/dev/null | head -20 || echo "无已删除但被占用的文件"
    echo ""
    echo "总大小:"
    lsof +L1 2>/dev/null | awk 'NR>1 {sum+=$7} END {print sum}' | awk '{printf "%.2f MB\n", $1/1024/1024}'
else
    echo "lsof 未安装，跳过此检查"
fi
echo ""

#-------------------------------------------------------------------------------
# 排查结论
#-------------------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo -e "  磁盘空间排查结论与建议"
echo -e "==========================================${NC}"
echo ""

echo "【快速清理命令】"
echo ""
echo "# 清理旧日志"
echo "journalctl --vacuum-time=7d"
echo "find /var/log -type f -name '*.log' -mtime +7 -delete"
echo ""
echo "# 清理临时文件"
echo "rm -rf /tmp/*"
echo "find /tmp -type f -atime +7 -delete 2>/dev/null"
echo ""
echo "# 清理包管理器缓存"
echo "apt/apt-get/yum clean all     # Debian/Ubuntu 或 CentOS/RHEL"
echo "dnf clean all"
echo ""
echo "# 清理 Docker (谨慎使用)"
echo "docker system prune -a -f     # 删除所有未使用的镜像和容器"
echo "docker volume prune -f        # 删除未使用的卷"
echo ""

echo "【预防措施】"
echo "  - 配置 logrotate 自动轮转日志"
echo "  - 设置磁盘空间监控告警 (阈值: 85%)"
echo "  - 定期检查和清理临时文件"
echo "  - 应用程序日志配置合理的大小限制"
echo "  - 使用 LVM 便于在线扩容"
echo ""

echo -e "${BLUE}=========================================="
echo -e "  磁盘空间排查完成"
echo -e "==========================================${NC}"