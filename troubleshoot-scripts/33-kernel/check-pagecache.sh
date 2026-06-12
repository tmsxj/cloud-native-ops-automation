#!/bin/bash
# ============================================================================
# 模块33-计算机基础与内核脚本
# 脚本名称: check-pagecache.sh
# 功能: Page Cache分析
# 用法: ./check-pagecache.sh
# 说明: 检查Page Cache使用、脏页参数、文件句柄使用和内存回收状态
# ============================================================================

# ======================== 颜色输出函数定义 ========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_info() { echo -e "[INFO] $1"; }

echo "============================================================"
echo "          Page Cache分析报告"
echo "          检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ======================== 1. Page Cache统计 ========================
print_info ">>> [1/4] 检查Page Cache使用情况 ..."

# 从/proc/meminfo获取缓存信息
MEMINFO=$(cat /proc/meminfo 2>/dev/null)

CACHED=$(echo "$MEMINFO" | grep "^Cached:" | awk '{print $2}')
DIRTY=$(echo "$MEMINFO" | grep "^Dirty:" | awk '{print $2}')
WRITEBACK=$(echo "$MEMINFO" | grep "^Writeback:" | awk '{print $2}')
MAPPED=$(echo "$MEMINFO" | grep "^Mapped:" | awk '{print $2}')
ACTIVE_FILE=$(echo "$MEMINFO" | grep "^Active(file):" | awk '{print $2}')
INACTIVE_FILE=$(echo "$MEMINFO" | grep "^Inactive(file):" | awk '{print $2}')
SLAB_RECLAIMABLE=$(echo "$MEMINFO" | grep "^SReclaimable:" | awk '{print $2}')

# 转换为MB
CACHED_MB=$((CACHED / 1024))
DIRTY_MB=$((DIRTY / 1024))
WRITEBACK_MB=$((WRITEBACK / 1024))
MAPPED_MB=$((MAPPED / 1024))
ACTIVE_FILE_MB=$((ACTIVE_FILE / 1024))
INACTIVE_FILE_MB=$((INACTIVE_FILE / 1024))
SLAB_MB=$((SLAB_RECLAIMABLE / 1024))

echo "    Page Cache统计:"
echo "    ------------------------------------------------------------------"
printf "    %-25s %-12s %s\n" "指标" "大小" "说明"
echo "    ------------------------------------------------------------------"
printf "    %-25s %-12s %s\n" "Cached" "${CACHED_MB}MB" "页缓存(已缓存文件)"
printf "    %-25s %-12s %s\n" "Dirty" "${DIRTY_MB}MB" "脏页(待写入磁盘)"
printf "    %-25s %-12s %s\n" "Writeback" "${WRITEBACK_MB}MB" "正在回写"
printf "    %-25s %-12s %s\n" "Mapped" "${MAPPED_MB}MB" "被进程映射的文件"
printf "    %-25s %-12s %s\n" "Active(file)" "${ACTIVE_FILE_MB}MB" "活跃文件页"
printf "    %-25s %-12s %s\n" "Inactive(file)" "${INACTIVE_FILE_MB}MB" "非活跃文件页"
printf "    %-25s %-12s %s\n" "SReclaimable" "${SLAB_MB}MB" "可回收slab缓存"
echo "    ------------------------------------------------------------------"

# 脏页阈值判断: Dirty > 1GB(1048576KB) 黄色
DIRTY_THRESHOLD_KB=1048576  # 1GB
if [ "$DIRTY" -gt "$DIRTY_THRESHOLD_KB" ]; then
    print_warn "脏页过多 (${DIRTY_MB}MB > 1GB)，可能影响写入性能"
    print_info "建议: 检查是否有大量文件写入或flush线程阻塞"
elif [ "$DIRTY" -gt $((DIRTY_THRESHOLD_KB / 2)) ]; then
    print_info "脏页量适中 (${DIRTY_MB}MB)"
else
    print_ok "脏页量正常 (${DIRTY_MB}MB)"
fi

# Writeback检查
if [ "$WRITEBACK" -gt $((DIRTY_THRESHOLD_KB / 2)) ]; then
    print_warn "正在回写的页面较多 (${WRITEBACK_MB}MB)，磁盘写入压力大"
else
    print_ok "回写页面正常 (${WRITEBACK_MB}MB)"
fi

echo ""

# ======================== 2. 脏页参数检查 ========================
print_info ">>> [2/4] 检查脏页内核参数 ..."

# 脏页参数
DIRTY_RATIO=$(cat /proc/sys/vm/dirty_ratio 2>/dev/null)
DIRTY_BACKGROUND_RATIO=$(cat /proc/sys/vm/dirty_background_ratio 2>/dev/null)
DIRTY_EXPIRE_CENTISECS=$(cat /proc/sys/vm/dirty_expire_centisecs 2>/dev/null)
DIRTY_WRITEBACK_CENTISECS=$(cat /proc/sys/vm/dirty_writeback_centisecs 2>/dev/null)

echo "    脏页相关参数:"
echo "    vm.dirty_ratio = ${DIRTY_RATIO}% (脏页达到总内存的此比例时触发同步写入)"
echo "    vm.dirty_background_ratio = ${DIRTY_BACKGROUND_RATIO}% (后台回写触发比例)"
echo "    vm.dirty_expire_centisecs = ${DIRTY_EXPIRE_CENTISECS} (脏页过期时间: $((DIRTY_EXPIRE_CENTISECS/100))秒)"
echo "    vm.dirty_writeback_centisecs = ${DIRTY_WRITEBACK_CENTISECS} (回写间隔: $((DIRTY_WRITEBACK_CENTISECS/100))秒)"

# 参数评估
echo ""
echo "    参数评估:"
if [ "$DIRTY_RATIO" -gt 20 ]; then
    print_warn "dirty_ratio偏高(${DIRTY_RATIO}%)，可能导致大量脏页积压"
    print_info "建议: 对于大多数场景，设置为10-20"
else
    print_ok "dirty_ratio设置合理(${DIRTY_RATIO}%)"
fi

if [ "$DIRTY_BACKGROUND_RATIO" -gt 10 ]; then
    print_warn "dirty_background_ratio偏高(${DIRTY_BACKGROUND_RATIO}%)"
else
    print_ok "dirty_background_ratio设置合理(${DIRTY_BACKGROUND_RATIO}%)"
fi

if [ "$DIRTY_EXPIRE_CENTISECS" -gt 6000 ]; then
    print_info "脏页过期时间较长($((DIRTY_EXPIRE_CENTISECS/100))秒)，数据丢失风险略高"
else
    print_ok "脏页过期时间合理($((DIRTY_EXPIRE_CENTISECS/100))秒)"
fi

echo ""
echo "    优化建议:"
echo "    - 通用服务器: dirty_ratio=10, dirty_background_ratio=5"
echo "    - 高写入场景: dirty_ratio=15, dirty_background_ratio=5"
echo "    - 低延迟要求: dirty_ratio=5, dirty_background_ratio=3"

echo ""

# ======================== 3. 文件句柄检查 ========================
print_info ">>> [3/4] 检查系统文件句柄使用情况 ..."

FILE_NR=$(cat /proc/sys/fs/file-nr 2>/dev/null)
FILE_ALLOCATED=$(echo "$FILE_NR" | awk '{print $1}')
FILE_USED=$(echo "$FILE_NR" | awk '{print $2}')
FILE_MAX=$(echo "$FILE_NR" | awk '{print $3}')

echo "    文件句柄统计:"
echo "    已分配: ${FILE_ALLOCATED}  |  已使用: ${FILE_USED}  |  最大值: ${FILE_MAX}"

if [ "$FILE_MAX" -gt 0 ]; then
    FILE_USAGE_PERCENT=$((FILE_USED * 100 / FILE_MAX))
    echo "    使用率: ${FILE_USAGE_PERCENT}%"

    if [ "$FILE_USAGE_PERCENT" -gt 95 ]; then
        print_fail "文件句柄使用率极高 (${FILE_USAGE_PERCENT}%)，可能无法打开新文件"
        print_info "建议: 增加fs.file-max或排查句柄泄漏"
    elif [ "$FILE_USAGE_PERCENT" -gt 80 ]; then
        print_warn "文件句柄使用率偏高 (${FILE_USAGE_PERCENT}%)"
        print_info "建议: 监控使用趋势，考虑调大fs.file-max"
    else
        print_ok "文件句柄使用率正常 (${FILE_USAGE_PERCENT}%)"
    fi
fi

# 检查每个进程的文件句柄限制
echo ""
echo "    各进程文件句柄限制检查:"
ULIMIT_GLOBAL=$(ulimit -n 2>/dev/null)
echo "    当前shell ulimit -n: ${ULIMIT_GLOBAL}"

# 检查systemd的文件句柄限制
if [ -f /etc/systemd/system.conf ]; then
    LIMIT_NOFILE=$(grep "^DefaultLimitNOFILE" /etc/systemd/system.conf 2>/dev/null)
    if [ -n "$LIMIT_NOFILE" ]; then
        echo "    systemd DefaultLimitNOFILE: $LIMIT_NOFILE"
    fi
fi

# 检查/etc/security/limits.conf
if [ -f /etc/security/limits.conf ]; then
    echo ""
    echo "    limits.conf中的nofile配置:"
    grep -v "^#" /etc/security/limits.conf 2>/dev/null | grep "nofile" | while read line; do
        echo "    $line"
    done
fi

echo ""

# ======================== 4. 内存回收状态 ========================
print_info ">>> [4/4] 检查内存回收状态 ..."

# 检查内存回收相关参数
ZONE_RECLAIM_MODE=$(cat /proc/sys/vm/zone_reclaim_mode 2>/dev/null)
DROP_CACHES=$(cat /proc/sys/vm/drop_caches 2>/dev/null)

echo "    vm.zone_reclaim_mode = ${ZONE_RECLAIM_MODE}"
echo "    vm.drop_caches = ${DROP_CACHES}"

# 检查kswapd活动
KSWAPD=$(ps aux | grep -E "\[kswapd" | grep -v grep)
if [ -n "$KSWAPD" ]; then
    echo ""
    echo "    kswapd守护进程:"
    echo "$KSWAPD" | while read line; do
        echo "    $line"
    done
    print_info "kswapd负责后台内存回收，持续高CPU使用可能表示内存压力"
fi

# 检查直接内存回收
DMESG_RECLAIM=$(dmesg 2>/dev/null | grep -i "direct reclaim\|memory reclaim" | tail -3)
if [ -n "$DMESG_RECLAIM" ]; then
    print_warn "检测到直接内存回收事件:"
    echo "$DMESG_RECLAIM" | while read line; do
        echo "    $line"
    done
fi

echo ""
echo "============================================================"
echo "                     诊断结论"
echo "============================================================"

ISSUE_COUNT=0

if [ "$DIRTY" -gt "$DIRTY_THRESHOLD_KB" ]; then
    echo -e "  ${YELLOW}[警告]${NC} 脏页过多(${DIRTY_MB}MB)，可能影响写入性能"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "${FILE_USAGE_PERCENT:-0}" -gt 80 ]; then
    echo -e "  ${YELLOW}[警告]${NC} 文件句柄使用率${FILE_USAGE_PERCENT}%，接近上限"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ -n "$DMESG_RECLAIM" ]; then
    echo -e "  ${YELLOW}[警告]${NC} 存在直接内存回收事件，内存可能不足"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$ISSUE_COUNT" -eq 0 ]; then
    echo -e "  ${GREEN}[正常]${NC} Page Cache和文件句柄状态正常"
fi

echo "============================================================"
