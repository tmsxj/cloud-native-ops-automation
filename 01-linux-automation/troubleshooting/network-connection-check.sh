#!/bin/bash

###############################################################################
# 脚本名称：network-connection-check.sh
# 功能说明：排查连接数耗尽问题
# 适用场景：新建连接失败、连接被拒绝、服务响应缓慢
# 使用方法：sudo ./network-connection-check.sh
# 输出说明：显示各状态连接数统计，异常项用红色标注
###############################################################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo -e "  网络连接数耗尽排查"
echo -e "==========================================${NC}"
echo ""

#-------------------------------------------------------------------------------
# 检查1：查看所有状态的连接数统计
# 目的：快速了解各类连接的数量分布
# 原理：ss -s 或 netstat -an | awk 统计各状态的连接数
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[1] 连接状态分布统计 ${NC}"
echo "命令: ss -s 或 netstat -an | awk '/^tcp/ {print \$6}' | sort | uniq -c"
echo "----------------------------------------------"
echo "连接状态汇总:"
ss -s 2>/dev/null || netstat -an | awk '/^tcp/ {print $6}' | sort | uniq -c
echo ""

#-------------------------------------------------------------------------------
# 检查2：详细列出各状态的连接数
# 目的：找出哪种状态的连接数最多
# 原理：统计 LISTEN、ESTABLISHED、TIME_WAIT、CLOSE_WAIT、SYN_RECV 等各状态数量
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[2] 各状态连接数详细统计 ${NC}"
echo "----------------------------------------------"
echo "状态              数量"
echo "------------------------"

# 统计各状态连接数
for state in LISTEN ESTABLISHED SYN_SENT SYN_RECV FIN_WAIT1 FIN_WAIT2 TIME_WAIT CLOSE CLOSE_WAIT LAST_ACK; do
    count=$(ss -an state $state 2>/dev/null | tail -n +2 | wc -l)
    printf "%-15s %d\n" "$state" "$count"
done
echo ""

#-------------------------------------------------------------------------------
# 检查3：TIME_WAIT 连接数过多
# 目的：大量 TIME_WAIT 会占用端口，可能导致无法建立新连接
# 原理：关闭连接后进入 TIME_WAIT 状态，默认持续60秒
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[3] TIME_WAIT 连接分析 ${NC}"
echo "----------------------------------------------"
TIME_WAIT=$(ss -an state time-wait 2>/dev/null | tail -n +2 | wc -l)
echo "TIME_WAIT 连接数: $TIME_WAIT"

if [ "$TIME_WAIT" -gt 10000 ]; then
    echo -e "${RED}⚠ TIME_WAIT连接数过高，可能导致端口耗尽${NC}"
    echo ""
    echo "TIME_WAIT 来源分析（占用最多的端口）:"
    ss -ant state time-wait 2>/dev/null | tail -n +2 | awk '{print $4}' | cut -d: -f2 | sort | uniq -c | sort -rn | head -10
elif [ "$TIME_WAIT" -gt 1000 ]; then
    echo -e "${YELLOW}⚠ TIME_WAIT连接数偏高${NC}"
else
    echo -e "${GREEN}✓ TIME_WAIT连接数正常${NC}"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查4：CLOSE_WAIT 连接数过多
# 目的：CLOSE_WAIT 表示对端已关闭连接，但本地未关闭socket
# 原理：程序bug或连接泄漏会导致 CLOSE_WAIT 堆积
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[4] CLOSE_WAIT 连接分析 ${NC}"
echo "----------------------------------------------"
CLOSE_WAIT=$(ss -an state close-wait 2>/dev/null | tail -n +2 | wc -l)
echo "CLOSE_WAIT 连接数: $CLOSE_WAIT"

if [ "$CLOSE_WAIT" -gt 1000 ]; then
    echo -e "${RED}⚠ CLOSE_WAIT连接数异常高！存在连接泄漏${NC}"
    echo ""
    echo "导致 CLOSE_WAIT 的进程:"
    ss -ant state close-wait 2>/dev/null | tail -n +2 | awk '{print $4}' | cut -d: -f2 | sort | uniq -c | sort -rn | head -5
elif [ "$CLOSE_WAIT" -gt 100 ]; then
    echo -e "${YELLOW}⚠ CLOSE_WAIT连接数偏高${NC}"
else
    echo -e "${GREEN}✓ CLOSE_WAIT连接数正常${NC}"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查5：ESTABLISHED 连接数分析
# 目的：查看当前活跃连接数，分析是否有异常大量连接
# 原理：ESTABLISHED 表示正常建立的连接，数量过高可能需要扩展
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[5] ESTABLISHED 连接分析 ${NC}"
echo "----------------------------------------------"
ESTABLISHED=$(ss -an state established 2>/dev/null | tail -n +2 | wc -l)
echo "当前 ESTABLISHED 连接数: $ESTABLISHED"
echo ""
echo "连接来源 TOP 10（按IP统计）:"
ss -ant state established 2>/dev/null | tail -n +2 | \
    awk '{print $4}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -10
echo ""

#-------------------------------------------------------------------------------
# 检查6：SYN_RECV 连接数分析
# 目的：检测是否存在 SYN Flood 攻击
# 原理：大量 SYN_RECV 表示服务器收到大量SYN包但未完成握手
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[6] SYN_RECV (半开连接) 分析 ${NC}"
echo "----------------------------------------------"
SYN_RECV=$(ss -an state syn-recv 2>/dev/null | tail -n +2 | wc -l)
echo "SYN_RECV 连接数: $SYN_RECV"

if [ "$SYN_RECV" -gt 5000 ]; then
    echo -e "${RED}⚠ 警告：SYN_RECV连接数极高，可能正在遭受SYN Flood攻击！${NC}"
elif [ "$SYN_RECV" -gt 1000 ]; then
    echo -e "${RED}⚠ SYN_RECV连接数异常，可能存在攻击${NC}"
elif [ "$SYN_RECV" -gt 100 ]; then
    echo -e "${YELLOW}⚠ SYN_RECV连接数偏高${NC}"
else
    echo -e "${GREEN}✓ SYN_RECV连接数正常${NC}"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查7：查看端口使用情况
# 目的：检查是否有端口耗尽的问题
# 原理：客户端使用临时端口(32768-60999)连接服务器，端口耗尽会导致无法新建连接
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[7] 端口使用情况分析 ${NC}"
echo "----------------------------------------------"

# 查看可用端口范围
echo "客户端临时端口范围:"
cat /proc/sys/net/ipv4/ip_local_port_range
echo ""

# 查看各端口使用情况
echo "监听端口及并发连接数:"
ss -ltn 2>/dev/null | tail -n +2 | while read line; do
    port=$(echo $line | awk '{print $4}' | cut -d: -f2)
    estab=$(ss -tn state established 2>/dev/null | grep ":$port" | wc -l)
    echo "  Port $port: $estab 个 ESTABLISHED 连接"
done | sort -t: -k2 -rn | head -15
echo ""

#-------------------------------------------------------------------------------
# 检查8：连接追踪子系统状态
# 目的：查看连接跟踪表使用情况
# 原理：Linux 使用 nf_conntrack 跟踪连接，耗尽后无法建立新连接
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[8] 连接追踪(nf_conntrack)状态检查 ${NC}"
echo "----------------------------------------------"

if [ -f /proc/net/nf_conntrack ]; then
    # 当前连接数
    CONN_COUNT=$(wc -l < /proc/net/nf_conntrack)
    # 最大连接数
    MAX_CONN=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo "未知")

    echo "当前跟踪连接数: $CONN_COUNT"
    echo "最大连接数限制: $MAX_CONN"

    if [ -n "$MAX_CONN" ] && [ "$MAX_CONN" != "未知" ]; then
        USAGE=$(echo "scale=2; $CONN_COUNT / $MAX_CONN * 100" | bc 2>/dev/null || echo "计算失败")
        echo "使用率: ${USAGE}%"
        if [ "$CONN_COUNT" -gt $((MAX_CONN * 90 / 100)) ]; then
            echo -e "${RED}⚠ 连接追踪表即将耗尽！${NC}"
        fi
    fi
else
    echo "连接追踪模块未加载或不可用"
fi
echo ""

#-------------------------------------------------------------------------------
# 检查9：按进程统计连接数
# 目的：找出哪个进程占用了大量连接
# 原理：每个进程打开的 socket 数量有限，进程级连接泄漏也会导致问题
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[9] 按进程统计连接数 ${NC}"
echo "----------------------------------------------"
echo "连接数最多的进程:"
ss -tnp 2>/dev/null | tail -n +2 | \
    awk '{print $6}' | \
    sed 's/.*pid=\([0-9]*\).*/\1/' | \
    sort | uniq -c | sort -rn | head -10

echo ""
echo "各进程打开的socket数量:"
for pid in $(ss -tnp 2>/dev/null | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | sort -u | head -20); do
    count=$(ls -l /proc/$pid/fd 2>/dev/null | grep socket | wc -l)
    name=$(ps -p $pid -o comm= 2>/dev/null || echo "未知")
    echo "  PID $pid ($name): $count sockets"
done | sort -rn | head -10
echo ""

#-------------------------------------------------------------------------------
# 检查10：查看系统级连接数限制
# 目的：检查系统最大文件描述符限制
# 原理：每个连接占用一个文件描述符，FD 耗尽会导致无法建立新连接
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[10] 系统资源限制检查 ${NC}"
echo "----------------------------------------------"

echo "最大文件描述符限制:"
echo "  系统级限制: $(cat /proc/sys/fs/file-max 2>/dev/null)"
echo "  当前使用量: $(cat /proc/sys/fs/file-nr 2>/dev/null | awk '{print $1}')"

echo ""
echo "进程级限制 (ulimit -n):"
ulimit -n
echo ""

#-------------------------------------------------------------------------------
# 检查11：查看 recent 模块（防止 SYN Flood）
# 目的：检查 iptables recent 模块的设置
# 原理：recent 模块可用于限制连接速率
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[11] IP 连接频率限制检查 ${NC}"
echo "----------------------------------------------"
echo "iptables recent 模块统计:"
if ls /proc/net/ipt_recent/ 2>/dev/null; then
    for f in /proc/net/ipt_recent/*; do
        echo "  $(basename $f): $(cat $f 2>/dev/null | wc -l) 条记录"
    done
else
    echo "  ipt_recent 模块未使用或不可用"
fi
echo ""

#-------------------------------------------------------------------------------
# 排查结论
#-------------------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo -e "  连接数耗尽排查结论与建议"
echo -e "==========================================${NC}"
echo ""

echo "【可能原因分析】"
echo ""
echo "1. TIME_WAIT 堆积"
echo "   原因：大量短连接，连接关闭后处于 TIME_WAIT 状态"
echo "   解决：启用 tcp_tw_reuse，调整 tcp_max_tw_buckets"
echo ""
echo "2. CLOSE_WAIT 堆积"
echo "   原因：应用程序未正确关闭连接，连接泄漏"
echo "   解决：检查应用代码，确保及时关闭 socket"
echo ""
echo "3. SYN_RECV 堆积"
echo "   原因：SYN Flood 攻击或服务器来不及处理"
echo "   解决：启用 syncookies，限制连接速率"
echo ""
echo "4. 连接追踪表耗尽"
echo "   原因：nf_conntrack_max 设置过小或连接生命周期过长"
echo "   解决：增加 nf_conntrack_max，优化连接超时时间"
echo ""
echo "5. 端口范围耗尽"
echo   原因：作为客户端建立大量连接，临时端口用尽
echo "   解决：扩大 ip_local_port_range，启用 tcp_tw_reuse"
echo ""

echo "【快速修复命令】"
echo ""
echo "# 紧急措施 - 清理 TIME_WAIT 连接"
echo "sysctl -w net.ipv4.tcp_fin_timeout=30"
echo ""
echo "# 启用 TIME_WAIT 复用"
echo "sysctl -w net.ipv4.tcp_tw_reuse=1"
echo ""
echo "# 增加连接追踪表大小"
echo "sysctl -w net.netfilter.nf_conntrack_max=1048576"
echo ""
echo "# 扩大客户端端口范围"
echo "sysctl -w net.ipv4.ip_local_port_range='1024 65535'"
echo ""
echo "# 启用 SYN cookies 防 SYN Flood"
echo "sysctl -w net.ipv4.tcp_syncookies=1"
echo ""

echo "【长期优化建议】"
echo "  - 调整应用：使用连接池，减少短连接"
echo "  - 内核优化：根据业务调整上述参数"
echo "  - 监控告警：配置连接数阈值告警"
echo "  - 安全防护：部署 DDoS 防护服务"
echo ""

echo -e "${BLUE}=========================================="
echo -e "  连接数排查完成"
echo -e "==========================================${NC}"