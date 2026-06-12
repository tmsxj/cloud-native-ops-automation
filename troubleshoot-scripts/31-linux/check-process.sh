#!/bin/bash
# ============================================================================
# 模块31-Linux系统故障排查脚本
# 脚本名称: check-process.sh
# 功能: 僵尸进程与D状态进程诊断
# 用法: ./check-process.sh
# 说明: 检查各状态进程数、僵尸进程、D状态进程和文件句柄使用情况
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
echo "          僵尸进程与D状态进程诊断报告"
echo "          检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ======================== 1. 进程状态统计 ========================
print_info ">>> [1/4] 统计各状态进程数 ..."

# 使用ps统计进程状态分布
# 注意: ps aux第8列为STAT字段
echo "    进程状态分布:"
echo "    ------------------------------------------------------------------"
ps aux | awk 'NR>1 {
    stat=$8
    # 取第一个字符作为主状态
    s=substr(stat, 1, 1)
    count[s]++
}
END {
    printf "    %-10s %-10s %s\n", "状态", "数量", "说明"
    printf "    %-10s %-10s %s\n", "----", "----", "----"
    states["R"]="Running(运行)"
    states["S"]="Sleeping(可中断睡眠)"
    states["D"]="Disk Sleep(不可中断IO)"
    states["Z"]="Zombie(僵尸)"
    states["T"]="Stopped(停止)"
    states["I"]="Idle(空闲)"
    states["t"]="Traced(跟踪)"
    for (s in count) {
        desc = states[s] ? states[s] : "Other(其他)"
        printf "    %-10s %-10s %s\n", s, count[s], desc
    }
    total=0
    for (s in count) total+=count[s]
    printf "    %-10s %-10s %s\n", "总计", total, ""
}'
echo "    ------------------------------------------------------------------"

echo ""

# ======================== 2. 僵尸进程检查 ========================
print_info ">>> [2/4] 检查僵尸进程 ..."

# 查找僵尸进程
ZOMBIE_LIST=$(ps aux | awk '$8 ~ /^Z/ {print $2, $1, $11}')

ZOMBIE_COUNT=$(ps aux | awk '$8 ~ /^Z/' | wc -l)

echo "    僵尸进程数量: ${ZOMBIE_COUNT}"

if [ "$ZOMBIE_COUNT" -gt 10 ]; then
    print_fail "僵尸进程过多 (${ZOMBIE_COUNT}个)，可能存在父进程未正确回收子进程"
    print_info "建议: 检查僵尸进程的父进程，修复子进程回收逻辑(SIGCHLD)"
    echo ""
    echo "    僵尸进程列表:"
    echo "$ZOMBIE_LIST" | head -20 | while read line; do
        echo "    $line"
    done
elif [ "$ZOMBIE_COUNT" -gt 0 ]; then
    print_warn "存在 ${ZOMBIE_COUNT} 个僵尸进程"
    echo ""
    echo "    僵尸进程列表:"
    echo "$ZOMBIE_LIST" | while read line; do
        echo "    $line"
    done
    print_info "建议: 找到父进程并发送SIGCHLD信号，或重启父进程"
else
    print_ok "未发现僵尸进程"
fi

echo ""

# ======================== 3. D状态进程检查 ========================
print_info ">>> [3/4] 检查D状态(不可中断睡眠)进程 ..."

# 查找D状态进程
D_LIST=$(ps aux | awk '$8 ~ /^D/ {print $2, $1, $8, $11}')

D_COUNT=$(ps aux | awk '$8 ~ /^D/' | wc -l)

echo "    D状态进程数量: ${D_COUNT}"

if [ "$D_COUNT" -gt 0 ]; then
    print_fail "发现 ${D_COUNT} 个D状态进程，可能存在IO阻塞或NFS挂起"
    print_info "建议: 检查这些进程是否在等待磁盘IO或网络文件系统"
    echo ""
    echo "    D状态进程列表:"
    echo "$D_LIST" | while read line; do
        echo "    $line"
    done

    # 尝试获取D状态进程的堆栈信息
    echo ""
    print_info "尝试获取D状态进程的内核堆栈(需要root权限):"
    echo "$D_LIST" | while read pid rest; do
        if [ -f "/proc/$pid/stack" ]; then
            echo "    --- PID=$pid 内核堆栈 ---"
            cat "/proc/$pid/stack" 2>/dev/null | head -10 | while read line; do
                echo "    $line"
            done
        fi
    done
else
    print_ok "未发现D状态进程"
fi

echo ""

# ======================== 4. 文件句柄检查 ========================
print_info ">>> [4/4] 检查系统文件句柄使用情况 ..."

# 读取文件句柄信息: file-nr返回 "已分配 已使用 最大值"
FILE_NR=$(cat /proc/sys/fs/file-nr 2>/dev/null)
FILE_ALLOCATED=$(echo "$FILE_NR" | awk '{print $1}')
FILE_USED=$(echo "$FILE_NR" | awk '{print $2}')
FILE_MAX=$(echo "$FILE_NR" | awk '{print $3}')

echo "    文件句柄 - 已分配: ${FILE_ALLOCATED}  |  已使用: ${FILE_USED}  |  最大值: ${FILE_MAX}"

if [ "$FILE_MAX" -gt 0 ]; then
    FILE_USAGE_PERCENT=$((FILE_USED * 100 / FILE_MAX))
    echo "    句柄使用率: ${FILE_USAGE_PERCENT}%"

    # 阈值判断: 使用率 > 80% 黄色, > 95% 红色
    if [ "$FILE_USAGE_PERCENT" -gt 95 ]; then
        print_fail "文件句柄使用率极高 (${FILE_USAGE_PERCENT}%)，系统可能无法打开新文件"
        print_info "建议: 增加fs.file-max或排查句柄泄漏"
    elif [ "$FILE_USAGE_PERCENT" -gt 80 ]; then
        print_warn "文件句柄使用率偏高 (${FILE_USAGE_PERCENT}%)"
        print_info "建议: 监控句柄使用趋势，考虑调大fs.file-max"
    else
        print_ok "文件句柄使用率正常 (${FILE_USAGE_PERCENT}%)"
    fi
else
    print_warn "无法获取文件句柄最大值"
fi

# 检查各进程打开的文件句柄数 TOP 10
echo ""
echo "    打开文件句柄最多的进程 TOP 10:"
echo "    ------------------------------------------------------------------"
printf "    %-8s %-8s %-10s %s\n" "PID" "FDS" "USER" "COMMAND"
for pid in $(ls /proc/ 2>/dev/null | grep -E '^[0-9]+$'); do
    if [ -d "/proc/$pid/fd" ]; then
        fd_count=$(ls "/proc/$pid/fd" 2>/dev/null | wc -l)
        cmd=$(cat "/proc/$pid/comm" 2>/dev/null)
        user=$(stat -c '%U' "/proc/$pid" 2>/dev/null)
        echo "${fd_count} ${pid} ${user} ${cmd}"
    fi
done 2>/dev/null | sort -rn | head -10 | while read fds pid user cmd; do
    printf "    %-8s %-8s %-10s %s\n" "$pid" "$fds" "$user" "$cmd"
done
echo "    ------------------------------------------------------------------"

echo ""
echo "============================================================"
echo "                     诊断结论"
echo "============================================================"

ISSUE_COUNT=0

if [ "$ZOMBIE_COUNT" -gt 10 ]; then
    echo -e "  ${YELLOW}[警告]${NC} 僵尸进程过多(${ZOMBIE_COUNT}个)，需排查父进程回收逻辑"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
elif [ "$ZOMBIE_COUNT" -gt 0 ]; then
    echo -e "  ${YELLOW}[警告]${NC} 存在${ZOMBIE_COUNT}个僵尸进程，建议处理"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$D_COUNT" -gt 0 ]; then
    echo -e "  ${RED}[严重]${NC} 发现${D_COUNT}个D状态进程，可能存在IO阻塞"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$FILE_USAGE_PERCENT" -gt 80 ]; then
    echo -e "  ${YELLOW}[警告]${NC} 文件句柄使用率${FILE_USAGE_PERCENT}%，接近上限"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$ISSUE_COUNT" -eq 0 ]; then
    echo -e "  ${GREEN}[正常]${NC} 进程状态健康，未发现异常"
fi

echo "============================================================"
