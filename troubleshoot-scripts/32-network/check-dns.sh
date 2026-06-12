#!/bin/bash
# ============================================================================
# 模块32-网络协议深度解析脚本
# 脚本名称: check-dns.sh
# 功能: DNS解析诊断
# 用法: ./check-dns.sh [domain]
# 说明: 测试DNS解析时间、追踪解析路径、检查resolv.conf和对比DNS服务器
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
DOMAIN=${1:-"www.baidu.com"}
print_info "目标域名: ${DOMAIN}"

# 常用DNS服务器列表
DNS_SERVERS=(
    "114.114.114.114:114 DNS(国内公共)"
    "223.5.5.5:阿里DNS"
    "8.8.8.8:Google DNS"
    "8.8.4.4:Google DNS备用"
    "1.1.1.1:Cloudflare DNS"
    "208.67.222.222:OpenDNS"
)

echo "============================================================"
echo "          DNS解析诊断报告"
echo "          检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ======================== 1. DNS解析时间测试 ========================
print_info ">>> [1/4] DNS解析时间测试 ..."

if command -v dig &>/dev/null; then
    DIG_RESULT=$(dig +stats "$DOMAIN" 2>&1)

    # 提取Query time
    QUERY_TIME=$(echo "$DIG_RESULT" | grep "Query time" | awk '{print $4}')
    QUERY_TIME=${QUERY_TIME:-0}

    echo "    域名: ${DOMAIN}"
    echo "    查询耗时: ${QUERY_TIME}ms"

    # 提取解析结果
    ANSWER_IP=$(echo "$DIG_RESULT" | grep -A1 "ANSWER SECTION" | tail -1 | awk '{print $NF}')
    echo "    解析结果: ${ANSWER_IP}"

    # 提取DNS服务器
    QUERY_SERVER=$(echo "$DIG_RESULT" | grep "SERVER:" | awk '{print $2}' | tr -d '#')
    echo "    查询服务器: ${QUERY_SERVER}"

    # 阈值判断: > 500ms 红色, > 100ms 黄色
    if [ "$QUERY_TIME" -gt 500 ]; then
        print_fail "DNS解析时间过长 (${QUERY_TIME}ms)，严重影响应用性能"
        print_info "建议: 检查DNS服务器响应速度，考虑更换DNS或启用本地缓存"
    elif [ "$QUERY_TIME" -gt 100 ]; then
        print_warn "DNS解析时间偏长 (${QUERY_TIME}ms)"
        print_info "建议: 考虑使用更快的DNS服务器或部署本地DNS缓存(如dnsmasq)"
    else
        print_ok "DNS解析时间正常 (${QUERY_TIME}ms)"
    fi

    # 检查DNS响应状态
    DNS_STATUS=$(echo "$DIG_RESULT" | grep "STATUS:" | awk '{print $2}')
    if [ "$DNS_STATUS" != "NOERROR" ]; then
        print_fail "DNS查询异常! 状态码: ${DNS_STATUS}"
    else
        print_ok "DNS查询状态正常 (NOERROR)"
    fi
else
    print_warn "dig命令不可用，请安装: yum install -y bind-utils 或 apt install -y dnsutils"
fi

echo ""

# ======================== 2. DNS解析路径追踪 ========================
print_info ">>> [2/4] 追踪DNS解析路径 ..."

if command -v dig &>/dev/null; then
    print_info "执行dig +trace（可能需要较长时间）..."
    TRACE_RESULT=$(dig +trace "$DOMAIN" 2>&1 | tail -20)

    echo "    解析链路(最后20行):"
    echo "$TRACE_RESULT" | while read line; do
        echo "    $line"
    done

    # 检查是否从根服务器开始解析
    ROOT_QUERY=$(dig +trace "$DOMAIN" 2>&1 | grep -c "\. \.")
    if [ "$ROOT_QUERY" -gt 0 ]; then
        print_ok "DNS解析从根服务器开始，递归解析正常"
    fi
else
    print_warn "dig不可用，跳过解析路径追踪"
fi

echo ""

# ======================== 3. resolv.conf检查 ========================
print_info ">>> [3/4] 检查DNS客户端配置 ..."

RESOLV_FILE="/etc/resolv.conf"
if [ -f "$RESOLV_FILE" ]; then
    echo "    ${RESOLV_FILE} 内容:"
    echo "    ------------------------------------------------------------------"
    while read line; do
        # 跳过注释和空行
        if [[ ! "$line" =~ ^# ]] && [ -n "$line" ]; then
            echo "    $line"
        fi
    done < "$RESOLV_FILE"
    echo "    ------------------------------------------------------------------"

    # 检查nameserver配置
    NAMESERVER_COUNT=$(grep -c "^nameserver" "$RESOLV_FILE" 2>/dev/null)
    echo ""
    echo "    配置的DNS服务器数量: ${NAMESERVER_COUNT}"

    if [ "$NAMESERVER_COUNT" -eq 0 ]; then
        print_fail "未配置任何DNS服务器!"
    elif [ "$NAMESERVER_COUNT" -eq 1 ]; then
        print_warn "仅配置了1个DNS服务器，建议至少配置2个作为备份"
    else
        print_ok "配置了${NAMESERVER_COUNT}个DNS服务器"
    fi

    # 检查search和options
    SEARCH_DOMAIN=$(grep "^search" "$RESOLV_FILE" 2>/dev/null)
    if [ -n "$SEARCH_DOMAIN" ]; then
        echo "    搜索域: $SEARCH_DOMAIN"
    fi

    OPTIONS=$(grep "^options" "$RESOLV_FILE" 2>/dev/null)
    if [ -n "$OPTIONS" ]; then
        echo "    选项: $OPTIONS"
    fi

    # 检查ndots配置
    NDOTS=$(grep "^options" "$RESOLV_FILE" 2>/dev/null | grep -o "ndots:[0-9]*" | cut -d: -f2)
    NDOTS=${NDOTS:-5}
    if [ "$NDOTS" -gt 5 ]; then
        print_warn "ndots=${NDOTS}偏大，可能导致过多DNS查询"
        print_info "建议: 对于纯外部域名访问，设置ndots:2减少不必要的查询"
    fi
else
    print_warn "未找到 ${RESOLV_FILE}"
fi

echo ""

# ======================== 4. 对比多个DNS服务器 ========================
print_info ">>> [4/4] 对比多个DNS服务器解析速度 ..."

echo "    DNS服务器解析速度对比:"
echo "    ------------------------------------------------------------------"
printf "    %-25s %-15s %-15s %s\n" "DNS服务器" "解析时间" "解析结果" "状态"
echo "    ------------------------------------------------------------------"

for dns_entry in "${DNS_SERVERS[@]}"; do
    DNS_IP=$(echo "$dns_entry" | cut -d: -f1)
    DNS_NAME=$(echo "$dns_entry" | cut -d: -f2)

    if command -v dig &>/dev/null; then
        DNS_RESULT=$(dig @"$DNS_IP" +stats +time=2 +tries=1 "$DOMAIN" 2>&1)
        DNS_TIME=$(echo "$DNS_RESULT" | grep "Query time" | awk '{print $4}')
        DNS_IP_RESULT=$(echo "$DNS_RESULT" | grep -A1 "ANSWER SECTION" | tail -1 | awk '{print $NF}')
        DNS_STATUS=$(echo "$DNS_RESULT" | grep "STATUS:" | awk '{print $2}')

        DNS_TIME=${DNS_TIME:-"timeout"}
        DNS_IP_RESULT=${DNS_IP_RESULT:-"N/A"}

        # 状态判断
        if [ "$DNS_STATUS" != "NOERROR" ]; then
            STATUS="${RED}FAIL${NC}"
        elif [ "$DNS_TIME" = "timeout" ]; then
            STATUS="${RED}TIMEOUT${NC}"
        elif [ "${DNS_TIME:-0}" -gt 500 ]; then
            STATUS="${RED}SLOW${NC}"
        elif [ "${DNS_TIME:-0}" -gt 100 ]; then
            STATUS="${YELLOW}WARN${NC}"
        else
            STATUS="${GREEN}OK${NC}"
        fi

        printf "    %-25s %-15s %-15s " "$DNS_NAME" "${DNS_TIME}ms" "$DNS_IP_RESULT"
        echo -e "$STATUS"
    fi
done
echo "    ------------------------------------------------------------------"

echo ""
echo "============================================================"
echo "                     诊断结论"
echo "============================================================"

ISSUE_COUNT=0

if [ "${QUERY_TIME:-0}" -gt 500 ]; then
    echo -e "  ${RED}[严重]${NC} DNS解析时间过长(${QUERY_TIME}ms)，严重影响应用性能"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
elif [ "${QUERY_TIME:-0}" -gt 100 ]; then
    echo -e "  ${YELLOW}[警告]${NC} DNS解析时间偏长(${QUERY_TIME}ms)，建议优化"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$NAMESERVER_COUNT" -le 1 ]; then
    echo -e "  ${YELLOW}[警告]${NC} DNS服务器配置不足，建议配置多个备份DNS"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$ISSUE_COUNT" -eq 0 ]; then
    echo -e "  ${GREEN}[正常]${NC} DNS解析状态健康"
fi

echo ""
echo "    优化建议:"
echo "    1. 使用本地DNS缓存(dnsmasq/unbound)减少外部查询"
echo "    2. 应用内使用DNS缓存库(如dnsjava、go-resolver)"
echo "    3. 合理设置ndots参数减少不必要的域名补全查询"
echo "    4. 对高频域名配置本地hosts解析"
echo "============================================================"
