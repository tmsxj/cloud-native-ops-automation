#!/bin/bash

###############################################################################
# 脚本名称：network-packet-loss-check.sh
# 功能说明：排查网络丢包和TCP重传问题
# 适用场景：网络延迟高、传输速度慢、连接不稳定、数据传输丢包
# 使用方法：sudo ./network-packet-loss-check.sh
# 输出说明：显示丢包率、重传率等网络质量指标，异常项用红色标注
###############################################################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo -e "  网络丢包与TCP重传排查"
echo -e "==========================================${NC}"
echo ""

#-------------------------------------------------------------------------------
# 检查1：查看网卡丢包和错误统计
# 目的：确认网卡层面是否存在丢包或错误
# 原理：ifconfig 或 ip -s link 可以显示网卡的 RX/TX 丢包数、错误数
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[1] 网卡丢包和错误统计 ${NC}"
echo "命令: ifconfig 或 ip -s link show"
echo "----------------------------------------------"
echo "检查各网卡的接收(RX)和发送(TX)丢包情况:"
echo ""
for iface in $(ls /sys/class/net/ | grep -E "eth|ens|enp|lo"); do
    echo ">>> 网卡: $iface"
    # 获取 RX 丢包/错误统计
    RX_DROP=$(cat /sys/class/net/$iface/statistics/rx_dropped 2>/dev/null || echo 0)
    RX_ERRORS=$(cat /sys/class/net/$iface/statistics/rx_errors 2>/dev/null || echo 0)
    TX_DROP=$(cat /sys/class/net/$iface/statistics/tx_dropped 2>/dev/null || echo 0)
    TX_ERRORS=$(cat /sys/class/net/$iface/statistics/tx_errors 2>/dev/null || echo 0)

    echo "  接收(RX) - 丢包: $RX_DROP, 错误: $RX_ERRORS"
    echo "  发送(TX) - 丢包: $TX_DROP, 错误: $TX_ERRORS"

    # 判断是否异常
    if [ "$RX_DROP" -gt 0 ] || [ "$TX_DROP" -gt 0 ]; then
        echo -e "  ${RED}⚠ 发现丢包！需要进一步排查${NC}"
    else
        echo -e "  ${GREEN}✓ 无丢包${NC}"
    fi
    echo ""
done

#-------------------------------------------------------------------------------
# 检查2：查看 TCP 协议层丢包统计
# 目的：统计 TCP 重传、丢失重传、失序等高级指标
# 原理：netstat -s 显示 TCP 协议的详细统计，包括重传率和丢失情况
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[2] TCP协议层丢包统计 ${NC}"
echo "命令: netstat -s | grep -i tcp"
echo "----------------------------------------------"
netstat -s 2>/dev/null | grep -i "segments" | head -20
echo ""

#-------------------------------------------------------------------------------
# 检查3：计算TCP重传率
# 目的：评估网络质量，TCP重传率高说明网络不稳定
# 原理：重传率 = 重传包数 / 总发送包数，通常应低于0.1%
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[3] TCP重传率计算 ${NC}"
echo "----------------------------------------------"
# 获取 TCP 统计（两次采样）
TCP_STATS1=$(cat /proc/net/netstat | grep TcpExt | head -1)
TCP_STATS2=$(cat /proc/net/netstat | grep TcpExt | tail -1)

# 解析关键指标
# TcpExt.ListenOverflows = 监听队列溢出
# TcpExt.ListenDrops = 监听丢包
# TcpExt.TCPRetransFail = 重传失败
# TcpExt.TCPRetransFail = TCP重传失败

echo "TCP扩展统计（累计值）:"
cat /proc/net/netstat | grep TcpExt | awk '{print "RCVAR:" $0}' | column -t

echo ""
echo "关键指标分析:"
# 检查是否存在 TCP 重传相关统计
if grep -q "TCPRetransFail" /proc/net/netstat; then
    RetransFails=$(cat /proc/net/netstat | grep TcpExt | awk '{print $XX}' | head -n XX) # 需要根据实际列位置
    echo "  TCP重传失败计数: 可通过 ss -s 查看"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查4：使用 ping 测试丢包率
# 目的：通过 ICMP 探测检测到目标的丢包情况
# 原理：ping 可以统计发送和接收的包数，计算丢包率百分比
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[4] ICMP Ping 丢包率测试 ${NC}"
echo "命令: ping -c 20 -i 0.2 <目标IP>"
echo "----------------------------------------------"

# 测试到网关的丢包率
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)
if [ -n "$GATEWAY" ]; then
    echo ">>> 测试到网关: $GATEWAY"
    ping -c 10 -i 0.2 $GATEWAY 2>/dev/null | tail -1
    echo ""
fi

echo "提示：请手动测试关键目标地址的丢包情况："
echo "  ping -c 50 -i 0.2 <业务服务器IP>"
echo "  ping -c 50 -i 0.2 8.8.8.8  # 测试外网连通性"
echo ""

#-------------------------------------------------------------------------------
# 检查5：使用 traceroute 检查路由丢包
# 目的：定位丢包发生在哪个网络跳点
# 原理：traceroute 可以显示每一跳的延迟和丢包情况
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[5] Traceroute 路由跳点丢包检查 ${NC}"
echo "命令: traceroute -I <目标IP> 或 mtr <目标IP>"
echo "----------------------------------------------"

# 检查是否有 mtr 工具
if command -v mtr &> /dev/null; then
    echo "使用 mtr 进行持续路由检测（10个包）:"
    if [ -n "$GATEWAY" ]; then
        mtr -r -c 10 $GATEWAY 2>/dev/null || echo "mtr 执行失败"
    fi
else
    echo "mtr 未安装，使用 traceroute:"
    if [ -n "$GATEWAY" ]; then
        traceroute -I -n -w 2 -q 2 $GATEWAY 2>/dev/null | head -15 || echo "traceroute 执行失败"
    fi
fi
echo ""

#-------------------------------------------------------------------------------
# 检查6：查看连接队列和半开连接数
# 目的：检查是否有连接队列溢出导致的丢包
# 原理：SYN Flood 攻击会导致监听队列溢出，新连接被丢弃
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[6] TCP连接队列状态检查 ${NC}"
echo "命令: ss -ltn 或 netstat -s | grep -i listen"
echo "----------------------------------------------"

echo "监听队列状态:"
ss -ltn 2>/dev/null | head -20 || netstat -ltn | head -20

echo ""
echo "监听队列溢出统计:"
if netstat -s 2>/dev/null | grep -q "overflow"; then
    netstat -s 2>/dev/null | grep -iE "overflow|listen|accept"
else
    echo "  监听队列计数器未触发溢出"
fi

# 检查半连接数（SYN_RECV）
SYN_RECV=$(netstat -an | grep SYN_RECV | wc -l)
echo ""
echo "当前 SYN_RECV (半开连接) 数: $SYN_RECV"
if [ "$SYN_RECV" -gt 1000 ]; then
    echo -e "${RED}⚠ 警告：半开连接数异常高，可能存在SYN Flood攻击${NC}"
elif [ "$SYN_RECV" -gt 100 ]; then
    echo -e "${YELLOW}⚠ 注意：半开连接数偏高${NC}"
else
    echo -e "${GREEN}✓ 半开连接数正常${NC}"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查7：检查网络接口缓冲区设置
# 目的：查看网卡和协议栈的缓冲区配置是否合理
# 原理：缓冲区过小会导致丢包，过大会增加延迟
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[7] 网络缓冲区配置检查 ${NC}"
echo "命令: ethtool -g/-G eth0 查看和设置 ring buffer"
echo "----------------------------------------------"

if command -v ethtool &> /dev/null; then
    for iface in $(ls /sys/class/net/ | grep -E "eth|ens|enp"); do
        echo ">>> 网卡: $iface"
        # 查看 ring buffer
        echo "Ring Buffer 设置:"
        ethtool -g $iface 2>/dev/null | grep -E "Ring parameters|tx|rx" || echo "  无法获取 ring buffer 信息"
        echo ""

        # 查看网卡队列状态
        echo "多队列状态:"
        ethtool -l $iface 2>/dev/null | head -10 || echo "  无法获取多队列信息"
        echo ""
    done
else
    echo "ethtool 未安装，跳过网卡硬件配置检查"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查8：检查内核网络参数
# 目的：查看与丢包相关的内核参数设置
# 原理：somaxconn、tcp_max_syn_backlog 等参数影响连接处理和丢包
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[8] 内核网络参数检查 ${NC}"
echo "命令: sysctl -a | grep -E 'tcp_|net.core' | grep -v '#'"
echo "----------------------------------------------"

echo "关键网络参数（可能导致丢包的配置）:"
sysctl -a 2>/dev/null | grep -E "^net\.ipv4\.tcp_max_syn_backlog|^net\.ipv4\.tcp_syncookies|^net\.core\.somaxconn|^net\.ipv4\.tcp_timestamps|^net\.ipv4\.tcp_sack" | column -t
echo ""

#-------------------------------------------------------------------------------
# 检查9：查看软中断负载分布
# 目的：检查 CPU 是否成为网络处理瓶颈
# 原理：网络数据包通过软中断处理，如果单个 CPU 负载高会导致处理不过来丢包
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[9] 网络软中断(CPU)负载检查 ${NC}"
echo "命令: cat /proc/softirqs 或 mpstat -I SUM 1 3"
echo "----------------------------------------------"

echo "软中断分布（各CPU处理网络中断的情况）:"
cat /proc/softirqs 2>/dev/null | head -10

echo ""
echo "CPU 负载与网络处理:"
if command -v mpstat &> /dev/null; then
    mpstat -I SUM 1 3 2>/dev/null || echo "mpstat 不可用"
else
    echo "mpstat 未安装，使用备选方案:"
    top -bn2 -d 1 | grep "Cpu(s)" | tail -1
fi
echo ""

#-------------------------------------------------------------------------------
# 排查结论
#-------------------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo -e "  丢包排查结论与建议"
echo -e "==========================================${NC}"
echo ""

echo "【丢包原因分析】"
echo ""
echo "1. 网卡层面丢包"
echo "   症状：rx_dropped 或 tx_dropped > 0"
echo "   原因：Ring Buffer 不足、网卡故障、驱动问题"
echo "   对策：检查 ethtool -g 增加 ring buffer，更新驱动"
echo ""
echo "2. TCP协议层丢包"
echo "   症状：netstat 显示大量 Retransmits"
echo "   原因：网络拥塞、路由不稳定、高延迟链路"
echo "   对策：使用 mtr 定位问题节点，优化路由"
echo ""
echo "3. 连接队列溢出"
echo "   症状：ListenOverflows 或 ListenDrops > 0"
echo "   原因：SYN Flood 攻击、突发高并发"
echo "   对策：启用 syncookies，增加 somaxconn"
echo ""
echo "4. CPU瓶颈导致丢包"
echo "   症状：单个 CPU softirq 负载高"
echo "   原因：网卡多队列未启用、中断集中在单个 CPU"
echo "   对策：启用 RPS/RFS，配置 irqbalance"
echo ""

echo "【处理建议】"
echo ""
echo "临时措施："
echo "  # 临时扩大 ring buffer"
echo "  ethtool -G eth0 rx 4096 tx 4096"
echo ""
echo "  # 启用 syncookies 防 SYN Flood"
echo "  sysctl -w net.ipv4.tcp_syncookies=1"
echo ""
echo "  # 增加连接队列"
echo "  sysctl -w net.core.somaxconn=65535"
echo "  sysctl -w net.ipv4.tcp_max_syn_backlog=65535"
echo ""

echo "长期方案："
echo "  - 部署网络监控系统（如 Prometheus + node_exporter）"
echo "  - 配置丢包率告警（阈值建议：丢包率 > 0.1%）"
echo "  - 定期检查和优化网络参数"
echo "  - 使用高质量网络设备和线路"
echo ""

echo -e "${BLUE}=========================================="
echo -e "  丢包排查完成"
echo -e "==========================================${NC}"