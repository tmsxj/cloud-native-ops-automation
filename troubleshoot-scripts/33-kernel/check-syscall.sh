#!/bin/bash
# ============================================================================
# 模块33-计算机基础与内核脚本
# 脚本名称: check-syscall.sh
# 功能: 系统调用分析
# 用法: ./check-syscall.sh [pid]
# 说明: 使用strace分析系统调用频率，检查用户态/内核态时间分布
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
    print_info "指定进程 PID=$TARGET_PID，将进行系统调用追踪"
fi

echo "============================================================"
echo "          系统调用分析报告"
echo "          检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ======================== 1. 系统调用频率分析 ========================
if [ -n "$TARGET_PID" ]; then
    print_info ">>> [1/3] 系统调用频率分析 (PID=${TARGET_PID}) ..."

    PROC_NAME=$(ps -p "$TARGET_PID" -o comm --no-headers 2>/dev/null)
    echo "    进程名: ${PROC_NAME}"

    if command -v strace &>/dev/null; then
        echo ""
        print_info "使用strace -c追踪系统调用(采样3秒)..."
        echo "    注意: strace将附加到进程，采样完成后自动 detach"
        echo ""

        # 使用strace -c进行系统调用统计，运行3秒
        STRACE_RESULT=$(timeout 3 strace -c -p "$TARGET_PID" 2>&1)
        STRACE_EXIT=$?

        if [ $STRACE_EXIT -eq 124 ]; then
            # timeout退出是正常的（采样3秒）
            echo "$STRACE_RESULT" | grep -v "^strace:" | tail -n +2 | while read line; do
                echo "    $line"
            done
        elif [ $STRACE_EXIT -eq 0 ]; then
            echo "$STRACE_RESULT" | tail -n +2 | while read line; do
                echo "    $line"
            done
        else
            print_warn "strace执行失败(退出码:$STRACE_EXIT)，可能需要root权限"
            echo "$STRACE_RESULT" | head -5
        fi

        echo ""
        # 分析高频系统调用
        print_info "高频系统调用分析:"
        STRACE_TOP=$(echo "$STRACE_RESULT" | grep -v "^strace:" | awk 'NR>2 && $1 !~ /total|---/' {
            if ($1+0 > 0) print $1, $6
        }' | sort -rn | head -5)

        if [ -n "$STRACE_TOP" ]; then
            echo "$STRACE_TOP" | while read count syscall; do
                echo "    ${syscall}: ${count}次"
            done

            # 针对高频系统调用给出建议
            echo ""
            echo "    系统调用优化建议:"
            echo "$STRACE_TOP" | while read count syscall; do
                case "$syscall" in
                    read|write|pread|pwrite)
                        echo "    - ${syscall}频率高(${count}次): 考虑使用更大的缓冲区或mmap减少系统调用"
                        ;;
                    futex)
                        echo "    - futex频率高(${count}次): 存在锁竞争，检查并发代码中的锁使用"
                        ;;
                    mmap|munmap)
                        echo "    - mmap/munmap频率高(${count}次): 可能频繁分配释放内存，考虑内存池"
                        ;;
                    clone)
                        echo "    - clone频率高(${count}次): 频繁创建线程/进程，考虑使用线程池"
                        ;;
                    open|openat)
                        echo "    - open/openat频率高(${count}次): 频繁打开文件，考虑使用文件缓存或保持文件描述符"
                        ;;
                    stat|fstat|lstat)
                        echo "    - stat/fstat频率高(${count}次): 频繁查询文件状态，考虑缓存文件元数据"
                        ;;
                    gettimeofday|clock_gettime)
                        echo "    - 时钟调用频率高(${count}次): 考虑使用VDSO减少系统调用开销"
                        ;;
                    epoll_wait|poll|select)
                        echo "    - IO多路复用调用频繁(${count}次): 检查事件循环效率"
                        ;;
                    *)
                        echo "    - ${syscall}频率高(${count}次): 建议分析是否可以批量处理减少调用次数"
                        ;;
                esac
            done
        fi
    else
        print_warn "strace命令不可用"
        print_info "安装: yum install -y strace 或 apt install -y strace"

        # 替代方案: 从/proc获取系统调用信息
        if [ -f "/proc/$TARGET_PID/syscall" ]; then
            CURRENT_SYSCALL=$(cat "/proc/$TARGET_PID/syscall" 2>/dev/null)
            echo "    当前系统调用: $CURRENT_SYSCALL"
        fi
    fi
else
    print_info ">>> [1/3] 跳过系统调用频率分析（未指定PID）"
    print_info "用法: ./check-syscall.sh <pid>"
    print_info "提示: 需要指定PID以进行系统调用级别的分析"
fi

echo ""

# ======================== 2. 用户态/内核态时间分析 ========================
print_info ">>> [2/3] 用户态/内核态时间分析 ..."

if [ -n "$TARGET_PID" ]; then
    # 从/proc/[pid]/stat获取CPU时间
    if [ -f "/proc/$TARGET_PID/stat" ]; then
        PROC_STAT=$(cat "/proc/$TARGET_PID/stat" 2>/dev/null)

        # utime(14) = 用户态时间, stime(15) = 内核态时间 (单位: jiffies)
        UTIME=$(echo "$PROC_STAT" | awk '{print $14}')
        STIME=$(echo "$PROC_STAT" | awk '{print $15}')
        THREADS=$(echo "$PROC_STAT" | awk '{print $20}')

        HZ=$(getconf CLK_TCK 2>/dev/null || echo 100)
        UTIME_SEC=$(echo "scale=2; $UTIME / $HZ" | bc 2>/dev/null)
        STIME_SEC=$(echo "scale=2; $STIME / $HZ" | bc 2>/dev/null)
        TOTAL_TIME=$(echo "$UTIME + $STIME" | bc 2>/dev/null)

        echo "    进程: ${PROC_NAME} (PID=${TARGET_PID})"
        echo "    用户态时间(utime): ${UTIME_SEC}s"
        echo "    内核态时间(stime): ${STIME_SEC}s"
        echo "    总CPU时间: ${TOTAL_TIME}s"
        echo "    线程数: ${THREADS}"

        if [ -n "$UTIME_SEC" ] && [ -n "$STIME_SEC" ] && [ "$(echo "$TOTAL_TIME > 0" | bc 2>/dev/null)" = "1" ]; then
            KERNEL_RATIO=$(echo "scale=1; $STIME_SEC * 100 / $TOTAL_TIME" | bc 2>/dev/null)
            echo "    内核态占比: ${KERNEL_RATIO}%"

            KERNEL_INT=${KERNEL_RATIO%.*}
            if [ "$KERNEL_INT" -gt 50 ]; then
                print_warn "内核态时间占比过高(${KERNEL_RATIO}%)，可能存在大量系统调用"
            elif [ "$KERNEL_INT" -gt 30 ]; then
                print_info "内核态时间占比${KERNEL_RATIO}%，属于正常范围"
            else
                print_ok "内核态时间占比正常(${KERNEL_RATIO}%)"
            fi
        fi
    fi

    # 使用pidstat获取CPU时间分布（如果可用）
    if command -v pidstat &>/dev/null; then
        echo ""
        print_info "pidstat CPU时间分布:"
        pidstat -u 1 3 -p "$TARGET_PID" 2>/dev/null | while read line; do
            echo "    $line"
        done
    fi
else
    # 全局CPU时间分布
    print_info "全局CPU时间分布:"
    CPU_STATS=$(cat /proc/stat 2>/dev/null | grep "^cpu ")
    if [ -n "$CPU_STATS" ]; then
        USER=$(echo "$CPU_STATS" | awk '{print $2}')
        NICE=$(echo "$CPU_STATS" | awk '{print $3}')
        SYSTEM=$(echo "$CPU_STATS" | awk '{print $4}')
        IDLE=$(echo "$CPU_STATS" | awk '{print $5}')
        IOWAIT=$(echo "$CPU_STATS" | awk '{print $6}')
        TOTAL=$((USER + NICE + SYSTEM + IDLE + IOWAIT))

        USER_PCT=$((USER * 100 / TOTAL))
        SYSTEM_PCT=$((SYSTEM * 100 / TOTAL))
        IDLE_PCT=$((IDLE * 100 / TOTAL))
        IOWAIT_PCT=$((IOWAIT * 100 / TOTAL))

        echo "    用户态: ${USER_PCT}%  |  内核态: ${SYSTEM_PCT}%  |  空闲: ${IDLE_PCT}%  |  IO等待: ${IOWAIT_PCT}%"
    fi
fi

echo ""

# ======================== 3. 内核热点分析 ========================
print_info ">>> [3/3] 内核热点分析 ..."

if command -v perf &>/dev/null; then
    if [ -n "$TARGET_PID" ]; then
        print_info "使用perf分析进程内核热点(采样3秒)..."
        PERF_RESULT=$(timeout 3 perf top -p "$TARGET_PID" --no-children -g 2>&1)
        PERF_EXIT=$?

        if [ $PERF_EXIT -eq 0 ] || [ $PERF_EXIT -eq 124 ]; then
            echo "    内核热点函数 TOP 10:"
            echo "$PERF_RESULT" | grep -v "^#" | grep -v "^$" | head -15 | while read line; do
                echo "    $line"
            done
        else
            print_warn "perf执行失败，可能需要root权限或perf未正确配置"
            print_info "尝试: sysctl kernel.perf_event_max_sample_rate=10000"
        fi
    else
        print_info "使用perf分析全局内核热点(采样3秒)..."
        PERF_RESULT=$(timeout 3 perf top --no-children -g 2>&1)
        PERF_EXIT=$?

        if [ $PERF_EXIT -eq 0 ] || [ $PERF_EXIT -eq 124 ]; then
            echo "    全局内核热点函数 TOP 10:"
            echo "$PERF_RESULT" | grep -v "^#" | grep -v "^$" | head -15 | while read line; do
                echo "    $line"
            done
        else
            print_warn "perf执行失败，可能需要root权限"
        fi
    fi
else
    print_warn "perf命令不可用"
    print_info "安装: yum install -y perf 或 apt install -y linux-tools-common"

    # 替代方案: 检查/proc中断
    echo ""
    print_info "中断统计(替代分析):"
    cat /proc/interrupts 2>/dev/null | head -10 | while read line; do
        echo "    $line"
    done
fi

echo ""
echo "============================================================"
echo "                     诊断结论"
echo "============================================================"

if [ -n "$TARGET_PID" ]; then
    echo "  进程 ${PROC_NAME}(${TARGET_PID}) 系统调用分析完成"
    echo ""
    echo "  常见优化方向:"
    echo "  - 减少不必要的系统调用(批量IO、缓冲区复用)"
    echo "  - 使用更高效的系统调用(如splice、sendfile替代read+write)"
    echo "  - 减少锁竞争(无锁数据结构、读写锁替代互斥锁)"
    echo "  - 使用事件驱动模型(epoll)替代轮询(poll/select)"
    echo "  - 考虑使用io_uring(Linux 5.1+)减少系统调用开销"
else
    echo "  未指定PID，仅完成全局分析"
    echo "  用法: ./check-syscall.sh <pid> 进行进程级分析"
fi

echo "============================================================"
