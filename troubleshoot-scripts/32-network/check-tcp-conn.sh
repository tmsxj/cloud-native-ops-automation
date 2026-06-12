#!/bin/bash
# ============================================================================
# 模块32-网络协议深度解析脚本
# 脚本名称: check-tcp-conn.sh
# 功能: TCP连接状态分析
# 用法: ./check-tcp-conn.sh [port]
# 说明: 统计各TCP状态连接数，分析TIME_WAIT、ESTABLISHED、CLOSE_WAIT等
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
TARGET_PORT=""
if [ -n "$1" ]; then
    TARGET_PORT=$1
    print_info "指定端口: ${TARGET_PORT}，将过滤该端口的连接"
fi

echo "============================================================"
echo "          TCP连接状态分析报告"
echo "          检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ======================== 1. TCP状态总览 ========================
print_info ">>> [1/5] TCP连接状态总览 ..."

echo "    各状态连接数统计:"
echo "    ------------------------------------------------------------------"
printf "    %-15s %-10s %s\n" "状态" "数量" "说明"
echo "    ------------------------------------------------------------------"

# TCP状态说明
declare -A STATE_DESC=(
    ["ESTAB"]="Established(已建立)"
    ["TIME-WAIT"]="Time-Wait(等待关闭)"
    ["CLOSE-WAIT"]="Close-Wait(等待关闭)"
    ["LISTEN"]="Listen(监听中)"
    ["SYN-SENT"]="Syn-Sent(同步已发送)"
    ["SYN-RECV"]="Syn-Rcv(同步已接收)"
    ["FIN-WAIT-1"]="Fin-Wait-1(终止等待1)"
    ["FIN-WAIT-2"]="Fin-Wait-2(终止等待2)"
    ["LAST-ACK"]="Last-Ack(最后确认)"
    ["CLOSING"]="Closing(关闭中)"
)

# 使用ss统计各状态连接数
TOTAL_CONN=0
for state in ESTAB TIME-WAIT CLOSE-WAIT LISTEN SYN-SENT SYN-RECV FIN-WAIT-1 FIN-WAIT-2 LAST-ACK CLOSING; do
    if [ -n "$TARGET_PORT" ]; then
        COUNT=$(ss -tan "sport = :${TARGET_PORT}" "state ${state}" 2>/dev/null | grep -v "^State" | wc -l)
    else
        COUNT=$(ss -tan "state ${state}" 2>/dev/null | grep -v "^State" | wc -l)
    fi
    DESC=${STATE_DESC[$state]:-"Unknown"}
    if [ "$COUNT" -gt 0 ]; then
        printf "    %-15s %-10s %s\n" "$state" "$COUNT" "$DESC"
    fi
    TOTAL_CONN=$((TOTAL_CONN + COUNT))
done

echo "    ------------------------------------------------------------------"
printf "    %-15s %-10s %s\n" "总计" "$TOTAL_CONN" ""

echo ""

# ======================== 2. TIME_WAIT检查 ========================
print_info ">>> [2/5] 检查TIME_WAIT连接 ..."

if [ -n "$TARGET_PORT" ]; then
    TIME_WAIT_COUNT=$(ss -tan "sport = :${TARGET_PORT}" "state time-wait" 2>/dev/null | grep -v "^State" | wc -l)
else
    TIME_WAIT_COUNT=$(ss -tan "state time-wait" 2>/dev/null | grep -v "^State" | wc -l)
fi

echo "    TIME_WAIT连接数: ${TIME_WAIT_COUNT}"

# 阈值判断: TIME_WAIT > 1000 黄色, > 5000 红色
if [ "$TIME_WAIT_COUNT" -gt 5000 ]; then
    print_fail "TIME_WAIT连接数过多 (${TIME_WAIT_COUNT})，可能耗尽端口资源"
    print_info "建议: 启用tcp_tw_reuse，检查连接关闭模式"
elif [ "$TIME_WAIT_COUNT" -gt 1000 ]; then
    print_warn "TIME_WAIT连接数偏多 (${TIME_WAIT_COUNT})"
    print_info "建议: 关注连接关闭频率，考虑调整tcp_tw_reuse和tcp_fin_timeout"
else
    print_ok "TIME_WAIT连接数正常 (${TIME_WAIT_COUNT})"
fi

# 显示TIME_WAIT连接的TOP目标地址
if [ "$TIME_WAIT_COUNT" -gt 0 ]; then
    echo ""
    echo "    TIME_WAIT连接TOP目标地址:"
    if [ -n "$TARGET_PORT" ]; then
        ss -tan "sport = :${TARGET_PORT}" "state time-wait" 2>/dev/null | grep -v "^State" | \
            awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -5 | \
            while read count ip; do
                echo "    ${count}个连接 -> ${ip}"
            done
    else
        ss -tan "state time-wait" 2>/dev/null | grep -v "^State" | \
            awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -5 | \
            while read count ip; do
                echo "    ${count}个连接 -> ${ip}"
            done
    fi
fi

echo ""

# ======================== 3. ESTABLISHED检查 ========================
print_info ">>> [3/5] 检查ESTABLISHED连接 ..."

if [ -n "$TARGET_PORT" ]; then
    ESTAB_COUNT=$(ss -tan "sport = :${TARGET_PORT}" "state established" 2>/dev/null | grep -v "^State" | wc -l)
else
    ESTAB_COUNT=$(ss -tan "state established" 2>/dev/null | grep -v "^State" | wc -l)
fi

echo "    ESTABLISHED连接数: ${ESTAB_COUNT}"

if [ "$ESTAB_COUNT" -gt 0 ]; then
    print_ok "当前有 ${ESTAB_COUNT} 个活跃连接"

    # 显示ESTABLISHED连接的TOP目标地址
    echo ""
    echo "    ESTABLISHED连接TOP目标地址:"
    if [ -n "$TARGET_PORT" ]; then
        ss -tan "sport = :${TARGET_PORT}" "state established" 2>/dev/null | grep -v "^State" | \
            awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -5 | \
            while read count ip; do
                echo "    ${count}个连接 -> ${ip}"
            done
    else
        ss -tan "state established" 2>/dev/null | grep -v "^State" | \
            awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -5 | \
            while read count ip; do
                echo "    ${count}个连接 -> ${ip}"
            done
    fi
else
    print_info "当前没有活跃的ESTABLISHED连接"
fi

echo ""

# ======================== 4. CLOSE_WAIT检查 ========================
print_info ">>> [4/5] 检查CLOSE_WAIT连接 ..."

if [ -n "$TARGET_PORT" ]; then
    CLOSE_WAIT_COUNT=$(ss -tan "sport = :${TARGET_PORT}" "state close-wait" 2>/dev/null | grep -v "^State" | wc -l)
else
    CLOSE_WAIT_COUNT=$(ss -tan "state close-wait" 2>/dev/null | grep -v "^State" | wc -l)
fi

echo "    CLOSE_WAIT连接数: ${CLOSE_WAIT_COUNT}"

# 阈值判断: CLOSE_WAIT > 100 红色, > 50 黄色
if [ "$CLOSE_WAIT_COUNT" -gt 100 ]; then
    print_fail "CLOSE_WAIT连接数过多 (${CLOSE_WAIT_COUNT})，应用可能未正确关闭连接!"
    print_info "建议: 检查应用代码中的连接关闭逻辑，确保调用close()"
elif [ "$CLOSE_WAIT_COUNT" -gt 50 ]; then
    print_warn "CLOSE_WAIT连接数偏多 (${CLOSE_WAIT_COUNT})"
    print_info "建议: 检查应用是否正确处理连接关闭"
else
    print_ok "CLOSE_WAIT连接数正常 (${CLOSE_WAIT_COUNT})"
fi

# 显示CLOSE_WAIT连接详情
if [ "$CLOSE_WAIT_COUNT" -gt 0 ]; then
    echo ""
    echo "    CLOSE_WAIT连接详情(最多显示10条):"
    if [ -n "$TARGET_PORT" ]; then
        ss -tan "sport = :${TARGET_PORT}" "state close-wait" 2>/dev/null | grep -v "^State" | head -10 | \
            while read line; do
                echo "    $line"
            done
    else
        ss -tan "state close-wait" 2>/dev/null | grep -v "^State" | head -10 | \
            while read line; do
                echo "    $line"
            done
    fi
fi

echo ""

# ======================== 5. 端口范围检查 ========================
print_info ">>> [5/5] 检查本地端口范围 ..."

PORT_RANGE=$(cat /proc/sys/net/ipv4/ip_local_port_range 2>/dev/null)
PORT_MIN=$(echo "$PORT_RANGE" | awk '{print $1}')
PORT_MAX=$(echo "$PORT_RANGE" | awk '{print $2}')
PORT_TOTAL=$((PORT_MAX - PORT_MIN))

echo "    本地端口范围: ${PORT_MIN} - ${PORT_MAX} (共${PORT_TOTAL}个)"

# 计算端口使用率
USED_PORTS=$(ss -tan 2>/dev/null | grep -v "^State" | wc -l)
PORT_USAGE_PERCENT=$((USED_PORTS * 100 / PORT_TOTAL))

echo "    已使用端口数: ${USED_PORTS} (${PORT_USAGE_PERCENT}%)"

if [ "$PORT_USAGE_PERCENT" -gt 80 ]; then
    print_fail "端口使用率过高 (${PORT_USAGE_PERCENT}%)，可能无法分配新端口"
    print_info "建议: 扩大端口范围或检查TIME_WAIT连接"
elif [ "$PORT_USAGE_PERCENT" -gt 50 ]; then
    print_warn "端口使用率偏高 (${PORT_USAGE_PERCENT}%)"
else
    print_ok "端口使用率正常 (${PORT_USAGE_PERCENT}%)"
fi

echo ""
echo "============================================================"
echo "                     诊断结论"
echo "============================================================"

ISSUE_COUNT=0

if [ "$TIME_WAIT_COUNT" -gt 1000 ]; then
    echo -e "  ${YELLOW}[警告]${NC} TIME_WAIT连接数${TIME_WAIT_COUNT}，建议优化连接管理"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$CLOSE_WAIT_COUNT" -gt 100 ]; then
    echo -e "  ${RED}[严重]${NC} CLOSE_WAIT连接数${CLOSE_WAIT_COUNT}，应用可能存在连接泄漏"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
elif [ "$CLOSE_WAIT_COUNT" -gt 50 ]; then
    echo -e "  ${YELLOW}[警告]${NC} CLOSE_WAIT连接数${CLOSE_WAIT_COUNT}，建议检查应用关闭逻辑"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$PORT_USAGE_PERCENT" -gt 80 ]; then
    echo -e "  ${RED}[严重]${NC} 端口使用率${PORT_USAGE_PERCENT}%，面临端口耗尽风险"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$ISSUE_COUNT" -eq 0 ]; then
    echo -e "  ${GREEN}[正常]${NC} TCP连接状态健康"
fi

echo "============================================================"
