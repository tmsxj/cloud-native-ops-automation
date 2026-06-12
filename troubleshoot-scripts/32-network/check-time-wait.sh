#!/bin/bash
# ============================================================================
# 模块32-网络协议深度解析脚本
# 脚本名称: check-time-wait.sh
# 功能: TIME_WAIT连接深度分析
# 用法: ./check-time-wait.sh
# 说明: 分析TIME_WAIT连接数量、分布、内核参数和连接跟踪
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
echo "          TIME_WAIT连接深度分析报告"
echo "          检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ======================== 1. TIME_WAIT数量与分布 ========================
print_info ">>> [1/4] TIME_WAIT连接数量与分布 ..."

# 统计TIME_WAIT总数
TW_TOTAL=$(ss -tan state time-wait 2>/dev/null | grep -v "^State" | wc -l)
echo "    TIME_WAIT连接总数: ${TW_TOTAL}"

if [ "$TW_TOTAL" -gt 5000 ]; then
    print_fail "TIME_WAIT连接数极多 (${TW_TOTAL})，系统面临端口耗尽风险"
elif [ "$TW_TOTAL" -gt 1000 ]; then
    print_warn "TIME_WAIT连接数偏多 (${TW_TOTAL})"
elif [ "$TW_TOTAL" -gt 0 ]; then
    print_ok "TIME_WAIT连接数在正常范围 (${TW_TOTAL})"
else
    print_ok "当前没有TIME_WAIT连接"
fi

# 按目标IP统计分布
if [ "$TW_TOTAL" -gt 0 ]; then
    echo ""
    echo "    TIME_WAIT连接按目标IP分布 TOP 10:"
    echo "    ------------------------------------------------------------------"
    printf "    %-20s %-10s %s\n" "目标IP" "连接数" "占比"
    echo "    ------------------------------------------------------------------"
    ss -tan state time-wait 2>/dev/null | grep -v "^State" | \
        awk '{print $5}' | rev | cut -d: -f2- | rev | sort | uniq -c | sort -rn | head -10 | \
        while read count ip; do
            percent=$((count * 100 / TW_TOTAL))
            printf "    %-20s %-10s %s%%\n" "$ip" "$count" "$percent"
        done
    echo "    ------------------------------------------------------------------"

    # 按本地端口统计
    echo ""
    echo "    TIME_WAIT连接按本地端口分布 TOP 10:"
    ss -tan state time-wait 2>/dev/null | grep -v "^State" | \
        awk '{print $4}' | rev | cut -d: -f1 | rev | sort | uniq -c | sort -rn | head -10 | \
        while read count port; do
            echo "    端口 ${port}: ${count}个TIME_WAIT连接"
        done
fi

echo ""

# ======================== 2. 内核TCP参数检查 ========================
print_info ">>> [2/4] 检查TCP TIME_WAIT相关内核参数 ..."

# tcp_tw_reuse: 是否允许将TIME_WAIT连接复用
TW_REUSE=$(cat /proc/sys/net/ipv4/tcp_tw_reuse 2>/dev/null)
echo "    net.ipv4.tcp_tw_reuse = ${TW_REUSE}"
if [ "$TW_REUSE" -eq 1 ]; then
    print_ok "tcp_tw_reuse已启用，允许复用TIME_WAIT连接作为新连接"
else
    print_warn "tcp_tw_reuse未启用 (当前值: ${TW_REUSE})"
    print_info "建议: 对于客户端角色，可设置 net.ipv4.tcp_tw_reuse=1"
fi

# tcp_tw_recycle: 是否启用TIME_WAIT连接快速回收（注意: Linux 4.12+已移除）
TW_RECYCLE=$(cat /proc/sys/net/ipv4/tcp_tw_recycle 2>/dev/null)
if [ -n "$TW_RECYCLE" ]; then
    echo "    net.ipv4.tcp_tw_recycle = ${TW_RECYCLE}"
    if [ "$TW_RECYCLE" -eq 1 ]; then
        print_warn "tcp_tw_recycle已启用，可能导致NAT环境下连接问题"
        print_info "建议: 在NAT环境中不要启用tcp_tw_recycle"
    fi
else
    echo "    net.ipv4.tcp_tw_recycle = (内核已移除此参数)"
fi

# tcp_fin_timeout: FIN_WAIT超时时间
FIN_TIMEOUT=$(cat /proc/sys/net/ipv4/tcp_fin_timeout 2>/dev/null)
echo "    net.ipv4.tcp_fin_timeout = ${FIN_TIMEOUT}秒"
if [ "$FIN_TIMEOUT" -gt 30 ]; then
    print_warn "tcp_fin_timeout偏长 (${FIN_TIMEOUT}秒)，建议缩短为15-30秒"
else
    print_ok "tcp_fin_timeout设置合理 (${FIN_TIMEOUT}秒)"
fi

# tcp_max_tw_buckets: TIME_WAIT桶的最大数量
MAX_TW_BUCKETS=$(cat /proc/sys/net/ipv4/tcp_max_tw_buckets 2>/dev/null)
echo "    net.ipv4.tcp_max_tw_buckets = ${MAX_TW_BUCKETS}"
TW_USAGE_PERCENT=$((TW_TOTAL * 100 / MAX_TW_BUCKETS))
if [ "$TW_USAGE_PERCENT" -gt 80 ]; then
    print_warn "TIME_WAIT桶使用率${TW_USAGE_PERCENT}%，接近上限${MAX_TW_BUCKETS}"
elif [ "$TW_USAGE_PERCENT" -gt 50 ]; then
    print_info "TIME_WAIT桶使用率${TW_USAGE_PERCENT}%"
else
    print_ok "TIME_WAIT桶使用率正常 (${TW_USAGE_PERCENT}%)"
fi

echo ""

# ======================== 3. 连接跟踪检查 ========================
print_info ">>> [3/4] 检查连接跟踪(nf_conntrack) ..."

# 检查连接跟踪表
if [ -f /proc/net/nf_conntrack ]; then
    CONNTRACK_COUNT=$(wc -l < /proc/net/nf_conntrack 2>/dev/null)
    CONNTRACK_MAX=$(cat /proc/sys/net/nf_conntrack_max 2>/dev/null)
    CONNTRACK_PERCENT=0
    if [ "$CONNTRACK_MAX" -gt 0 ]; then
        CONNTRACK_PERCENT=$((CONNTRACK_COUNT * 100 / CONNTRACK_MAX))
    fi

    echo "    连接跟踪表使用: ${CONNTRACK_COUNT} / ${CONNTRACK_MAX} (${CONNTRACK_PERCENT}%)"

    if [ "$CONNTRACK_PERCENT" -gt 80 ]; then
        print_fail "连接跟踪表使用率过高 (${CONNTRACK_PERCENT}%)，新连接可能被丢弃"
        print_info "建议: 增大net.netfilter.nf_conntrack_max或优化连接跟踪规则"
    elif [ "$CONNTRACK_PERCENT" -gt 50 ]; then
        print_warn "连接跟踪表使用率偏高 (${CONNTRACK_PERCENT}%)"
    else
        print_ok "连接跟踪表使用率正常 (${CONNTRACK_PERCENT}%)"
    fi

    # 统计TIME_WAIT状态的连接跟踪条目
    TW_TRACK=$(grep "TIME_WAIT" /proc/net/nf_conntrack 2>/dev/null | wc -l)
    echo "    TIME_WAIT连接跟踪条目: ${TW_TRACK}"
else
    print_info "nf_conntrack未加载或不可用"
fi

echo ""

# ======================== 4. 优化建议 ========================
print_info ">>> [4/4] TIME_WAIT优化建议汇总 ..."

echo ""
echo "    ============================================================"
echo "    当前配置评估:"
echo "    ============================================================"

# 综合评估
if [ "$TW_TOTAL" -gt 5000 ]; then
    echo -e "    ${RED}[严重]${NC} TIME_WAIT数量${TW_TOTAL}，需要立即优化"
    echo ""
    echo "    推荐优化方案:"
    echo "    1. 启用连接复用:"
    echo "       sysctl -w net.ipv4.tcp_tw_reuse=1"
    echo "    2. 缩短超时时间:"
    echo "       sysctl -w net.ipv4.tcp_fin_timeout=15"
    echo "    3. 增加TIME_WAIT桶上限:"
    echo "       sysctl -w net.ipv4.tcp_max_tw_buckets=262144"
    echo "    4. 使用长连接替代短连接(如HTTP Keep-Alive)"
    echo "    5. 考虑使用连接池管理数据库/Redis连接"
elif [ "$TW_TOTAL" -gt 1000 ]; then
    echo -e "    ${YELLOW}[警告]${NC} TIME_WAIT数量${TW_TOTAL}，建议优化"
    echo ""
    echo "    推荐优化方案:"
    echo "    1. 启用连接复用: sysctl -w net.ipv4.tcp_tw_reuse=1"
    echo "    2. 缩短超时: sysctl -w net.ipv4.tcp_fin_timeout=30"
    echo "    3. 优化应用: 使用长连接减少频繁建连"
else
    echo -e "    ${GREEN}[正常]${NC} TIME_WAIT数量在健康范围内"
    echo ""
    echo "    预防性建议:"
    echo "    1. 确保tcp_tw_reuse=1（客户端角色）"
    echo "    2. 合理设置tcp_fin_timeout（建议15-30秒）"
    echo "    3. 使用长连接减少TIME_WAIT积累"
fi

echo ""
echo "    ============================================================"
echo "    持久化配置(写入/etc/sysctl.conf):"
echo "    ============================================================"
echo "    net.ipv4.tcp_tw_reuse = 1"
echo "    net.ipv4.tcp_fin_timeout = 30"
echo "    net.ipv4.tcp_max_tw_buckets = 262144"
echo "    net.netfilter.nf_conntrack_max = 1048576"
echo "    ============================================================"

echo ""
echo "============================================================"
echo "                     诊断结论"
echo "============================================================"

if [ "$TW_TOTAL" -gt 5000 ]; then
    echo -e "  ${RED}[严重]${NC} TIME_WAIT连接过多，需立即优化内核参数和应用连接模式"
elif [ "$TW_TOTAL" -gt 1000 ]; then
    echo -e "  ${YELLOW}[警告]${NC} TIME_WAIT连接偏多，建议调整内核参数"
else
    echo -e "  ${GREEN}[正常]${NC} TIME_WAIT连接状态健康"
fi

echo "============================================================"
