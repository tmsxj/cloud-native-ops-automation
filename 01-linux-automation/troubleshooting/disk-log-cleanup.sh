#!/bin/bash

###############################################################################
# 脚本名称：disk-log-cleanup.sh
# 功能说明：处理日志文件快速增长的问题
# 适用场景：日志文件占用大量空间、需要清理历史日志、磁盘空间告警
# 使用方法：sudo ./disk-log-cleanup.sh [--dry-run] [--keep-days N]
# 参数说明：--dry-run 只显示将要删除的文件，不实际删除
#           --keep-days N 保留最近N天的日志 (默认7天)
# 输出说明：显示将被清理的日志文件和释放的空间
###############################################################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 默认参数
DRY_RUN=false
KEEP_DAYS=7

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --keep-days)
            KEEP_DAYS="$2"
            shift 2
            ;;
        *)
            echo "未知参数: $1"
            echo "用法: $0 [--dry-run] [--keep-days N]"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}=========================================="
echo -e "  日志文件清理工具"
echo -e "==========================================${NC}"
echo ""

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}⚠ 模拟运行模式 - 不会实际删除任何文件${NC}"
    echo ""
fi

echo "保留策略: 保留最近 $KEEP_DAYS 天的日志"
echo ""

#-------------------------------------------------------------------------------
# 第1步：分析系统日志目录
# 目的：统计 /var/log 目录的总体占用情况
# 原理：du 命令可以统计目录大小
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[1] 系统日志目录分析 ${NC}"
echo "----------------------------------------------"

if [ ! -d /var/log ]; then
    echo "错误: /var/log 目录不存在或无权限访问"
    exit 1
fi

echo ">>> /var/log 目录总大小:"
TOTAL_SIZE=$(du -sh /var/log 2>/dev/null | cut -f1)
echo "  $TOTAL_SIZE"

echo ""
echo ">>> 各子目录大小排名:"
du -sh /var/log/* 2>/dev/null | sort -rh | head -15
echo ""

#-------------------------------------------------------------------------------
# 第2步：查找大日志文件
# 目的：快速定位占用空间最多的日志文件
# 原理：find 命令可以按大小筛选文件
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[2] 查找大日志文件 (超过50MB) ${NC}"
echo "----------------------------------------------"
echo ">>> 单文件超过50MB的日志文件:"
find /var/log -type f -size +50M 2>/dev/null | while read file; do
    size=$(du -h "$file" 2>/dev/null | cut -f1)
    modified=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1)
    echo "  $size  $modified  $file"
done
echo ""

#-------------------------------------------------------------------------------
# 第3步：识别可清理的日志
# 目的：找出可以安全删除的日志文件
# 原理：日志文件通常有 .log, .log.1, .gz 等后缀
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[3] 可清理日志分析 ${NC}"
echo "----------------------------------------------"

# 统计将被清理的日志
echo ">>> 将被清理的日志文件统计:"
echo ""

# 3.1 超过保留期限的 .log 文件
echo "1) 超过 ${KEEP_DAYS} 天的 .log 文件:"
OLD_LOGS=$(find /var/log -type f -name "*.log" -mtime +$KEEP_DAYS 2>/dev/null)
if [ -n "$OLD_LOGS" ]; then
    OLD_COUNT=$(echo "$OLD_LOGS" | wc -l)
    OLD_SIZE=$(echo "$OLD_LOGS" | xargs du -ch 2>/dev/null | tail -1 | cut -f1)
    echo "  数量: $OLD_COUNT 个"
    echo "  总大小: $OLD_SIZE"
    if [ "$DRY_RUN" = true ]; then
        echo "$OLD_LOGS" | head -10 | sed 's/^/    /'
        [ $OLD_COUNT -gt 10 ] && echo "    ... (还有 $((OLD_COUNT-10)) 个文件)"
    fi
else
    echo "  无"
fi
echo ""

# 3.2 旧日志压缩包 (.gz)
echo "2) 超过 $((KEEP_DAYS*2)) 天的 .gz 压缩包:"
OLD_GZ=$(find /var/log -type f -name "*.gz" -mtime +$((KEEP_DAYS*2)) 2>/dev/null)
if [ -n "$OLD_GZ" ]; then
    GZ_COUNT=$(echo "$OLD_GZ" | wc -l)
    GZ_SIZE=$(echo "$OLD_GZ" | xargs du -ch 2>/dev/null | tail -1 | cut -f1)
    echo "  数量: $GZ_COUNT 个"
    echo "  总大小: $GZ_SIZE"
    if [ "$DRY_RUN" = true ]; then
        echo "$OLD_GZ" | head -10 | sed 's/^/    /'
    fi
else
    echo "  无"
fi
echo ""

# 3.3 轮转的旧日志 (如 .log.1, .log.2.gz 等)
echo "3) 日志轮转文件 (.*.[0-9]*):"
ROTATE_LOGS=$(find /var/log -type f -regex '.*\.[0-9]+(\.gz)?$' -mtime +$KEEP_DAYS 2>/dev/null)
if [ -n "$ROTATE_LOGS" ]; then
    ROTATE_COUNT=$(echo "$ROTATE_LOGS" | wc -l)
    ROTATE_SIZE=$(echo "$ROTATE_LOGS" | xargs du -ch 2>/dev/null | tail -1 | cut -f1)
    echo "  数量: $ROTATE_COUNT 个"
    echo "  总大小: $ROTATE_SIZE"
else
    echo "  无"
fi
echo ""

#-------------------------------------------------------------------------------
# 第4步：系统服务日志分析
# 目的：分析各系统服务的日志占用情况
# 原理：按服务分类统计日志大小
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[4] 各服务日志分析 ${NC}"
echo "----------------------------------------------"

declare -A LOG_PATHS=(
    ["系统日志"]="/var/log/syslog /var/log/messages /var/log/dmesg"
    ["认证日志"]="/var/log/auth.log /var/log/secure"
    ["Nginx日志"]="/var/log/nginx/*"
    ["Apache日志"]="/var/log/apache2/* /var/log/httpd/*"
    ["MySQL日志"]="/var/log/mysql/*"
    ["PostgreSQL日志"]="/var/log/postgresql/*"
    ["Docker日志"]="/var/lib/docker/containers/*/*.log"
    ["Kernel日志"]="/var/log/kern.log"
    ["Cron日志"]="/var/log/cron.log /var/log/crontab"
    ["邮件日志"]="/var/log/maillog /var/log/mail.*"
)

for service in "${!LOG_PATHS[@]}"; do
    paths="${LOG_PATHS[$service]}"
    # 合并通配符路径
    total_size=0
    file_count=0
    for pattern in $paths; do
        if ls $pattern 2>/dev/null | head -1 > /dev/null; then
            size=$(du -ch $pattern 2>/dev/null | tail -1 | cut -f1)
            count=$(ls $pattern 2>/dev/null | wc -l)
            total_size=$(($total_size + $(du -sk $pattern 2>/dev/null | awk '{sum+=$1} END {print sum}')))
            file_count=$(($file_count + $count))
        fi
    done

    if [ $file_count -gt 0 ]; then
        size_human=$(echo "$total_size" | awk '{printf "%.1f MB", $1/1024}')
        echo "  $service: $file_count 个文件 ($size_human)"
    fi
done
echo ""

#-------------------------------------------------------------------------------
# 第5步：日志增长速度分析
# 目的：识别哪些日志增长最快
# 原理：比较日志文件当前大小和一定时间前的大小
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[5] 日志增长速度分析 ${NC}"
echo "----------------------------------------------"

echo ">>> 最近修改时间超过1小时的日志:"
find /var/log -type f -mmin +60 -mtime -1 -size +1M 2>/dev/null | head -10 | while read file; do
    size=$(du -h "$file" 2>/dev/null | cut -f1)
    mtime=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1,2 | cut -d':' -f1,2)
    echo "  $size  $mtime  $(basename $file)"
done
echo ""

#-------------------------------------------------------------------------------
# 第6步：统计清理后的预期效果
# 目的：计算清理操作可以释放的空间
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[6] 清理效果预估 ${NC}"
echo "----------------------------------------------"

# 统计所有可清理的文件
TOTAL_CLEANABLE=$(find /var/log -type f \( -name "*.log" -o -name "*.gz" -o -regex '.*\.[0-9]+(\.gz)?$' \) -mtime +$KEEP_DAYS 2>/dev/null)
if [ -n "$TOTAL_CLEANABLE" ]; then
    CLEANABLE_COUNT=$(echo "$TOTAL_CLEANABLE" | wc -l)
    CLEANABLE_SIZE=$(echo "$TOTAL_CLEANABLE" | xargs du -ck 2>/dev/null | tail -1 | cut -f1)
    CLEANABLE_HUMAN=$(echo "$CLEANABLE_SIZE" | awk '{printf "%.1f MB", $1/1024}')

    echo "可清理日志统计:"
    echo "  文件数量: $CLEANABLE_COUNT"
    echo "  总大小: $CLEANABLE_HUMAN"
    echo "  清理后 /var/log 目录大小约: 预计减少 $CLEANABLE_HUMAN"
else
    echo "当前没有超过保留期限的日志文件需要清理"
fi
echo ""

#-------------------------------------------------------------------------------
# 第7步：执行清理
# 目的：根据策略清理旧的日志文件
# 原理：find 命令配合 -delete 或 rm 删除过期文件
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[7] 执行清理 ${NC}"
echo "----------------------------------------------"

if [ "$DRY_RUN" = true ]; then
    echo "⚠ 模拟模式 - 未执行实际删除"
    echo ""
    echo "如需实际清理，请重新运行不带 --dry-run 参数:"
    echo "  sudo $0 --keep-days $KEEP_DAYS"
else
    echo "开始清理日志文件..."

    # 清理过期的 .log 文件
    echo ">>> 清理超过 ${KEEP_DAYS} 天的 .log 文件..."
    find /var/log -type f -name "*.log" -mtime +$KEEP_DAYS -delete 2>/dev/null
    echo "  完成"

    # 清理过期的压缩日志
    echo ">>> 清理超过 $((KEEP_DAYS*2)) 天的 .gz 日志..."
    find /var/log -type f -name "*.gz" -mtime +$((KEEP_DAYS*2)) -delete 2>/dev/null
    echo "  完成"

    # 清理旧的轮转日志
    echo ">>> 清理旧的轮转日志..."
    find /var/log -type f -regex '.*\.[0-9]+(\.gz)?$' -mtime +$KEEP_DAYS -delete 2>/dev/null
    echo "  完成"

    # 清理空文件
    echo ">>> 清理空日志文件..."
    find /var/log -type f -size 0 -delete 2>/dev/null
    echo "  完成"

    echo ""
    echo -e "${GREEN}✓ 清理完成！${NC}"
fi
echo ""

#-------------------------------------------------------------------------------
# 第8步：显示清理后的结果
# 目的：确认清理效果
# 原理：重新统计 /var/log 目录大小
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[8] 清理后状态 ${NC}"
echo "----------------------------------------------"

if [ "$DRY_RUN" = false ]; then
    NEW_SIZE=$(du -sh /var/log 2>/dev/null | cut -f1)
    echo "/var/log 目录清理后大小: $NEW_SIZE"

    # 显示剩余的主要目录
    echo ""
    echo "清理后各目录大小:"
    du -sh /var/log/* 2>/dev/null | sort -rh | head -10
fi
echo ""

#-------------------------------------------------------------------------------
# 第9步：推荐配置 logrotate
# 目的：建立自动日志轮转机制
# 原理：logrotate 是Linux标准日志轮转工具
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[9] 配置 logrotate 自动轮转 ${NC}"
echo "----------------------------------------------"

echo "建议为重要日志配置 logrotate。以下是推荐配置示例："
echo ""

cat << 'EOF'
# /etc/logrotate.d/custom-logs
/var/log/myapp/*.log {
    daily              # 每天轮转
    missingok          # 文件不存在不报错
    rotate 7           # 保留7个版本
    compress           # 压缩旧日志
    delaycompress      # 延迟一天压缩
    notifempty         # 空文件不轮转
    maxsize 100M       # 超过100M立即轮转
    dateext            # 使用日期作为后缀
}

/var/log/myapp/access.log {
    weekly
    rotate 14
    compress
    maxsize 200M
}
EOF

echo ""
echo "配置说明:"
echo "  daily/weekly/monthly: 轮转频率"
echo "  rotate N: 保留N个版本"
echo "  compress: 压缩旧日志"
echo "  maxsize: 文件超过此大小立即轮转"
echo "  dateext: 使用日期后缀替代数字后缀"
echo ""

#-------------------------------------------------------------------------------
# 第10步：truncate 清空正在写入的日志
# 目的：安全清空大日志文件而不删除文件句柄
# 原理：truncate -s 0 可以清空文件但保持文件描述符
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[10] 清空大日志文件 (保留文件) ${NC}"
echo "----------------------------------------------"

echo "如果您需要清空正在写入的日志文件（但不删除文件本身），可以使用 truncate："
echo ""
echo "# 清空日志文件但保留文件句柄 (进程可以继续写入)"
echo "truncate -s 0 /var/log/nginx/access.log"
echo ""
echo "或者使用 > 重定向清空："
echo ""
echo "# 注意：某些进程可能需要重启才能重新打开日志文件"
echo "> /var/log/nginx/access.log"
echo ""

echo -e "${BLUE}=========================================="
echo -e "  日志清理完成"
echo -e "==========================================${NC}"

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "运行不带 --dry-run 参数以执行实际清理"
fi