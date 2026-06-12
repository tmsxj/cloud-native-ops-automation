#!/bin/bash
# ============================================================================
# 模块33-计算机基础与内核脚本
# 脚本名称: check-scheduler.sh
# 功能: 进程调度与上下文切换分析
# 用法: ./check-scheduler.sh [pid]
# 说明: 检查上下文切换率、运行队列长度、进程级调度和CPU核心数
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
    print_info "指定进程 PID=$TARGET_PID，将进行进程级调度分析"
fi

echo "============================================================"
echo "          进程调度与上下文切换分析报告"
echo "          检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ======================== 1. CPU核心数检查 ========================
print_info ">>> [1/4] 检查CPU核心数 ..."

CPU_CORES=$(nproc)
CPU_SOCKETS=$(lscpu 2>/dev/null | grep "Socket(s):" | awk '{print $2}')
CPU_MODEL=$(lscpu 2>/dev/null | grep "Model name:" | sed 's/Model name:[[:space:]]*//')

echo "    CPU型号: ${CPU_MODEL}"
echo "    逻辑核心数: ${CPU_CORES}"
echo "    CPU插槽数: ${CPU_SOCKETS}"

print_ok "CPU核心数: ${CPU_CORES}（用于运行队列阈值计算）"

echo ""

# ======================== 2. 上下文切换检查 ========================
print_info ">>> [2/4] 检查上下文切换率 ..."

# vmstat采样3次，取平均值
VMSTAT_SAMPLES=$(vmstat 1 3 2>/dev/null)
CS_VALUES=$(echo "$VMSTAT_SAMPLES" | awk 'NR>2 {print $13}')

# 计算平均值
CS_SUM=0
CS_COUNT=0
for val in $CS_VALUES; do
    CS_SUM=$((CS_SUM + val))
    CS_COUNT=$((CS_COUNT + 1))
done

if [ "$CS_COUNT" -gt 0 ]; then
    CS_AVG=$((CS_SUM / CS_COUNT))
else
    CS_AVG=0
fi

echo "    上下文切换率(cs):"
echo "    采样数据: $CS_VALUES"
echo "    平均值: ${CS_AVG}/s"

# 阈值判断: cs > 50000 红色, > 10000 黄色
if [ "$CS_AVG" -gt 50000 ]; then
    print_fail "上下文切换率极高 (${CS_AVG}/s)，系统调度压力巨大"
    print_info "建议: 检查线程数是否过多、是否存在锁竞争、频繁睡眠唤醒"
elif [ "$CS_AVG" -gt 10000 ]; then
    print_warn "上下文切换率偏高 (${CS_AVG}/s)"
    print_info "建议: 关注线程数量和锁的使用情况"
else
    print_ok "上下文切换率正常 (${CS_AVG}/s)"
fi

# 每核心上下文切换率
CS_PER_CORE=$((CS_AVG / CPU_CORES))
echo "    每核心上下文切换率: ${CS_PER_CORE}/s/core"

echo ""

# ======================== 3. 运行队列检查 ========================
print_info ">>> [3/4] 检查运行队列长度 ..."

# 解析vmstat中的r列（运行队列长度）
R_VALUES=$(echo "$VMSTAT_SAMPLES" | awk 'NR>2 {print $1}')

# 计算平均值
R_SUM=0
R_COUNT=0
for val in $R_VALUES; do
    R_SUM=$((R_SUM + val))
    R_COUNT=$((R_COUNT + 1))
done

if [ "$R_COUNT" -gt 0 ]; then
    R_AVG=$((R_SUM / R_COUNT))
else
    R_AVG=0
fi

# 计算最大值
R_MAX=0
for val in $R_VALUES; do
    if [ "$val" -gt "$R_MAX" ]; then
        R_MAX=$val
    fi
done

echo "    运行队列长度(r):"
echo "    采样数据: $R_VALUES"
echo "    平均值: ${R_AVG}  |  最大值: ${R_MAX}"
echo "    CPU核心数: ${CPU_CORES}"

# 阈值判断: r > 核心数*2 红色, r > 核心数 黄色
R_THRESHOLD_HIGH=$((CPU_CORES * 2))
R_THRESHOLD_WARN=$CPU_CORES

if [ "$R_MAX" -gt "$R_THRESHOLD_HIGH" ]; then
    print_fail "运行队列长度过高 (最大${R_MAX})，远超核心数${CPU_CORES}的2倍"
    print_info "建议: CPU严重不足，存在大量进程等待调度"
elif [ "$R_MAX" -gt "$R_THRESHOLD_WARN" ]; then
    print_warn "运行队列长度偏高 (最大${R_MAX})，超过CPU核心数${CPU_CORES}"
    print_info "建议: 关注CPU密集型进程，考虑扩容或优化"
else
    print_ok "运行队列长度正常 (最大${R_MAX})，在核心数${CPU_CORES}范围内"
fi

# 检查可运行进程数
B_VALUES=$(echo "$VMSTAT_SAMPLES" | awk 'NR>2 {print $2}')
echo "    阻塞进程数(b): $B_VALUES"

echo ""

# ======================== 4. 进程级调度分析 ========================
if [ -n "$TARGET_PID" ]; then
    print_info ">>> [4/4] 进程级调度分析 (PID=${TARGET_PID}) ..."

    PROC_NAME=$(ps -p "$TARGET_PID" -o comm --no-headers 2>/dev/null)
    PROC_THREADS=$(ps -o nlwp -p "$TARGET_PID" --no-headers 2>/dev/null)
    PROC_NICE=$(ps -o nice -p "$TARGET_PID" --no-headers 2>/dev/null)
    PROC_PRIO=$(ps -o pri -p "$TARGET_PID" --no-headers 2>/dev/null)
    PROC_POLICY=$(ps -o policy -p "$TARGET_PID" --no-headers 2>/dev/null)

    echo "    进程名: ${PROC_NAME}"
    echo "    线程数: ${PROC_THREADS}"
    echo "    Nice值: ${PROC_NICE}  |  优先级: ${PROC_PRIO}"
    echo "    调度策略: ${PROC_POLICY}"

    # 使用pidstat检查进程上下文切换（如果可用）
    if command -v pidstat &>/dev/null; then
        echo ""
        print_info "进程上下文切换统计(pidstat -w):"
        pidstat -w 1 3 -p "$TARGET_PID" 2>/dev/null | while read line; do
            echo "    $line"
        done
    else
        print_info "pidstat不可用，使用/proc接口"
        # 从/proc获取进程上下文切换信息
        if [ -f "/proc/$TARGET_PID/status" ]; then
            VOLUNTARY=$(grep "voluntary_ctxt_switches" /proc/$TARGET_PID/status 2>/dev/null | awk '{print $2}')
            NONVOLUNTARY=$(grep "nonvoluntary_ctxt_switches" /proc/$TARGET_PID/status 2>/dev/null | awk '{print $2}')
            echo "    自愿上下文切换: ${VOLUNTARY}"
            echo "    非自愿上下文切换: ${NONVOLUNTARY}"
            echo "    总上下文切换: $((VOLUNTARY + NONVOLUNTARY))"
        fi
    fi

    # 线程数评估
    if [ "$PROC_THREADS" -gt 1000 ]; then
        print_fail "进程线程数过多 (${PROC_THREADS})，可能导致调度开销过大"
    elif [ "$PROC_THREADS" -gt 200 ]; then
        print_warn "进程线程数偏多 (${PROC_THREADS})"
    else
        print_ok "进程线程数合理 (${PROC_THREADS})"
    fi
else
    print_info ">>> [4/4] 跳过进程级调度分析（未指定PID）"
    # 显示线程数最多的进程
    print_info "线程数最多的进程 TOP 10:"
    echo "    ------------------------------------------------------------------"
    printf "    %-8s %-8s %-10s %s\n" "PID" "线程数" "USER" "COMMAND"
    ps -eo pid,nlwp,user,comm --sort=-nlwp | head -11 | tail -10 | while read pid nlwp user cmd; do
        printf "    %-8s %-8s %-10s %s\n" "$pid" "$nlwp" "$user" "$cmd"
    done
    echo "    ------------------------------------------------------------------"
fi

echo ""
echo "============================================================"
echo "                     诊断结论"
echo "============================================================"

ISSUE_COUNT=0

if [ "$CS_AVG" -gt 50000 ]; then
    echo -e "  ${RED}[严重]${NC} 上下文切换率极高(${CS_AVG}/s)，系统调度压力巨大"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
elif [ "$CS_AVG" -gt 10000 ]; then
    echo -e "  ${YELLOW}[警告]${NC} 上下文切换率偏高(${CS_AVG}/s)，需优化线程模型"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$R_MAX" -gt "$R_THRESHOLD_HIGH" ]; then
    echo -e "  ${RED}[严重]${NC} 运行队列过长(${R_MAX})，CPU严重不足"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
elif [ "$R_MAX" -gt "$R_THRESHOLD_WARN" ]; then
    echo -e "  ${YELLOW}[警告]${NC} 运行队列偏长(${R_MAX})，超过CPU核心数"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$ISSUE_COUNT" -eq 0 ]; then
    echo -e "  ${GREEN}[正常]${NC} 进程调度状态健康，无异常"
fi

echo "============================================================"
