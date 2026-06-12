#!/bin/bash
# ============================================================================
# 模块31-Linux系统故障排查脚本
# 脚本名称: check-cpu.sh
# 功能: CPU性能瓶颈诊断
# 用法: ./check-cpu.sh [pid]
# 说明: 检查CPU使用率、上下文切换、系统负载等关键指标
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
    # 验证进程是否存在
    if ! kill -0 "$TARGET_PID" 2>/dev/null; then
        print_fail "进程 PID=$TARGET_PID 不存在"
        exit 1
    fi
    print_info "指定进程 PID=$TARGET_PID，将进行进程级CPU分析"
fi

echo "============================================================"
echo "          CPU性能瓶颈诊断报告"
echo "          检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ======================== 1. 整体CPU使用率检查 ========================
print_info ">>> [1/4] 检查整体CPU使用率 ..."

# 从top获取CPU数据，解析us/sy/wa/id
CPU_RAW=$(top -bn1 | head -20)
CPU_US=$(echo "$CPU_RAW" | grep '%Cpu' | awk '{print $2}' | cut -d'.' -f1)
CPU_SY=$(echo "$CPU_RAW" | grep '%Cpu' | awk '{print $4}' | cut -d'.' -f1)
CPU_WA=$(echo "$CPU_RAW" | grep '%Cpu' | awk '{print $10}' | cut -d'.' -f1)
CPU_ID=$(echo "$CPU_RAW" | grep '%Cpu' | awk '{print $8}' | cut -d'.' -f1)

# 容错处理：如果解析失败则设为0
CPU_US=${CPU_US:-0}
CPU_SY=${CPU_SY:-0}
CPU_WA=${CPU_WA:-0}
CPU_ID=${CPU_ID:-0}

echo "    用户态(us): ${CPU_US}%  |  内核态(sy): ${CPU_SY}%  |  IO等待(wa): ${CPU_WA}%  |  空闲(id): ${CPU_ID}%"

# 用户态CPU阈值判断: us > 80% 红色
if [ "$CPU_US" -gt 80 ]; then
    print_fail "用户态CPU使用率过高 (${CPU_US}%)，可能导致应用响应缓慢"
elif [ "$CPU_US" -gt 60 ]; then
    print_warn "用户态CPU使用率偏高 (${CPU_US}%)，建议关注"
else
    print_ok "用户态CPU使用率正常 (${CPU_US}%)"
fi

# 内核态CPU阈值判断: sy > 30% 红色
if [ "$CPU_SY" -gt 30 ]; then
    print_fail "内核态CPU使用率过高 (${CPU_SY}%)，可能存在大量系统调用或中断处理"
elif [ "$CPU_SY" -gt 20 ]; then
    print_warn "内核态CPU使用率偏高 (${CPU_SY}%)"
else
    print_ok "内核态CPU使用率正常 (${CPU_SY}%)"
fi

# IO等待阈值判断: wa > 20% 红色
if [ "$CPU_WA" -gt 20 ]; then
    print_fail "IO等待过高 (${CPU_WA}%)，磁盘IO存在严重瓶颈"
elif [ "$CPU_WA" -gt 10 ]; then
    print_warn "IO等待偏高 (${CPU_WA}%)，建议检查磁盘性能"
else
    print_ok "IO等待正常 (${CPU_WA}%)"
fi

echo ""

# ======================== 2. 指定进程CPU检查 ========================
if [ -n "$TARGET_PID" ]; then
    print_info ">>> [2/4] 检查进程 PID=$TARGET_PID 的CPU使用率 ..."

    PROC_CPU=$(ps -p "$TARGET_PID" -o %cpu --no-headers 2>/dev/null | awk '{printf "%.1f", $1}')
    PROC_NAME=$(ps -p "$TARGET_PID" -o comm --no-headers 2>/dev/null)
    PROC_CPU_INT=${PROC_CPU%.*}

    echo "    进程名: ${PROC_NAME}  |  CPU使用率: ${PROC_CPU}%"

    if [ "$PROC_CPU_INT" -gt 80 ]; then
        print_fail "进程 ${PROC_NAME}(${TARGET_PID}) CPU使用率过高 (${PROC_CPU}%)"
        print_info "建议: 检查是否存在死循环、频繁GC或计算密集型操作"
    elif [ "$PROC_CPU_INT" -gt 50 ]; then
        print_warn "进程 ${PROC_NAME}(${TARGET_PID}) CPU使用率偏高 (${PROC_CPU}%)"
    else
        print_ok "进程 ${PROC_NAME}(${TARGET_PID}) CPU使用率正常 (${PROC_CPU}%)"
    fi

    # 检查该进程的线程数
    PROC_THREADS=$(ps -o nlwp -p "$TARGET_PID" --no-headers 2>/dev/null)
    echo "    线程数: ${PROC_THREADS}"
else
    print_info ">>> [2/4] 跳过进程级CPU检查（未指定PID）"
    # 显示CPU使用率最高的进程
    print_info "CPU使用率 TOP 5 进程:"
    ps aux --sort=-%cpu | head -6 | awk 'NR==1{printf "    %-10s %-8s %-6s %-6s %s\n", "USER", "PID", "CPU%", "MEM%", "COMMAND"} NR>1{printf "    %-10s %-8s %-6s %-6s %s\n", $1, $2, $3, $4, $11}'
fi

echo ""

# ======================== 3. 上下文切换检查 ========================
print_info ">>> [3/4] 检查上下文切换率 ..."

# vmstat采样3次，取最后一次数据
VMSTAT_DATA=$(vmstat 1 3 | tail -1)
CS_VALUE=$(echo "$VMSTAT_DATA" | awk '{print $12}')
CS_VALUE=${CS_VALUE:-0}

echo "    当前上下文切换率(cs): ${CS_VALUE}/s"

# 上下文切换阈值判断: cs > 10000 黄色, > 50000 红色
if [ "$CS_VALUE" -gt 50000 ]; then
    print_fail "上下文切换率极高 (${CS_VALUE}/s)，系统调度压力巨大"
    print_info "建议: 检查是否存在线程过多、锁竞争、频繁睡眠唤醒等问题"
elif [ "$CS_VALUE" -gt 10000 ]; then
    print_warn "上下文切换率偏高 (${CS_VALUE}/s)，可能存在线程竞争"
    print_info "建议: 关注线程数和锁的使用情况"
else
    print_ok "上下文切换率正常 (${CS_VALUE}/s)"
fi

echo ""

# ======================== 4. 系统负载检查 ========================
print_info ">>> [4/4] 检查系统负载 ..."

LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}')
LOAD_1M=$(echo "$LOAD_AVG" | awk '{print $1}' | tr -d ',')
LOAD_5M=$(echo "$LOAD_AVG" | awk '{print $2}' | tr -d ',')
LOAD_15M=$(echo "$LOAD_AVG" | awk '{print $3}')

CPU_CORES=$(nproc)

echo "    CPU核心数: ${CPU_CORES}"
echo "    负载均值: 1分钟=${LOAD_1M} | 5分钟=${LOAD_5M} | 15分钟=${LOAD_15M}"

# 负载阈值判断: 负载 > 核心数*2 红色, > 核心数 黄色
LOAD_INT=$(echo "$LOAD_1M" | awk '{printf "%d", $1}')
LOAD_THRESHOLD_HIGH=$((CPU_CORES * 2))
LOAD_THRESHOLD_WARN=$CPU_CORES

if [ "$LOAD_INT" -gt "$LOAD_THRESHOLD_HIGH" ]; then
    print_fail "系统负载过高 (${LOAD_1M})，远超CPU核心数(${CPU_CORES})的2倍"
    print_info "建议: 检查是否有CPU密集型进程或IO阻塞"
elif [ "$LOAD_INT" -gt "$LOAD_THRESHOLD_WARN" ]; then
    print_warn "系统负载偏高 (${LOAD_1M})，已超过CPU核心数(${CPU_CORES})"
else
    print_ok "系统负载正常 (${LOAD_1M})，在CPU核心数(${CPU_CORES})范围内"
fi

echo ""
echo "============================================================"
echo "                     诊断结论"
echo "============================================================"

# 综合判断
ISSUE_COUNT=0

if [ "$CPU_US" -gt 80 ] || [ "$CPU_SY" -gt 30 ] || [ "$CPU_WA" -gt 20 ]; then
    echo -e "  ${RED}[严重]${NC} CPU使用率存在瓶颈，需要立即处理"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$CS_VALUE" -gt 10000 ]; then
    echo -e "  ${YELLOW}[警告]${NC} 上下文切换率偏高，建议优化线程模型"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$LOAD_INT" -gt "$LOAD_THRESHOLD_WARN" ]; then
    echo -e "  ${YELLOW}[警告]${NC} 系统负载偏高，需关注进程调度情况"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$ISSUE_COUNT" -eq 0 ]; then
    echo -e "  ${GREEN}[正常]${NC} CPU状态健康，未发现明显瓶颈"
fi

echo "============================================================"
