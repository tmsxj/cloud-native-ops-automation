#!/bin/bash
# ============================================================================
# 模块31-Linux系统故障排查脚本
# 脚本名称: check-diskio.sh
# 功能: 磁盘IO瓶颈诊断
# 用法: ./check-diskio.sh [device]
# 说明: 检查磁盘使用率、IO性能、高IO进程和IO调度器
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
TARGET_DEVICE=""
if [ -n "$1" ]; then
    TARGET_DEVICE=$1
    print_info "指定设备: ${TARGET_DEVICE}"
fi

echo "============================================================"
echo "          磁盘IO瓶颈诊断报告"
echo "          检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ======================== 1. 磁盘使用率检查 ========================
print_info ">>> [1/4] 检查磁盘使用率 ..."

echo "    磁盘分区使用情况:"
echo "    ------------------------------------------------------------------"
printf "    %-20s %-8s %-8s %-8s %-6s %s\n" "Filesystem" "Size" "Used" "Avail" "Use%" "Mounted"
df -h | awk 'NR>1 && /^\/dev/ {printf "    %-20s %-8s %-8s %-8s %-6s %s\n", $1, $2, $3, $4, $5, $6}'
echo "    ------------------------------------------------------------------"

# 检查是否有分区使用率超过阈值
HIGH_USAGE=$(df -h | awk 'NR>1 && /^\/dev/ {
    usage=$5;
    sub(/%/, "", usage);
    if (usage+0 > 85) print $6 " (" usage "%)";
}')

if [ -n "$HIGH_USAGE" ]; then
    print_fail "以下分区使用率超过85%:"
    echo "$HIGH_USAGE" | while read line; do
        echo "    - $line"
    done
    print_info "建议: 清理无用文件或扩展磁盘容量"
else
    print_ok "所有分区使用率正常（均低于85%）"
fi

echo ""

# ======================== 2. IO性能检查 ========================
print_info ">>> [2/4] 检查磁盘IO性能 (采样3秒) ..."

# 检查iostat是否可用
if ! command -v iostat &>/dev/null; then
    print_warn "iostat命令不可用，请安装sysstat包: yum install -y sysstat"
else
    IO_DATA=$(iostat -x 1 3 2>/dev/null)
    # 解析最后一个采样点的数据
    if [ -n "$TARGET_DEVICE" ]; then
        # 指定设备
        IO_LINE=$(echo "$IO_DATA" | grep -E "^${TARGET_DEVICE}" | tail -1)
        if [ -n "$IO_LINE" ]; then
            AWAIT=$(echo "$IO_LINE" | awk '{print $10}')
            UTIL=$(echo "$IO_LINE" | awk '{print $16}')
            R_S=$(echo "$IO_LINE" | awk '{print $4}')
            W_S=$(echo "$IO_LINE" | awk '{print $5}')

            echo "    设备: ${TARGET_DEVICE}"
            echo "    平均IO等待(await): ${AWAIT}ms"
            echo "    IO利用率(%util): ${UTIL}%"
            echo "    每秒读(r/s): ${R_S}  |  每秒写(w/s): ${W_S}"

            # await阈值: > 50ms 红色, > 20ms 黄色
            AWAIT_INT=${AWAIT%.*}
            if [ "$AWAIT_INT" -gt 50 ]; then
                print_fail "IO等待时间过长 (${AWAIT}ms)，磁盘响应严重延迟"
            elif [ "$AWAIT_INT" -gt 20 ]; then
                print_warn "IO等待时间偏高 (${AWAIT}ms)，磁盘可能存在瓶颈"
            else
                print_ok "IO等待时间正常 (${AWAIT}ms)"
            fi

            # %util阈值: > 90% 红色, > 70% 黄色
            UTIL_INT=${UTIL%.*}
            if [ "$UTIL_INT" -gt 90 ]; then
                print_fail "IO利用率过高 (${UTIL}%)，磁盘已接近饱和"
                print_info "建议: 考虑使用SSD、RAID或优化应用IO模式"
            elif [ "$UTIL_INT" -gt 70 ]; then
                print_warn "IO利用率偏高 (${UTIL}%)，磁盘负载较大"
            else
                print_ok "IO利用率正常 (${UTIL}%)"
            fi
        else
            print_warn "未找到设备 ${TARGET_DEVICE} 的IO数据"
        fi
    else
        # 显示所有设备数据
        echo "    所有设备IO数据:"
        echo "    ------------------------------------------------------------------"
        printf "    %-10s %-8s %-8s %-8s %-8s %-8s %-8s\n" "Device" "rrqm/s" "await" "%util" "r/s" "w/s" "avgqu-sz"
        echo "$IO_DATA" | grep -E "^sd|^vd|^nvme|^xvd|^dm-" | while read line; do
            DEV=$(echo "$line" | awk '{print $1}')
            AWAIT=$(echo "$line" | awk '{print $10}')
            UTIL=$(echo "$line" | awk '{print $16}')
            R_S=$(echo "$line" | awk '{print $4}')
            W_S=$(echo "$line" | awk '{print $5}')
            RQM=$(echo "$line" | awk '{print $2}')
            QU=$(echo "$line" | awk '{print $9}')
            printf "    %-10s %-8s %-8s %-8s %-8s %-8s %-8s\n" "$DEV" "$RQM" "${AWAIT}ms" "${UTIL}%" "$R_S" "$W_S" "$QU"
        done
        echo "    ------------------------------------------------------------------"

        # 检查是否有设备超过阈值
        HIGH_AWAIT=$(echo "$IO_DATA" | grep -E "^sd|^vd|^nvme|^xvd|^dm-" | awk '$10+0 > 50 {print $1, $10"ms"}')
        HIGH_UTIL=$(echo "$IO_DATA" | grep -E "^sd|^vd|^nvme|^xvd|^dm-" | awk '$16+0 > 90 {print $1, $16"%"}')

        if [ -n "$HIGH_AWAIT" ]; then
            print_fail "以下设备IO等待过高(>50ms): $(echo $HIGH_AWAIT | tr '\n' ' ')"
        fi
        if [ -n "$HIGH_UTIL" ]; then
            print_fail "以下设备IO利用率过高(>90%): $(echo $HIGH_UTIL | tr '\n' ' ')"
        fi
        if [ -z "$HIGH_AWAIT" ] && [ -z "$HIGH_UTIL" ]; then
            print_ok "所有设备IO性能正常"
        fi
    fi
fi

echo ""

# ======================== 3. 高IO进程检查 ========================
print_info ">>> [3/4] 检查高IO进程 ..."

if ! command -v iotop &>/dev/null; then
    print_warn "iotop命令不可用，使用替代方案检查"
    # 替代方案: 使用/proc读取进程IO信息
    echo "    通过/proc检查进程IO (需要root权限):"
    for pid in $(ls /proc/ 2>/dev/null | grep -E '^[0-9]+$' | head -20); do
        if [ -f "/proc/$pid/io" ] && [ -f "/proc/$pid/comm" ]; then
            READ_BYTES=$(awk '/read_bytes/{print $2}' /proc/$pid/io 2>/dev/null)
            WRITE_BYTES=$(awk '/write_bytes/{print $2}' /proc/$pid/io 2>/dev/null)
            COMM=$(cat /proc/$pid/comm 2>/dev/null)
            if [ "$READ_BYTES" != "0" ] || [ "$WRITE_BYTES" != "0" ]; then
                echo "    PID=$pid COMM=$COMM READ=${READ_BYTES} WRITE=${WRITE_BYTES}"
            fi
        fi
    done | sort -k5 -rn | head -5
else
    IOTOP_DATA=$(iotop -b -n 1 -o 2>/dev/null)
    if [ -n "$IOTOP_DATA" ]; then
        echo "    高IO活动进程:"
        echo "$IOTOP_DATA" | head -15
    else
        print_info "当前没有明显的高IO进程"
    fi
fi

echo ""

# ======================== 4. IO调度器检查 ========================
print_info ">>> [4/4] 检查IO调度器 ..."

# 查找所有块设备
for dev_path in /sys/block/sd* /sys/block/vd* /sys/block/nvme* /sys/block/xvd*; do
    if [ -d "$dev_path" ]; then
        DEV_NAME=$(basename "$dev_path")
        SCHED_FILE="${dev_path}/queue/scheduler"
        if [ -f "$SCHED_FILE" ]; then
            SCHED=$(cat "$SCHED_FILE" 2>/dev/null)
            # 当前调度器用[]标记
            CURRENT_SCHED=$(echo "$SCHED" | grep -o '\[.*\]' | tr -d '[]')
            echo "    设备: ${DEV_NAME}  |  调度器: ${CURRENT_SCHED} (可选: ${SCHED})"
        fi
    fi
done

print_info "建议: SSD设备推荐使用noop或mq-deadline，HDD推荐使用deadline或bfq"

echo ""
echo "============================================================"
echo "                     诊断结论"
echo "============================================================"

ISSUE_COUNT=0

if [ -n "$HIGH_USAGE" ]; then
    echo -e "  ${RED}[严重]${NC} 磁盘使用率超过85%，需要清理或扩容"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ -n "$HIGH_AWAIT" ]; then
    echo -e "  ${RED}[严重]${NC} IO等待时间过长，磁盘性能存在瓶颈"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ -n "$HIGH_UTIL" ]; then
    echo -e "  ${RED}[严重]${NC} IO利用率过高，磁盘接近饱和"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$ISSUE_COUNT" -eq 0 ]; then
    echo -e "  ${GREEN}[正常]${NC} 磁盘IO状态健康，未发现瓶颈"
fi

echo "============================================================"
