#!/bin/bash
# ============================================================================
# 模块32-网络协议深度解析脚本
# 脚本名称: check-network-latency.sh
# 功能: 网络延迟与丢包诊断
# 用法: ./check-network-latency.sh [target]
# 说明: 通过ping、traceroute、网卡错误统计和TCP重传进行网络诊断
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
TARGET=${1:-"8.8.8.8"}
print_info "目标地址: ${TARGET}"

echo "============================================================"
echo "          网络延迟与丢包诊断报告"
echo "          检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ======================== 1. Ping测试 ========================
print_info ">>> [1/4] Ping测试 (目标: ${TARGET}) ..."

PING_RESULT=$(ping -c 10 -W 2 "$TARGET" 2>&1)
PING_EXIT=$?

if [ $PING_EXIT -ne 0 ]; then
    print_fail "无法Ping通目标 ${TARGET}"
    echo "    $PING_RESULT"
else
    # 解析ping结果
    PKT_TRANSMIT=$(echo "$PING_RESULT" | grep "packets transmitted" | awk '{print $1}')
    PKT_RECEIVED=$(echo "$PING_RESULT" | grep "packets transmitted" | awk '{print $4}')
    PKT_LOSS=$(echo "$PING_RESULT" | grep "packets transmitted" | awk -F'%' '{print $1}' | awk '{print $NF}')
    PKT_LOSS=${PKT_LOSS:-0}

    RTT_MIN=$(echo "$PING_RESULT" | grep "rtt min/avg/max/mdev" | awk -F'/' '{print $4}' | awk '{print $2}')
    RTT_AVG=$(echo "$PING_RESULT" | grep "rtt min/avg/max/mdev" | awk -F'/' '{print $5}')
    RTT_MAX=$(echo "$PING_RESULT" | grep "rtt min/avg/max/mdev" | awk -F'/' '{print $6}')
    RTT_MDEV=$(echo "$PING_RESULT" | grep "rtt min/avg/max/mdev" | awk -F'/' '{print $7}')

    echo "    发送: ${PKT_TRANSMIT}  |  接收: ${PKT_RECEIVED}  |  丢包率: ${PKT_LOSS}%"
    echo "    延迟: min=${RTT_MIN}ms  avg=${RTT_AVG}ms  max=${RTT_MAX}ms  mdev=${RTT_MDEV}ms"

    # 丢包率判断: > 0% 红色
    if [ "$PKT_LOSS" -gt 0 ]; then
        print_fail "存在丢包! 丢包率: ${PKT_LOSS}%"
        print_info "建议: 检查网络链路质量、交换机端口和网线连接"
    else
        print_ok "无丢包"
    fi

    # 延迟判断: avg > 100ms 黄色, > 500ms 红色
    RTT_AVG_INT=${RTT_AVG%.*}
    if [ "$RTT_AVG_INT" -gt 500 ]; then
        print_fail "网络延迟极高 (${RTT_AVG}ms)，网络质量很差"
    elif [ "$RTT_AVG_INT" -gt 100 ]; then
        print_warn "网络延迟偏高 (${RTT_AVG}ms)"
    else
        print_ok "网络延迟正常 (${RTT_AVG}ms)"
    fi

    # 抖动判断: mdev > 50ms 黄色
    RTT_MDEV_INT=${RTT_MDEV%.*}
    if [ "$RTT_MDEV_INT" -gt 50 ]; then
        print_warn "网络抖动较大 (mdev=${RTT_MDEV}ms)，可能存在网络不稳定"
    else
        print_ok "网络抖动正常 (mdev=${RTT_MDEV}ms)"
    fi
fi

echo ""

# ======================== 2. Traceroute检查 ========================
print_info ">>> [2/4] Traceroute路由追踪 (目标: ${TARGET}) ..."

if command -v traceroute &>/dev/null; then
    TRACEROUTE_RESULT=$(traceroute -n -w 2 -m 15 "$TARGET" 2>&1)
    HOP_COUNT=$(echo "$TRACEROUTE_RESULT" | grep -c "^[0-9]")

    echo "    路由跳数: ${HOP_COUNT}"
    echo "    路由路径:"
    echo "$TRACEROUTE_RESULT" | head -15 | while read line; do
        echo "    $line"
    done

    # 检查是否有超时跳
    TIMEOUT_HOPS=$(echo "$TRACEROUTE_RESULT" | grep -c "\* \* \*")
    if [ "$TIMEOUT_HOPS" -gt 3 ]; then
        print_warn "路由路径中有多处超时(${TIMEOUT_HOPS}跳)，可能存在路由问题"
    elif [ "$TIMEOUT_HOPS" -gt 0 ]; then
        print_info "路由路径中有${TIMEOUT_HOPS}跳超时（可能是防火墙屏蔽ICMP）"
    else
        print_ok "路由路径正常，无超时跳"
    fi
else
    print_warn "traceroute命令不可用，跳过路由追踪"
    print_info "安装: yum install -y traceroute 或 apt install -y traceroute"
fi

echo ""

# ======================== 3. 网卡错误检查 ========================
print_info ">>> [3/4] 检查网卡错误统计 ..."

# 获取所有活跃网卡（排除lo和docker等虚拟网卡）
INTERFACES=$(ip link show 2>/dev/null | grep -E "^[0-9]" | grep -v "lo:" | awk -F: '{print $2}' | tr -d ' ')

for iface in $INTERFACES; do
    # 跳过虚拟网卡
    if [[ "$iface" == veth* ]] || [[ "$iface" == docker* ]] || [[ "$iface" == br-* ]]; then
        continue
    fi

    echo "    网卡: ${iface}"

    # 从/proc/net/dev获取统计
    IFACE_STATS=$(grep "$iface" /proc/net/dev 2>/dev/null)
    if [ -n "$IFACE_STATS" ]; then
        RX_PACKETS=$(echo "$IFACE_STATS" | awk '{print $3}')
        TX_PACKETS=$(echo "$IFACE_STATS" | awk '{print $11}')
        RX_ERRS=$(echo "$IFACE_STATS" | awk '{print $4}')
        TX_ERRS=$(echo "$IFACE_STATS" | awk '{print $12}')
        RX_DROP=$(echo "$IFACE_STATS" | awk '{print $5}')
        TX_DROP=$(echo "$IFACE_STATS" | awk '{print $13}')
        RX_FRAME=$(echo "$IFACE_STATS" | awk '{print $6}')
        TX_CARRIER=$(echo "$IFACE_STATS" | awk '{print $14}')

        echo "      接收: ${RX_PACKETS}包 (错误:${RX_ERRS} 丢弃:${RX_DROP} 帧:${RX_FRAME})"
        echo "      发送: ${TX_PACKETS}包 (错误:${TX_ERRS} 丢弃:${TX_DROP} 载波:${TX_CARRIER})"

        # 判断是否有错误
        TOTAL_ERRS=$((RX_ERRS + TX_ERRS + RX_DROP + TX_DROP))
        if [ "$TOTAL_ERRS" -gt 0 ]; then
            print_warn "网卡 ${iface} 存在错误/丢弃: 总计${TOTAL_ERRS}"
            print_info "建议: 检查网线、交换机端口和网卡驱动"
        else
            print_ok "网卡 ${iface} 无错误"
        fi
    fi

    # 尝试使用ethtool获取更详细的错误信息
    if command -v ethtool &>/dev/null; then
        ETHTOOL_ERRS=$(ethtool -S "$iface" 2>/dev/null | grep -iE "error|drop|crc" | grep -v ": 0" | head -5)
        if [ -n "$ETHTOOL_ERRS" ]; then
            echo "      ethtool详细错误:"
            echo "$ETHTOOL_ERRS" | while read line; do
                echo "        $line"
            done
        fi
    fi

    echo ""
done

# ======================== 4. TCP重传统计 ========================
print_info ">>> [4/4] 检查TCP重传统计 ..."

# 从/proc/net/snmp获取TCP统计
TCP_SNMP=$(cat /proc/net/snmp 2>/dev/null | grep "^Tcp:")

if [ -n "$TCP_SNMP" ]; then
    # 解析TCP重传统计
    # Tcp: ... RetransSegs ...
    TCP_FIELDS=$(echo "$TCP_SNMP" | tr '\t' ' ' | sed 's/  */ /g')
    TCP_RETRANS=$(echo "$TCP_FIELDS" | awk '{print $13}')
    TCP_OUTSEGS=$(echo "$TCP_FIELDS" | awk '{print $12}')

    echo "    TCP重传段数: ${TCP_RETRANS}"
    echo "    TCP发送段数: ${TCP_OUTSEGS}"

    if [ "$TCP_OUTSEGS" -gt 0 ]; then
        RETRANS_RATE=$((TCP_RETRANS * 100 / TCP_OUTSEGS))
        echo "    重传率: ${RETRANS_RATE}%"

        if [ "$RETRANS_RATE" -gt 5 ]; then
            print_fail "TCP重传率过高 (${RETRANS_RATE}%)，网络质量差"
            print_info "建议: 检查网络拥塞、交换机缓冲区和MTU设置"
        elif [ "$RETRANS_RATE" -gt 1 ]; then
            print_warn "TCP重传率偏高 (${RETRANS_RATE}%)"
        else
            print_ok "TCP重传率正常 (${RETRANS_RATE}%)"
        fi
    fi
else
    print_warn "无法获取TCP统计信息"
fi

echo ""
echo "============================================================"
echo "                     诊断结论"
echo "============================================================"

ISSUE_COUNT=0

if [ "${PKT_LOSS:-0}" -gt 0 ]; then
    echo -e "  ${RED}[严重]${NC} 存在丢包(丢包率${PKT_LOSS}%)，网络链路不稳定"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "${RTT_AVG_INT:-0}" -gt 100 ]; then
    echo -e "  ${YELLOW}[警告]${NC} 网络延迟偏高(${RTT_AVG}ms)，可能影响应用性能"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "${RETRANS_RATE:-0}" -gt 1 ]; then
    echo -e "  ${YELLOW}[警告]${NC} TCP重传率${RETRANS_RATE}%，网络质量需关注"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$ISSUE_COUNT" -eq 0 ]; then
    echo -e "  ${GREEN}[正常]${NC} 网络延迟与丢包状态健康"
fi

echo "============================================================"
