#!/bin/bash

###############################################################################
# 脚本名称：network-bandwidth-check.sh
# 功能说明：排查服务器带宽是否被占满导致的网络故障
# 适用场景：服务器访问变慢、SSH连接困难、网络服务响应延迟
# 使用方法：sudo ./network-bandwidth-check.sh
# 输出说明：显示当前网络带宽使用情况，异常项会用红色标注
###############################################################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================="
echo -e "  网络带宽使用情况排查"
echo -e "==========================================${NC}"
echo ""

#-------------------------------------------------------------------------------
# 检查1：查看网卡实时流量（每秒更新）
# 目的：观察当前网络接口的实时入站和出站流量
# 原理：ifstat 可以显示网卡的带宽使用情况，如果接近网卡上限说明带宽被打满
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[1] 网卡流量实时监控 (观察5秒) ${NC}"
echo "命令: ifstat 1 5 或 sar -n DEV 1 5"
echo "----------------------------------------------"
if command -v ifstat &> /dev/null; then
    ifstat -n 1 5
elif command -v sar &> /dev/null; then
    sar -n DEV 1 5 | grep -E "eth0|ens|enp"
else
    # 备选方案：使用 /proc/net/dev 获取基本流量信息
    echo "ifstat/sar 未安装，使用备选方案查看 /proc/net/dev:"
    cat /proc/net/dev | grep -E "eth0|ens|enp"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查2：查看流量最大的进程
# 目的：找出是哪个进程在大量使用网络带宽
# 原理：nethogs 可以按进程显示网络流量，帮助定位占用带宽的程序
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[2] 按进程查看网络流量 (占用带宽最大的进程) ${NC}"
echo "命令: nethogs -d 2 (2秒采样间隔)"
echo "----------------------------------------------"
if command -v nethogs &> /dev/null; then
    echo "注意：此命令需要root权限，将显示5秒采样数据"
    timeout 6 nethogs -d 2 eth0 2>/dev/null || timeout 6 nethogs -d 2 2>/dev/null || echo "nethogs采样超时或无可用网卡"
else
    echo "nethogs 未安装，跳过进程级流量分析"
    echo "提示：可执行 'apt install nethogs -y' 或 'yum install nethogs -y' 安装"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查3：查看网络连接数和状态分布
# 目的：统计各状态的连接数，异常高的连接数可能表明网络攻击或异常流量
# 原理：大量 TIME_WAIT 或 ESTABLISHED 连接会占用带宽资源
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[3] 网络连接状态统计 ${NC}"
echo "命令: ss -s"
echo "----------------------------------------------"
ss -s
echo ""

#-------------------------------------------------------------------------------
# 检查4：查看流量最大的IP或端口
# 目的：定位是哪些外部IP或服务端口占用带宽
# 原理：通过流量监控找出通信量最大的对端
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[4] 查看占用带宽最高的IP连接 ${NC}"
echo "命令: iftop -i eth0 -n -P (需安装 iftop)"
echo "----------------------------------------------"
if command -v iftop &> /dev/null; then
    echo "iftop 正在采样5秒，请稍候..."
    timeout 6 iftop -i eth0 -n -P -t -s 5 2>/dev/null | head -50 || echo "iftop采样完成"
else
    echo "iftop 未安装，使用备选方案: netstat 按连接数统计"
    echo "按连接数排名的IP:"
    netstat -an | grep ESTABLISHED | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -10
fi
echo ""

#-------------------------------------------------------------------------------
# 检查5：查看流量异常的时间段
# 目的：分析是否有规律的流量高峰，判断是否为正常业务流量或攻击
# 原理：结合业务时间表，分析流量模式是否正常
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[5] 历史流量分析 (需部署监控) ${NC}"
echo "命令: 查看 Prometheus/Grafana 流量面板"
echo "----------------------------------------------"
# 检查是否有历史监控数据
if [ -f /var/log/traffic.log ]; then
    tail -100 /var/log/traffic.log
else
    echo "未找到历史流量日志"
    echo "建议：部署 Prometheus + node_exporter 长期监控网络流量"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查6：检查是否有异常的大量小包
# 目的：识别 SYN Flood 或小包攻击
# 原理：正常业务流量包大小适中，大量小包可能是攻击
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[6] 网络包大小分布检查 ${NC}"
echo "命令: tcpdump -i eth0 -i eth0 -e | awk '{print $12}' | sort | uniq -c | sort -n | tail -10"
echo "----------------------------------------------"
echo "检查是否存在异常的小包流量（可能为攻击）:"
# 检查 SYN 包数量
SYN_COUNT=$(netstat -an | grep SYN | wc -l)
echo "当前 SYN_RECV 连接数: $SYN_COUNT"
if [ "$SYN_COUNT" -gt 1000 ]; then
    echo -e "${RED}警告：SYN_RECV连接数异常高，可能存在SYN Flood攻击${NC}"
else
    echo -e "${GREEN}当前SYN连接数正常${NC}"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查7：查看网卡带宽配置和协商速率
# 目的：确认网卡是否以最大速率工作，排除硬件问题
# 原理：网卡可能协商到低速率导致带宽不足
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[7] 网卡速率和双工模式检查 ${NC}"
echo "命令: ethtool eth0"
echo "----------------------------------------------"
if command -v ethtool &> /dev/null; then
    for iface in $(ls /sys/class/net/ | grep -E "eth|ens|enp"); do
        echo "网卡: $iface"
        ethtool $iface 2>/dev/null | grep -E "Speed|Duplex|Link detected"
        echo ""
    done
else
    echo "ethtool 未安装"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查8：带宽使用率计算
# 目的：计算当前带宽使用率百分比
# 原理：根据实时流量和网卡最大速率计算使用率
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[8] 带宽使用率评估 ${NC}"
echo "----------------------------------------------"
# 获取当前RX/TX字节数（间隔1秒）
RX1=$(cat /sys/class/net/eth0/statistics/rx_bytes 2>/dev/null || echo 0)
TX1=$(cat /sys/class/net/eth0/statistics/tx_bytes 2>/dev/null || echo 0)
sleep 1
RX2=$(cat /sys/class/net/eth0/statistics/rx_bytes 2>/dev/null || echo 0)
TX2=$(cat /sys/class/net/eth0/statistics/tx_bytes 2>/dev/null || echo 0)

# 计算每秒流量（字节转Mbps，假设eth0）
RX_RATE=$(( ($RX2 - $RX1) * 8 / 1000000 ))
TX_RATE=$(( ($TX2 - $TX1) * 8 / 1000000 ))

echo "当前入站速率: ${RX_RATE} Mbps"
echo "当前出站速率: ${TX_RATE} Mbps"

# 尝试获取网卡速率
SPEED=$(ethtool eth0 2>/dev/null | grep Speed | awk '{print $2}')
if [ -n "$SPEED" ]; then
    echo "网卡标称速率: $SPEED"
    echo "提示：如果接近标称速率，说明带宽可能被打满"
fi
echo ""

#-------------------------------------------------------------------------------
# 排查结论和建议
#-------------------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo -e "  排查结论与建议"
echo -e "==========================================${NC}"
echo ""

echo "【可能原因分析】"
echo "1. 带宽确实被打满 → 检查 iftop/nethogs 输出的流量来源"
echo "2. 网卡协商到低速率 → 使用 ethtool 检查双工模式和速率"
echo "3. 大量小包攻击 → 检查 SYN 连接数和包大小分布"
echo "4. 正常业务高峰 → 分析流量时间分布，确认业务是否需要升级带宽"
echo ""

echo "【处理建议】"
echo "1. 临时措施："
echo "   - 使用 iptables 限制可疑IP的流量"
echo "   - 启用流量QoS限制非关键业务带宽"
echo ""
echo "2. 长期方案："
echo "   - 部署流量监控系统（Prometheus + Grafana）"
echo "   - 配置告警规则，带宽超过80%时自动通知"
echo "   - 考虑升级带宽或添加负载均衡"
echo ""

echo "【常用命令参考】"
echo "  # 安装流量监控工具"
echo "  apt install iftop nethogs ethtool -y  # Ubuntu/Debian"
echo "  yum install iftop nethogs ethtool -y   # CentOS/RHEL"
echo ""
echo "  # 临时限流（限制IP到100Mbps）"
echo "  tc qdisc add dev eth0 root tbf rate 100mbit burst 50kb latency 50ms"
echo ""

echo -e "${BLUE}=========================================="
echo -e "  带宽排查完成"
echo -e "==========================================${NC}"