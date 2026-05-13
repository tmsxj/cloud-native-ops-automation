#!/bin/bash

###############################################################################
# 脚本名称：disk-io-check.sh
# 功能说明：排查磁盘I/O性能问题
# 适用场景：服务器卡顿、读写速度慢、响应延迟高
# 使用方法：sudo ./disk-io-check.sh
# 注意事项：需要root权限以获取准确的I/O统计
# 输出说明：显示I/O使用率、读写速度等，异常项用红色标注
###############################################################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo -e "  磁盘I/O性能排查"
echo -e "==========================================${NC}"
echo ""

#-------------------------------------------------------------------------------
# 检查1：实时I/O使用情况
# 目的：查看当前磁盘I/O的实时使用率
# 原理：iostat -x 显示每个设备的 I/O 使用率、利用率等指标
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[1] 实时I/O监控 (5秒采样) ${NC}"
echo "命令: iostat -x 1 5"
echo "----------------------------------------------"

if command -v iostat &> /dev/null; then
    iostat -x 1 5 2>/dev/null
else
    echo "iostat 未安装，尝试使用 /proc/diskstats"
    cat /proc/diskstats | head -20
fi
echo ""

#-------------------------------------------------------------------------------
# 检查2：查看各设备的I/O等待
# 目的：I/O等待高说明CPU在等待磁盘响应，是I/O瓶颈的典型特征
# 原理：iostat 的 %util 或 vmstat 的 wa 列显示I/O等待时间占比
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[2] I/O等待时间分析 ${NC}"
echo "命令: iostat -x 1 5 或 vmstat 1 5"
echo "----------------------------------------------"

if command -v vmstat &> /dev/null; then
    echo "CPU等待I/O时间占比 (wa列):"
    vmstat 1 5
    echo ""
fi

if command -v iostat &> /dev/null; then
    echo "各设备I/O使用率:"
    iostat -x 1 3 2>/dev/null | grep -E "Device|%util" | tail -20
fi
echo ""

#-------------------------------------------------------------------------------
# 检查3：查看哪些进程在产生大量I/O
# 目的：定位是哪个进程导致磁盘I/O高
# 原理：iotop 可以按进程显示I/O使用情况
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[3] 按进程查看I/O使用情况 (iotop) ${NC}"
echo "命令: iotop -aoP -b -n 3 (非交互模式，采样3次)"
echo "----------------------------------------------"

if command -v iotop &> /dev/null; then
    echo "产生I/O最多的进程 (3次采样):"
    iotop -aoP -b -n 3 2>/dev/null | grep -E "^\([0-9]|Total" | head -30 || echo "iotop 采样完成"
else
    echo "iotop 未安装，使用备选方案: 读取 /proc/*/io"
    echo ""
    echo "产生大量读写的进程:"
    for pid in $(ls /proc | grep -E '^[0-9]+$'); do
        if [ -f /proc/$pid/io ]; then
            read_bytes=$(grep rchar /proc/$pid/io 2>/dev/null | awk '{print $2}')
            write_bytes=$(grep wchar /proc/$pid/io 2>/dev/null | awk '{print $2}')
            if [ -n "$read_bytes" ] && [ "$read_bytes" -gt 100000000 ]; then
                cmd=$(ps -p $pid -o comm= 2>/dev/null)
                echo "  PID $pid ($cmd): 读取 $(($read_bytes/1024/1024)) MB"
            fi
        fi
    done | head -10
fi
echo ""

#-------------------------------------------------------------------------------
# 检查4：查看读写速度统计
# 目的：了解磁盘当前的读写速率
# 原理：/proc/diskstats 或 iostat 提供每秒读写的数据量
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[4] 磁盘读写速度统计 ${NC}"
echo "命令: iostat -d 1 3"
echo "----------------------------------------------"

if command -v iostat &> /dev/null; then
    iostat -d 1 3 2>/dev/null | grep -E "Device|tps|MB/s"
    echo ""

    echo "各设备读写速度 (MB/s):"
    iostat -d -m 1 3 2>/dev/null | tail -20
else
    echo "iostat 未安装"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查5：查看磁盘队列深度
# 目的：队列深度高说明有大量I/O请求在等待处理
# 原理：avgqu-sz 表示平均请求队列长度
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[5] 磁盘队列深度分析 ${NC}"
echo "命令: iostat -x 1 3 (查看 avgqu-sz 列)"
echo "----------------------------------------------"

if command -v iostat &> /dev/null; then
    iostat -x 1 3 2>/dev/null | grep -v "^$" | head -20
    echo ""

    # 解释队列深度的含义
    echo "队列深度解释:"
    echo "  < 1: 正常，磁盘处理能力充足"
    echo "  1-4: 轻微繁忙，接近饱和"
    echo "  > 4: 严重繁忙，磁盘成为瓶颈"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查6：查看SSD特有的信息（如果使用SSD）
# 目的：检查SSD的TBW(总写入量)、温度、健康状态
# 原理：smartctl 可以查看SSD的SMART信息
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[6] SSD/SATA 磁盘健康检查 ${NC}"
echo "命令: smartctl -a /dev/sda"
echo "----------------------------------------------"

if command -v smartctl &> /dev/null; then
    for disk in $(ls /dev/sd* 2>/dev/null | grep -E 'sd[a-z]$' | head -3); do
        echo ">>> 磁盘: $disk"
        smartctl -H $disk 2>/dev/null | grep -E "SMART|test|Result|PASSED|FAILED" || echo "  无法获取SMART信息"
        echo ""

        # 查看通电时间和写入量
        echo "  关键SMART指标:"
        smartctl -a $disk 2>/dev/null | grep -E "^9|^12|^194|^197|^198" | head -5
        echo ""
    done
else
    echo "smartctl 未安装，跳过磁盘健康检查"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查7：查看文件系统碎片程度
# 目的：碎片过多会影响随机读写性能
# 原理：ext4文件系统可以使用 filefrag 检查碎片
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[7] 文件系统碎片检查 ${NC}"
echo "命令: filefrag -v 或 fsck -n"
echo "----------------------------------------------"

# 检查根分区的碎片
if command -v filefrag &> /dev/null; then
    echo "检查关键文件的碎片情况:"
    for file in /bin/bash /usr/bin/ls /etc/passwd; do
        if [ -f "$file" ]; then
            fragments=$(filefrag "$file" 2>/dev/null | tail -1 | awk '{print $2}')
            echo "  $file: $fragments 个碎片"
        fi
    done
    echo ""
    echo "注意: ext4文件系统通常不需要定期碎片整理"
    echo "      如果需要整理，可使用 e4defrag 工具"
else
    echo "filefrag 未安装"
fi

# 检查文件系统状态
echo ""
echo "文件系统状态:"
df -T | grep -v "tmpfs\|devtmpfs" | tail -n +2
echo ""

#-------------------------------------------------------------------------------
# 检查8：查看I/O调度器设置
# 目的：不同的调度器适合不同的I/O模式
# 原理：SSD应使用 none/noop，机械盘可用 mq-deadline 或 bfq
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[8] I/O调度器检查 ${NC}"
echo "命令: cat /sys/block/sda/queue/scheduler"
echo "----------------------------------------------"

for disk in /sys/block/sd* /sys/block/nvme*; do
    if [ -d "$disk" ]; then
        disk_name=$(basename $disk)
        scheduler=$(cat $disk/queue/scheduler 2>/dev/null)
        echo "磁盘: $disk_name"
        echo "  当前调度器: $scheduler"

        # 检查调度器类型
        if [[ "$scheduler" == *"none"* ]] || [[ "$scheduler" == *"noop"* ]]; then
            echo -e "  ${GREEN}✓ SSD优化配置${NC}"
        elif [[ "$scheduler" == *"deadline"* ]]; then
            echo -e "  ${YELLOW}适合机械盘或混合存储${NC}"
        elif [[ "$scheduler" == *"bfq"* ]]; then
            echo "  适合桌面/多媒体应用"
        fi
        echo ""
    fi
done

#-------------------------------------------------------------------------------
# 检查9：查看读缓存和写缓存设置
# 目的：检查磁盘缓存是否启用，以及write-back/write-through模式
# 原理：hdparm -i /dev/sda 可以查看缓存信息
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[9] 磁盘缓存设置检查 ${NC}"
echo "命令: hdparm -i /dev/sda 或 cat /sys/block/sda/queue/write_cache"
echo "----------------------------------------------"

for disk in /dev/sd*; do
    if [ -b "$disk" ]; then
        echo "磁盘: $disk"
        # 查看读写缓存设置
        if [ -f "/sys/block/$(basename $disk)/queue/write_cache" ]; then
            cat /sys/block/$(basename $disk)/queue/write_cache 2>/dev/null
        fi

        if command -v hdparm &> /dev/null; then
            echo "hdparm 信息:"
            hdparm -i $disk 2>/dev/null | grep -E "Model|Cache|Buffer" | head -5
        fi
        echo ""
    fi
done

#-------------------------------------------------------------------------------
# 检查10：使用 fio 进行简单I/O基准测试
# 目的：快速评估磁盘的读写性能
# 原理：fio 是标准的I/O性能测试工具
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[10] 简单I/O性能测试 (可选) ${NC}"
echo "命令: fio --name=randread --rw=randread --bs=4k --size=1G --runtime=10 --ioengine=libaio"
echo "----------------------------------------------"

if command -v fio &> /dev/null; then
    echo "执行简单的4K随机读测试 (10秒)..."
    echo "注意：此测试会占用大量I/O资源，生产环境慎用"
    fio --name=randread --rw=randread --bs=4k --size=1G --runtime=10 --ioengine=libaio --direct=1 --runtime=10 2>/dev/null | grep -E "read|IOPS|latency"
else
    echo "fio 未安装，跳过性能测试"
    echo "如需测试，可执行: apt install fio -y"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查11：查看当前I/O操作的详细信息
# 目的：查看当前正在进行的I/O操作
# 原理：/proc/diskstats 和 ps 可以查看实时I/O活动
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[11] 当前I/O活动查看 ${NC}"
echo "命令: iotop 或 ps aux | sort -k6"
echo "----------------------------------------------"

# 查看正在等待I/O的进程
echo "正在等待I/O的进程:"
if [ -f /proc/diskstats ]; then
    # 统计等待I/O的进程数
    waiting_procs=$(ps -eo stat,pid,comm | grep -E "^D" | wc -l)
    echo "处于 D (Uninterruptible Sleep) 状态的进程数: $waiting_procs"

    if [ "$waiting_procs" -gt 10 ]; then
        echo -e "${RED}警告：大量进程在等待I/O${NC}"
        echo "详细信息:"
        ps -eo stat,pid,comm | grep -E "^D" | head -10
    fi
fi
echo ""

#-------------------------------------------------------------------------------
# 排查结论
#-------------------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo -e "  I/O性能排查结论与建议"
echo -e "==========================================${NC}"
echo ""

echo "【I/O性能瓶颈原因分析】"
echo ""
echo "1. 磁盘使用率 100%"
echo "   表现: iostat 显示 %util 接近 100%"
echo "   解决: 考虑升级到SSD、使用RAID、添加缓存"
echo ""
echo "2. I/O等待过高"
echo "   表现: CPU的wa列长时间高于30%"
echo "   解决: 优化应用I/O模式、使用SSD、调整调度器"
echo ""
echo "3. 读写混合冲突"
echo "   表现: 读和写同时都很高"
echo "   解决: 分离读写到不同磁盘、使用高性能存储"
echo ""
echo "4. 小文件I/O过多"
echo "   表现: 大量随机读写，吞吐量低"
echo "   解决: 合并小文件、使用tmpfs、优化应用"
echo ""

echo "【I/O优化建议】"
echo ""
echo "1. 调度器优化:"
echo "   # SSD使用noop调度器"
echo "   echo none > /sys/block/sda/queue/scheduler"
echo ""
echo "2. 提升应用性能:"
echo "   - 使用 O_DIRECT 绕过缓存"
echo "   - 使用异步I/O (libaio)"
echo "   - 批量读写，减少I/O次数"
echo ""
echo "3. 文件系统优化:"
echo "   - 挂载选项: noatime,nodiratime (减少写操作)"
echo "   - XFS通常比ext4性能更好"
echo ""
echo "4. 使用缓存:"
echo "   - 使用 SSD 作为缓存 (bcache, flashcache)"
echo "   - 使用内存缓存 (tmpfs, redis)"
echo ""

echo "【常用工具安装】"
echo "  apt install iotop sysstat smartmontools fio -y  # Ubuntu/Debian"
echo "  yum install iotop sysstat smartmontools fio -y   # CentOS/RHEL"
echo ""

echo -e "${BLUE}=========================================="
echo -e "  I/O排查完成"
echo -e "==========================================${NC}"