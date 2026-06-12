#!/bin/bash
# ============================================================================
# 模块31-Linux系统故障排查脚本
# 脚本名称: check-memory.sh
# 功能: 内存不足与OOM诊断
# 用法: ./check-memory.sh
# 说明: 检查内存使用率、Swap使用、进程内存占用和OOM事件
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
echo "          内存不足与OOM诊断报告"
echo "          检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ======================== 1. 内存使用率检查 ========================
print_info ">>> [1/4] 检查内存使用情况 ..."

# 解析free命令输出
MEM_INFO=$(free -h)
MEM_TOTAL=$(echo "$MEM_INFO" | awk '/^Mem:/{print $2}')
MEM_USED=$(echo "$MEM_INFO" | awk '/^Mem:/{print $3}')
MEM_AVAILABLE=$(echo "$MEM_INFO" | awk '/^Mem:/{print $7}')

# 使用free -m获取数值用于百分比计算
MEM_TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEM_AVAILABLE_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')

# 计算可用内存百分比
if [ "$MEM_TOTAL_KB" -gt 0 ]; then
    AVAILABLE_PERCENT=$((MEM_AVAILABLE_KB * 100 / MEM_TOTAL_KB))
else
    AVAILABLE_PERCENT=100
fi

echo "    总内存: ${MEM_TOTAL}  |  已用: ${MEM_USED}  |  可用: ${MEM_AVAILABLE}"
echo "    可用内存占比: ${AVAILABLE_PERCENT}%"

# 阈值判断: available < 20% 红色, < 40% 黄色
if [ "$AVAILABLE_PERCENT" -lt 20 ]; then
    print_fail "可用内存严重不足 (${AVAILABLE_PERCENT}%)，系统面临OOM风险"
    print_info "建议: 立即排查内存泄漏或扩展内存容量"
elif [ "$AVAILABLE_PERCENT" -lt 40 ]; then
    print_warn "可用内存偏低 (${AVAILABLE_PERCENT}%)，建议关注内存使用趋势"
else
    print_ok "可用内存充足 (${AVAILABLE_PERCENT}%)"
fi

echo ""

# ======================== 2. Swap使用检查 ========================
print_info ">>> [2/4] 检查Swap使用情况 ..."

SWAP_TOTAL=$(echo "$MEM_INFO" | awk '/^Swap:/{print $2}')
SWAP_USED=$(echo "$MEM_INFO" | awk '/^Swap:/{print $3}')

# 获取Swap数值（KB）
SWAP_TOTAL_KB=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
SWAP_USED_KB=$(grep SwapUsed /proc/meminfo 2>/dev/null | awk '{print $2}')
if [ -z "$SWAP_USED_KB" ]; then
    # 某些系统没有SwapUsed，通过计算获取
    SWAP_FREE_KB=$(grep SwapFree /proc/meminfo | awk '{print $2}')
    SWAP_USED_KB=$((SWAP_TOTAL_KB - SWAP_FREE_KB))
fi

echo "    Swap总量: ${SWAP_TOTAL}  |  Swap已用: ${SWAP_USED}"

# Swap阈值判断: swap > 0 黄色
if [ "$SWAP_TOTAL_KB" -eq 0 ]; then
    print_info "系统未配置Swap分区"
elif [ "$SWAP_USED_KB" -gt 0 ]; then
    print_warn "Swap已被使用 (${SWAP_USED})，物理内存可能不足"
    print_info "建议: 检查哪些进程在使用Swap，考虑增加物理内存"
else
    print_ok "Swap未被使用，物理内存充足"
fi

echo ""

# ======================== 3. 进程内存占用检查 ========================
print_info ">>> [3/4] 检查内存占用最高的进程 ..."

echo "    内存使用 TOP 10 进程:"
echo "    ------------------------------------------------------------------"
printf "    %-10s %-8s %-8s %-8s %-10s %s\n" "USER" "PID" "RSS" "%MEM" "VSZ" "COMMAND"
ps aux --sort=-%mem | head -11 | tail -10 | while read line; do
    USER=$(echo "$line" | awk '{print $1}')
    PID=$(echo "$line" | awk '{print $2}')
    RSS=$(echo "$line" | awk '{print $6}')
    MEM_PCT=$(echo "$line" | awk '{print $4}')
    VSZ=$(echo "$line" | awk '{print $5}')
    CMD=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}')
    printf "    %-10s %-8s %-8s %-8s %-10s %s\n" "$USER" "$PID" "$RSS" "$MEM_PCT%" "$VSZ" "$CMD"
done
echo "    ------------------------------------------------------------------"

# 检查是否有进程内存占用超过50%
HIGH_MEM_PROCS=$(ps aux --sort=-%mem | awk 'NR>1 && $4+0 > 50 {print $2, $11, $4"%"}')
if [ -n "$HIGH_MEM_PROCS" ]; then
    echo ""
    print_warn "以下进程内存占用超过50%:"
    echo "$HIGH_MEM_PROCS" | while read line; do
        echo "    - $line"
    done
fi

echo ""

# ======================== 4. OOM事件检查 ========================
print_info ">>> [4/4] 检查OOM Killer事件 ..."

# 检查dmesg中的OOM记录
OOM_LOGS=$(dmesg 2>/dev/null | grep -i "killed process" | tail -5)

if [ -z "$OOM_LOGS" ]; then
    print_ok "未检测到OOM Killer事件"
else
    OOM_COUNT=$(dmesg 2>/dev/null | grep -ci "killed process")
    print_fail "检测到 ${OOM_COUNT} 次OOM Killer事件!"
    echo ""
    echo "    最近OOM事件:"
    echo "$OOM_LOGS" | while read line; do
        echo "    $line"
    done
    print_info "建议: 分析被杀进程的内存使用模式，调整OOM分数或增加内存"
fi

# 检查系统日志中的OOM记录（如果dmesg没有）
if [ -z "$OOM_LOGS" ] && [ -f /var/log/messages ]; then
    SYSOOM=$(grep -i "out of memory\|oom killer\|invoked oom" /var/log/messages 2>/dev/null | tail -3)
    if [ -n "$SYSOOM" ]; then
        print_warn "在系统日志中发现OOM相关记录"
        echo "$SYSOOM" | while read line; do
            echo "    $line"
        done
    fi
fi

echo ""
echo "============================================================"
echo "                     诊断结论"
echo "============================================================"

ISSUE_COUNT=0

if [ "$AVAILABLE_PERCENT" -lt 20 ]; then
    echo -e "  ${RED}[严重]${NC} 可用内存不足${AVAILABLE_PERCENT}%，存在OOM风险"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
elif [ "$AVAILABLE_PERCENT" -lt 40 ]; then
    echo -e "  ${YELLOW}[警告]${NC} 可用内存偏低${AVAILABLE_PERCENT}%，建议持续监控"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$SWAP_USED_KB" -gt 0 ] && [ "$SWAP_TOTAL_KB" -gt 0 ]; then
    echo -e "  ${YELLOW}[警告]${NC} Swap已被使用，物理内存可能不足"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ -n "$OOM_LOGS" ]; then
    echo -e "  ${RED}[严重]${NC} 存在OOM Killer事件，需紧急排查"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$ISSUE_COUNT" -eq 0 ]; then
    echo -e "  ${GREEN}[正常]${NC} 内存状态健康，未发现异常"
fi

echo "============================================================"
