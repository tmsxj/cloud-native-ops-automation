#!/bin/bash

###############################################################################
# 脚本名称：system-resource-check.sh
# 功能说明：综合排查系统资源问题（CPU高、内存高、僵尸进程）
# 适用场景：系统负载高、响应缓慢、OOM、进程异常
# 使用方法：sudo ./system-resource-check.sh
# 输出说明：显示CPU/内存/进程信息，异常项用红色标注
###############################################################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo -e "  系统资源综合排查"
echo -e "==========================================${NC}"
echo ""

#-------------------------------------------------------------------------------
# 第一部分：CPU 资源排查
#-------------------------------------------------------------------------------
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  第一部分：CPU 资源排查"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

#-------------------------------------------------------------------------------
# 检查1：CPU 使用率概览
# 目的：查看当前 CPU 总体使用情况
# 原理：top 或 mpstat 显示 CPU 使用率、用户态/内核态占比
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[CPU-1] CPU 使用率概览 ${NC}"
echo "命令: top -bn1 | head -20 或 vmstat 1 3"
echo "----------------------------------------------"
echo "当前系统状态:"
uptime
echo ""
echo "CPU 使用情况:"
top -bn1 | head -20
echo ""

#-------------------------------------------------------------------------------
# 检查2：按进程排序的 CPU 使用率
# 目的：找出占用 CPU 最多的进程
# 原理：top 或 ps 可以按 CPU 使用率排序
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[CPU-2] CPU 占用最高的进程 ${NC}"
echo "命令: ps aux --sort=-%cpu | head -20"
echo "----------------------------------------------"
ps aux --sort=-%cpu | head -20
echo ""

#-------------------------------------------------------------------------------
# 检查3：多核 CPU 使用情况
# 目的：检查是否所有核心都高负载，或只有个别核心繁忙
# 原理：/proc/cpuinfo 或 mpstat -P ALL 显示每个核心的使用率
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[CPU-3] 各 CPU 核心使用情况 ${NC}"
echo "命令: mpstat -P ALL 1 3 或 top 然后按数字键 1"
echo "----------------------------------------------"

if command -v mpstat &> /dev/null; then
    echo "各核心 CPU 使用率:"
    mpstat -P ALL 1 3 2>/dev/null | grep -v "^$" | tail -30
else
    echo "mpstat 未安装，显示 top 输出:"
    top -bn1 | head -15
fi
echo ""

#-------------------------------------------------------------------------------
# 检查4：CPU 负载分析
# 目的：查看系统负载，判断负载来源
# 原理：load average 表示等待 CPU 和等待 I/O 的进程数总和
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[CPU-4] 系统负载分析 ${NC}"
echo "命令: uptime 和 w"
echo "----------------------------------------------"
echo "系统负载:"
uptime
echo ""
echo "当前登录用户和负载来源:"
w
echo ""

# 检查CPU负载是否过高
LOAD_1=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | sed 's/ //g')
CPU_COUNT=$(nproc 2>/dev/null || grep -c processor /proc/cpuinfo)
LOAD_STATUS=$(echo "$LOAD_1 $CPU_COUNT" | awk '{if($1 > $2) print "HIGH"; else if($1 > $2*0.7) print "MEDIUM"; else print "NORMAL"}')

echo "CPU 核心数: $CPU_COUNT"
echo -n "负载状态: "
case $LOAD_STATUS in
    HIGH)
        echo -e "${RED}HIGH - 负载超过CPU核心数！${NC}"
        ;;
    MEDIUM)
        echo -e "${YELLOW}MEDIUM - 负载接近CPU核心数${NC}"
        ;;
    *)
        echo -e "${GREEN}NORMAL - 负载正常${NC}"
        ;;
esac
echo ""

#-------------------------------------------------------------------------------
# 检查5：CPU 使用高峰时段分析
# 目的：分析 CPU 使用是否有规律
# 原理：sar 或历史监控数据可以展示时间序列
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[CPU-5] CPU 使用历史分析 ${NC}"
echo "命令: sar -u 5 5 或查看历史监控"
echo "----------------------------------------------"

if command -v sar &> /dev/null; then
    echo "最近5次采样 (每次间隔5秒):"
    sar -u 5 5 2>/dev/null | grep -v "^$" | tail -10
else
    echo "sar 未安装，无法查看历史数据"
    echo "建议：安装 sysstat 包并配置 cron 收集历史数据"
fi
echo ""

#-------------------------------------------------------------------------------
# 第二部分：内存资源排查
#-------------------------------------------------------------------------------
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  第二部分：内存资源排查"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

#-------------------------------------------------------------------------------
# 检查6：内存使用概览
# 目的：查看总体内存使用情况
# 原理：free -h 显示总内存、已用、可用、缓存
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[MEM-1] 内存使用概览 ${NC}"
echo "命令: free -h"
echo "----------------------------------------------"
free -h
echo ""

# 计算内存使用率
TOTAL=$(free | grep Mem | awk '{print $2}')
USED=$(free | grep Mem | awk '{print $3}')
FREE=$(free | grep Mem | awk '{print $4}')
USAGE=$(echo "scale=1; $USED/$TOTAL*100" | bc 2>/dev/null || echo "N/A")

echo "内存使用率: ${USAGE}%"
echo ""

if command -v bc &> /dev/null; then
    USAGE_INT=$(echo "$USAGE" | cut -d'.' -f1)
    if [ "$USAGE_INT" -ge 90 ]; then
        echo -e "${RED}⚠ 警告：内存使用率超过90%，可能触发OOM${NC}"
    elif [ "$USAGE_INT" -ge 80 ]; then
        echo -e "${YELLOW}⚠ 注意：内存使用率超过80%，建议关注${NC}"
    else
        echo -e "${GREEN}✓ 内存使用率正常${NC}"
    fi
fi
echo ""

#-------------------------------------------------------------------------------
# 检查7：按进程排序的内存使用
# 目的：找出占用内存最多的进程
# 原理：ps 或 top 可以按内存使用排序
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[MEM-2] 内存占用最高的进程 ${NC}"
echo "命令: ps aux --sort=-%mem | head -20"
echo "----------------------------------------------"
ps aux --sort=-%mem | head -20
echo ""

#-------------------------------------------------------------------------------
# 检查8：Swap 使用情况
# 目的：检查是否使用了 Swap，以及 Swap 频繁交换
# 原理：free -h 显示 Swap 总量和使用量，vmstat 显示 si/so
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[MEM-3] Swap 使用分析 ${NC}"
echo "命令: free -h 和 vmstat 1 5"
echo "----------------------------------------------"
echo "Swap 统计:"
free -h | grep Swap
echo ""

# 检查 swapiness 设置
echo "Swapiness 设置 (0-100，越高越倾向于使用Swap):"
cat /proc/sys/vm/swappiness
echo ""

# 检查是否有 Swap I/O
echo "Swap I/O 活动:"
vmstat 1 5 | head -10
echo ""

#-------------------------------------------------------------------------------
# 检查9：内存详细分析 (buffers/cache)
# 目的：区分实际使用的内存和缓存占用的内存
# 原理：Linux 会用空闲内存作为缓存，这部分可以回收
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[MEM-4] 内存详细分析 ${NC}"
echo "----------------------------------------------"

echo "实际可用内存计算:"
echo "  总内存: $(free -h | grep Mem | awk '{print $2}')"
echo "  已使用: $(free -h | grep Mem | awk '{print $3}')"
echo "  缓存/缓冲: $(free -h | grep Mem | awk '{print $6}')"
echo ""

# 计算"实际使用"内存（减去缓存）
if command -v bc &> /dev/null; then
    ACTUAL_USED=$(free | grep Mem | awk '{
        total=$2; used=$3; free=$4; buff=$6;
        actual=used-buff;
        if(actual<0) actual=0;
        printf "%.0f", actual
    }')
    TOTAL_KB=$(free | grep Mem | awk '{print $2}')
    ACTUAL_PCT=$(echo "scale=1; $ACTUAL_USED/$TOTAL_KB*100" | bc)
    echo "实际业务使用（不含缓存）: ${ACTUAL_PCT}%"
    echo "缓存可回收: $(free -h | grep Mem | awk '{print $6}')"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查10：OOM Killer 日志
# 目的：检查是否发生过 OOM（Out of Memory）杀死进程
# 原理：dmesg 或 /var/log/messages 中有 OOM killer 的记录
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[MEM-5] OOM Killer 检查 ${NC}"
echo "命令: dmesg | grep -i 'out of memory' 或 journalctl | grep -i oom"
echo "----------------------------------------------"

echo "最近的 OOM 记录 (如果有):"
dmesg 2>/dev/null | grep -iE "out of memory|oom-killer|killed process" | tail -10 || echo "  未发现 OOM 记录"

echo ""
echo "系统日志中的 OOM:"
journalctl 2>/dev/null | grep -iE "oom|out of memory" | tail -5 || echo "  无 journalctl 记录"
echo ""

#-------------------------------------------------------------------------------
# 第三部分：进程状态排查
#-------------------------------------------------------------------------------
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  第三部分：进程状态排查"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

#-------------------------------------------------------------------------------
# 检查11：僵尸进程检查
# 目的：检查是否存在僵尸进程
# 原理：ps 显示进程状态为 Z (Zombie) 的就是僵尸进程
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[PROC-1] 僵尸进程检查 ${NC}"
echo "命令: ps aux | grep -E '^Z|defunct'"
echo "----------------------------------------------"

ZOMBIE_COUNT=$(ps aux | grep -E '^Z|defunct' | wc -l)
echo "僵尸进程数量: $ZOMBIE_COUNT"

if [ "$ZOMBIE_COUNT" -gt 0 ]; then
    echo -e "${RED}⚠ 发现 $ZOMBIE_COUNT 个僵尸进程！${NC}"
    echo ""
    echo "僵尸进程详情:"
    ps aux | grep -E '^Z|defunct' | head -10
    echo ""
    echo "僵尸进程的父进程:"
    ps aux | grep -E '^Z|defunct' | awk '{print $3}' | sort -u | while read ppid; do
        echo "  父进程 PID $ppid:"
        ps -fp $ppid 2>/dev/null | tail -1
    done
else
    echo -e "${GREEN}✓ 无僵尸进程${NC}"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查12：不可中断睡眠进程
# 目的：检查 D 状态的进程，通常在等待 I/O
# 原理：ps 显示状态为 D (Uninterruptible Sleep) 的进程
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[PROC-2] 不可中断睡眠进程检查 ${NC}"
echo "命令: ps aux | grep ' D '"
echo "----------------------------------------------"

UNINTERRUPTIBLE=$(ps aux | grep ' D ' | grep -v grep | wc -l)
echo "处于 D (Uninterruptible Sleep) 状态的进程: $UNINTERRUPTIBLE"

if [ "$UNINTERRUPTIBLE" -gt 0 ]; then
    echo -e "${YELLOW}注意：有进程在等待I/O（可能是磁盘或网络I/O阻塞）${NC}"
    echo ""
    ps aux | grep ' D ' | grep -v grep
else
    echo -e "${GREEN}✓ 无阻塞的进程${NC}"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查13：进程数量统计
# 目的：检查总进程数是否过多
# 原理：ps 显示进程列表，wc -l 统计数量
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[PROC-3] 进程数量统计 ${NC}"
echo "----------------------------------------------"

echo "各状态进程数量:"
ps -eo stat | tail -n +2 | sort | uniq -c | sort -rn | while read count state; do
    case $state in
        R) state_desc="运行中(Running)" ;;
        S) state_desc="可中断睡眠(Sleeping)" ;;
        D) state_desc="不可中断I/O(Disk Sleep)" ;;
        Z) state_desc="僵尸(Zombie)" ;;
        T) state_desc="已停止(Stopped)" ;;
        t) state_desc="跟踪中(Tracing)" ;;
        X) state_desc="死亡(Dead)" ;;
        *) state_desc="未知($state)" ;;
    esac
    echo "  $state $state_desc: $count"
done

echo ""
TOTAL_PROCS=$(ps -eo pid | tail -n +2 | wc -l)
echo "总进程数: $TOTAL_PROCS"
echo ""

#-------------------------------------------------------------------------------
# 检查14：线程数统计
# 目的：检查线程数量，线程过多也会消耗资源
# 原理：ps 显示线程数，或查看 /proc/*/status 的 Threads
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[PROC-4] 线程数统计 ${NC}"
echo "----------------------------------------------"

echo "线程数最多的进程:"
for pid in $(ls /proc | grep -E '^[0-9]+$' | head -50); do
    if [ -f /proc/$pid/status ]; then
        threads=$(grep Threads /proc/$pid/status 2>/dev/null | awk '{print $2}')
        cmd=$(ps -p $pid -o comm= 2>/dev/null)
        if [ -n "$threads" ] && [ "$threads" -gt 1 ]; then
            echo "$threads $pid $cmd" 2>/dev/null
        fi
    fi
done | sort -rn | head -10 | while read threads pid cmd; do
    echo "  PID $pid ($cmd): $threads 线程"
done
echo ""

#-------------------------------------------------------------------------------
# 检查15：文件描述符使用
# 目的：检查文件描述符是否耗尽
# 原理：ulimit -n 或 /proc/sys/fs/file-nr 显示 FD 使用情况
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[PROC-5] 文件描述符使用 ${NC}"
echo "----------------------------------------------"

echo "系统级 FD 统计:"
FILE_NR=$(cat /proc/sys/fs/file-nr 2>/dev/null)
FILE_MAX=$(cat /proc/sys/fs/file-max 2>/dev/null)
echo "  已使用: $(echo $FILE_NR | awk '{print $1}')"
echo "  最大: $(cat /proc/sys/fs/file-max)"

if [ -n "$FILE_NR" ] && [ -n "$FILE_MAX" ]; then
    USED=$(echo $FILE_NR | awk '{print $1}')
    MAX=$(cat /proc/sys/fs/file-max)
    USAGE=$(echo "scale=1; $USED/$MAX*100" | bc 2>/dev/null || echo "N/A")
    echo "  使用率: ${USAGE}%"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查16：OOM Score 配置
# 目的：查看进程的 OOM Score，调整可以控制被杀优先级
# 原理：/proc/PID/oom_score 和 oom_score_adj
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[PROC-6] OOM Score 检查 ${NC}"
echo "----------------------------------------------"

echo "OOM Score 最高的进程 (分数越高越容易被 OOM Killer 杀死):"
for pid in $(ls /proc | grep -E '^[0-9]+$' | head -100); do
    if [ -f /proc/$pid/oom_score ]; then
        score=$(cat /proc/$pid/oom_score 2>/dev/null)
        cmd=$(ps -p $pid -o comm= 2>/dev/null)
        if [ -n "$score" ] && [ "$score" -gt 100 ]; then
            echo "$score $pid $cmd" 2>/dev/null
        fi
    fi
done | sort -rn | head -10 | while read score pid cmd; do
    echo "  PID $pid ($cmd): OOM Score = $score"
done
echo ""

#-------------------------------------------------------------------------------
# 第四部分：综合诊断和优化建议
#-------------------------------------------------------------------------------
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  综合诊断结论与建议"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "【CPU 高负载】"
echo ""
echo "可能原因："
echo "  1. 某个进程CPU使用率异常高"
echo "  2. 并发请求过多"
echo "  3. 存在死循环或计算密集型任务"
echo ""
echo "处理建议："
echo "  # 定位高CPU进程"
echo "  top   # 按 P 排序"
echo "  htop  # 更友好的界面"
echo ""
echo "  # 终止异常进程"
echo "  kill -TERM <PID>   # 优雅终止"
echo "  kill -KILL <PID>   # 强制终止"
echo ""

echo "【内存高占用】"
echo ""
echo "可能原因："
echo "  1. 内存泄漏"
echo "  2. 缓存未及时释放"
echo "  3. 配置的最大内存不足"
echo ""
echo "处理建议："
echo "  # 清理缓存"
echo "  sync && echo 3 > /proc/sys/vm/drop_caches"
echo ""
echo "  # 调整 swappiness (值越低越少使用swap)"
echo "  sysctl -w vm.swappiness=10"
echo ""
echo "  # 重启问题服务释放内存"
echo "  systemctl restart <服务名>"
echo ""

echo "【僵尸进程】"
echo ""
echo "可能原因："
echo "  1. 父进程未正确回收子进程"
echo "  2. 子进程退出但父进程仍在运行"
echo "  3. 父进程处于 D 状态无法响应"
echo ""
echo "处理建议："
echo "  # 查找僵尸进程的父进程"
echo "  ps -ef | grep -E '^Z|<defunct>'"
echo ""
echo "  # 重启父进程或等待其退出"
echo "  kill -CHLD <父进程PID>   # 触发父进程回收"
echo "  kill -TERM <父进程PID>   # 重启父进程"
echo ""

echo "【进程阻塞】"
echo ""
echo "可能原因："
echo "  1. 等待慢速I/O（网络/磁盘）"
echo "  2. 等待文件锁"
echo "  3. 服务无响应但未完全退出"
echo ""
echo "处理建议："
echo "  # 查看阻塞的进程在做什么"
echo "  strace -p <PID>           # 跟踪系统调用"
echo "  cat /proc/<PID>/stack     # 查看内核栈"
echo ""
echo "  # 查看被锁定的文件"
echo "  lsof +L1                   # 查看被锁定的文件"
echo ""

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  常用资源监控工具 ${NC}"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "安装推荐工具："
echo "  apt install htop iotop ncdu sysstat -y  # Ubuntu/Debian"
echo "  yum install htop iotop ncdu sysstat -y    # CentOS/RHEL"
echo ""

echo "推荐工具说明："
echo "  htop    - 交互式进程查看器（比 top 更友好）"
echo "  iotop   - 按进程查看磁盘 I/O"
echo "  ncdu    - 交互式磁盘使用分析"
echo "  sar     - 系统活动报告（历史数据）"
echo ""

echo -e "${BLUE}=========================================="
echo -e "  系统资源排查完成"
echo -e "==========================================${NC}"