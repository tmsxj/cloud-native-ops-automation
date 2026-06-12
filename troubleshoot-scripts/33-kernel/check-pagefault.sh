#!/bin/bash
# ============================================================================
# 模块33-计算机基础与内核脚本
# 脚本名称: check-pagefault.sh
# 功能: 缺页中断分析
# 用法: ./check-pagefault.sh [pid]
# 说明: 检查缺页中断统计、进程级缺页、swap使用和swappiness参数
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

# ======================== 初始化变量 ========================
TARGET_PID=""
if [ -n "$1" ]; then
    TARGET_PID=$1
    if ! kill -0 "$TARGET_PID" 2>/dev/null; then
        print_fail "进程 PID=$TARGET_PID 不存在"
        exit 1
    fi
    print_info "指定进程 PID=$TARGET_PID，将进行进程级缺页分析"
fi

echo "============================================================"
echo "          缺页中断分析报告"
echo "          检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ======================== 1. 系统缺页统计 ========================
print_info ">>> [1/4] 检查系统缺页中断统计 ..."

if command -v sar &>/dev/null; then
    SAR_RESULT=$(sar -B 1 3 2>/dev/null)
    echo "    缺页中断统计(每秒):"
    echo "$SAR_RESULT" | tail -5 | while read line; do
        echo "    $line"
    done

    # 提取最后一次采样的数据
    SAR_LAST=$(echo "$SAR_RESULT" | tail -1)
    MAJFLT=$(echo "$SAR_LAST" | awk '{print $6}')
    MINFLT=$(echo "$SAR_LAST" | awk '{print $4}')
    PGPGIN=$(echo "$SAR_LAST" | awk '{print $2}')
    PGPGOUT=$(echo "$SAR_LAST" | awk '{print $3}')

    echo ""
    echo "    主要指标:"
    echo "    每秒页换入(pgpgin/s): ${PGPGIN}"
    echo "    每秒页换出(pgpgout/s): ${PGPGOUT}"
    echo "    每秒缺页(minflt/s): ${MINFLT}"
    echo "    每秒主缺页(majflt/s): ${MAJFLT}"

    # 主缺页阈值: majflt/s > 100 红色
    MAJFLT_INT=${MAJFLT%.*}
    if [ "$MAJFLT_INT" -gt 100 ]; then
        print_fail "主缺页率过高 (${MAJFLT}/s)，大量磁盘IO用于页面换入"
        print_info "建议: 增加物理内存或减少内存使用，检查是否存在内存泄漏"
    elif [ "$MAJFLT_INT" -gt 10 ]; then
        print_warn "主缺页率偏高 (${MAJFLT}/s)，存在一定的磁盘换页压力"
    else
        print_ok "主缺页率正常 (${MAJFLT}/s)"
    fi
else
    print_warn "sar命令不可用，使用/proc/vmstat替代"
    # 从/proc/vmstat获取缺页统计
    VMSTAT_INFO=$(cat /proc/vmstat 2>/dev/null)
    PGFAULT=$(echo "$VMSTAT_INFO" | grep "^pgfault" | awk '{print $2}')
    PGMAJFAULT=$(echo "$VMSTAT_INFO" | grep "^pgmajfault" | awk '{print $2}')
    PGIN=$(echo "$VMSTAT_INFO" | grep "^pgpgin" | awk '{print $2}')
    PGOUT=$(echo "$VMSTAT_INFO" | grep "^pgpgout" | awk '{print $2}')

    echo "    pgfault(总缺页): ${PGFAULT}"
    echo "    pgmajfault(主缺页): ${PGMAJFAULT}"
    echo "    pgpgin(页换入): ${PGIN}"
    echo "    pgpgout(页换出): ${PGOUT}"
fi

echo ""

# ======================== 2. 进程级缺页分析 ========================
if [ -n "$TARGET_PID" ]; then
    print_info ">>> [2/4] 进程级缺页分析 (PID=${TARGET_PID}) ..."

    PROC_NAME=$(ps -p "$TARGET_PID" -o comm --no-headers 2>/dev/null)
    echo "    进程名: ${PROC_NAME}"

    if command -v pidstat &>/dev/null; then
        echo ""
        print_info "进程缺页统计(pidstat -r):"
        pidstat -r 1 3 -p "$TARGET_PID" 2>/dev/null | while read line; do
            echo "    $line"
        done
    else
        print_info "pidstat不可用，使用/proc接口"
    fi

    # 从/proc获取进程缺页信息
    if [ -f "/proc/$TARGET_PID/stat" ]; then
        PROC_STAT=$(cat "/proc/$TARGET_PID/stat" 2>/dev/null)
        # minflt在第10个字段，majflt在第12个字段
        PROC_MINFLT=$(echo "$PROC_STAT" | awk '{print $10}')
        PROC_MAJFLT=$(echo "$PROC_STAT" | awk '{print $12}')
        echo ""
        echo "    进程缺页统计:"
        echo "    次缺页(minor faults): ${PROC_MINFLT}"
        echo "    主缺页(major faults): ${PROC_MAJFLT}"

        if [ "${PROC_MAJFLT:-0}" -gt 10000 ]; then
            print_warn "进程主缺页数较高 (${PROC_MAJFLT})，可能频繁访问磁盘"
        fi
    fi
else
    print_info ">>> [2/4] 跳过进程级缺页分析（未指定PID）"
    # 显示缺页最多的进程
    print_info "缺页最多的进程 TOP 10:"
    echo "    ------------------------------------------------------------------"
    printf "    %-8s %-12s %-12s %-10s %s\n" "PID" "MINFLT" "MAJFLT" "RSS" "COMMAND"
    ps -eo pid,minflt,majflt,rss,comm --sort=-majflt | head -11 | tail -10 | while read pid minflt majflt rss cmd; do
        printf "    %-8s %-12s %-12s %-10s %s\n" "$pid" "$minflt" "$majflt" "$rss" "$cmd"
    done
    echo "    ------------------------------------------------------------------"
fi

echo ""

# ======================== 3. Swap使用检查 ========================
print_info ">>> [3/4] 检查Swap使用情况 ..."

MEM_INFO=$(free -h)
SWAP_TOTAL=$(echo "$MEM_INFO" | awk '/^Swap:/{print $2}')
SWAP_USED=$(echo "$MEM_INFO" | awk '/^Swap:/{print $3}')
SWAP_FREE=$(echo "$MEM_INFO" | awk '/^Swap:/{print $4}')

echo "    Swap总量: ${SWAP_TOTAL}  |  已用: ${SWAP_USED}  |  空闲: ${SWAP_FREE}"

# 获取数值
SWAP_TOTAL_KB=$(grep SwapTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
SWAP_FREE_KB=$(grep SwapFree /proc/meminfo 2>/dev/null | awk '{print $2}')
SWAP_USED_KB=$((SWAP_TOTAL_KB - SWAP_FREE_KB))

if [ "$SWAP_TOTAL_KB" -eq 0 ]; then
    print_info "系统未配置Swap"
elif [ "$SWAP_USED_KB" -gt 0 ]; then
    SWAP_MB=$((SWAP_USED_KB / 1024))
    print_warn "Swap已被使用 (${SWAP_MB}MB)，物理内存可能不足"
    print_info "建议: 检查哪些进程在使用Swap，考虑增加物理内存"

    # 显示使用Swap最多的进程
    echo ""
    echo "    使用Swap最多的进程 TOP 10:"
    echo "    ------------------------------------------------------------------"
    printf "    %-8s %-12s %-10s %s\n" "PID" "Swap(KB)" "RSS(KB)" "COMMAND"
    for pid in $(ls /proc/ 2>/dev/null | grep -E '^[0-9]+$'); do
        if [ -f "/proc/$pid/status" ] && [ -f "/proc/$pid/comm" ]; then
            VMSWAP=$(grep "VmSwap" /proc/$pid/status 2>/dev/null | awk '{print $2}')
            if [ -n "$VMSWAP" ] && [ "$VMSWAP" != "0" ]; then
                RSS=$(grep "VmRSS" /proc/$pid/status 2>/dev/null | awk '{print $2}')
                CMD=$(cat /proc/$pid/comm 2>/dev/null)
                echo "${VMSWAP} ${pid} ${RSS} ${CMD}"
            fi
        fi
    done 2>/dev/null | sort -rn | head -10 | while read vmswap pid rss cmd; do
        printf "    %-8s %-12s %-10s %s\n" "$pid" "$vmswap" "${rss:-0}" "$cmd"
    done
    echo "    ------------------------------------------------------------------"
else
    print_ok "Swap未被使用，物理内存充足"
fi

echo ""

# ======================== 4. Swappiness参数检查 ========================
print_info ">>> [4/4] 检查Swappiness参数 ..."

SWAPPINESS=$(cat /proc/sys/vm/swappiness 2>/dev/null)
echo "    vm.swappiness = ${SWAPPINESS}"

if [ "$SWAPPINESS" -gt 60 ]; then
    print_warn "swappiness偏高 (${SWAPPINESS})，系统倾向于使用Swap"
    print_info "建议: 对于大多数服务器，建议设置为10-30"
elif [ "$SWAPPINESS" -gt 30 ]; then
    print_info "swappiness=${SWAPPINESS}，使用默认值"
else
    print_ok "swappiness=${SWAPPINESS}，设置合理（倾向于使用物理内存）"
fi

# 检查其他内存相关参数
VFS_CACHE_PRESSURE=$(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null)
echo "    vm.vfs_cache_pressure = ${VFS_CACHE_PRESSURE}"

OVERCOMMIT_MEMORY=$(cat /proc/sys/vm/overcommit_memory 2>/dev/null)
echo "    vm.overcommit_memory = ${OVERCOMMIT_MEMORY}"

MIN_FREE_KB=$(cat /proc/sys/vm/min_free_kbytes 2>/dev/null)
echo "    vm.min_free_kbytes = ${MIN_FREE_KB}"

echo ""
echo "    参数优化建议:"
echo "    - 服务器场景建议: sysctl -w vm.swappiness=10"
echo "    - 数据库场景建议: sysctl -w vm.swappiness=1"
echo "    - 避免OOM建议: sysctl -w vm.overcommit_memory=0"

echo ""
echo "============================================================"
echo "                     诊断结论"
echo "============================================================"

ISSUE_COUNT=0

if [ "${MAJFLT_INT:-0}" -gt 100 ]; then
    echo -e "  ${RED}[严重]${NC} 主缺页率过高(${MAJFLT}/s)，磁盘IO压力大"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$SWAP_USED_KB" -gt 0 ] && [ "$SWAP_TOTAL_KB" -gt 0 ]; then
    echo -e "  ${YELLOW}[警告]${NC} Swap已被使用，物理内存可能不足"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$SWAPPINESS" -gt 60 ]; then
    echo -e "  ${YELLOW}[警告]${NC} swappiness偏高(${SWAPPINESS})，建议降低"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$ISSUE_COUNT" -eq 0 ]; then
    echo -e "  ${GREEN}[正常]${NC} 缺页中断和Swap状态正常"
fi

echo "============================================================"
