#!/bin/bash
# ============================================================================
# 模块32-网络协议深度解析脚本
# 脚本名称: check-tls.sh
# 功能: TLS配置与性能分析
# 用法: ./check-tls.sh [host] [port]
# 说明: 检查TLS握手时间、证书有效期、支持的协议和HTTP/2支持
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
TARGET_HOST=${1:-"www.baidu.com"}
TARGET_PORT=${2:-"443"}

print_info "目标: ${TARGET_HOST}:${TARGET_PORT}"

echo "============================================================"
echo "          TLS配置与性能分析报告"
echo "          检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ======================== 1. TLS握手时间检查 ========================
print_info ">>> [1/4] TLS握手时间测试 ..."

if command -v curl &>/dev/null; then
    # 使用curl测量TLS握手时间
    TLS_TIMING=$(curl -o /dev/null -s -w "DNS: %{time_namelookup}s\nTCP: %{time_connect}s\nTLS: %{time_appconnect}s\nTotal: %{time_total}s\n" \
        --connect-timeout 10 \
        "https://${TARGET_HOST}:${TARGET_PORT}/" 2>&1)

    TLS_TIME=$(echo "$TLS_TIMING" | grep "^TLS:" | awk '{print $2}' | tr -d 's')
    TCP_TIME=$(echo "$TLS_TIMING" | grep "^TCP:" | awk '{print $2}' | tr -d 's')
    DNS_TIME=$(echo "$TLS_TIMING" | grep "^DNS:" | awk '{print $2}' | tr -d 's')
    TOTAL_TIME=$(echo "$TLS_TIMING" | grep "^Total:" | awk '{print $2}' | tr -d 's')

    echo "    DNS解析: ${DNS_TIME}s"
    echo "    TCP连接: ${TCP_TIME}s"
    echo "    TLS握手: ${TLS_TIME}s"
    echo "    总耗时: ${TOTAL_TIME}s"

    # TLS握手时间判断（单位: 秒，转换为毫秒比较）
    TLS_MS=$(echo "$TLS_TIME" | awk '{printf "%.0f", $1 * 1000}')

    if [ "$TLS_MS" -gt 500 ]; then
        print_fail "TLS握手时间过长 (${TLS_MS}ms)，可能影响HTTPS性能"
        print_info "建议: 检查证书链长度、OCSP响应和TLS会话复用"
    elif [ "$TLS_MS" -gt 200 ]; then
        print_warn "TLS握手时间偏长 (${TLS_MS}ms)"
    else
        print_ok "TLS握手时间正常 (${TLS_MS}ms)"
    fi
else
    print_warn "curl命令不可用，跳过TLS握手时间测试"
fi

echo ""

# ======================== 2. 证书有效期检查 ========================
print_info ">>> [2/4] 检查TLS证书有效期 ..."

if command -v openssl &>/dev/null; then
    CERT_INFO=$(echo | openssl s_client -servername "$TARGET_HOST" -connect "${TARGET_HOST}:${TARGET_PORT}" 2>/dev/null)

    if [ -n "$CERT_INFO" ]; then
        # 提取证书信息
        CERT_SUBJECT=$(echo "$CERT_INFO" | grep "subject=" | head -1 | sed 's/subject=//')
        CERT_ISSUER=$(echo "$CERT_INFO" | grep "issuer=" | head -1 | sed 's/issuer=//')
        CERT_DATES=$(echo "$CERT_INFO" | grep -E "notBefore|notAfter")

        NOT_BEFORE=$(echo "$CERT_DATES" | grep "notBefore" | sed 's/.*notBefore=//')
        NOT_AFTER=$(echo "$CERT_DATES" | grep "notAfter" | sed 's/.*notAfter=//')

        echo "    主题: ${CERT_SUBJECT}"
        echo "    颁发者: ${CERT_ISSUER}"
        echo "    生效时间: ${NOT_BEFORE}"
        echo "    过期时间: ${NOT_AFTER}"

        # 计算证书剩余天数
        EXPIRY_EPOCH=$(echo "$CERT_INFO" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
        if [ -n "$EXPIRY_EPOCH" ]; then
            # 转换日期格式
            if date --version 2>/dev/null | grep -q GNU; then
                EXPIRY_SEC=$(date -d "$EXPIRY_EPOCH" +%s 2>/dev/null)
                NOW_SEC=$(date +%s)
                REMAIN_DAYS=$(( (EXPIRY_SEC - NOW_SEC) / 86400 ))
            else
                # macOS兼容
                EXPIRY_SEC=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$EXPIRY_EPOCH" +%s 2>/dev/null)
                NOW_SEC=$(date +%s)
                REMAIN_DAYS=$(( (EXPIRY_SEC - NOW_SEC) / 86400 ))
            fi

            echo "    剩余天数: ${REMAIN_DAYS}天"

            if [ "$REMAIN_DAYS" -lt 0 ]; then
                print_fail "证书已过期! 过期${REMAIN_DAYS}天"
            elif [ "$REMAIN_DAYS" -lt 7 ]; then
                print_fail "证书即将过期! 仅剩${REMAIN_DAYS}天，请立即续签"
            elif [ "$REMAIN_DAYS" -lt 30 ]; then
                print_warn "证书即将过期，剩余${REMAIN_DAYS}天，建议尽快续签"
            else
                print_ok "证书有效期充足 (剩余${REMAIN_DAYS}天)"
            fi
        fi

        # 检查证书协议版本
        PROTOCOL=$(echo "$CERT_INFO" | grep "Protocol" | awk '{print $3}')
        echo "    协议版本: ${PROTOCOL}"
        if [ "$PROTOCOL" = "TLSv1.2" ]; then
            print_ok "使用TLS 1.2协议"
        elif [ "$PROTOCOL" = "TLSv1.3" ]; then
            print_ok "使用TLS 1.3协议（推荐）"
        elif [ "$PROTOCOL" = "TLSv1" ] || [ "$PROTOCOL" = "TLSv1.1" ]; then
            print_fail "使用不安全的协议 ${PROTOCOL}，建议升级到TLS 1.2+"
        else
            print_info "协议版本: ${PROTOCOL}"
        fi
    else
        print_fail "无法获取证书信息，请检查主机和端口是否正确"
    fi
else
    print_warn "openssl命令不可用，跳过证书检查"
fi

echo ""

# ======================== 3. 支持的协议和密码套件检查 ========================
print_info ">>> [3/4] 检查支持的TLS协议和密码套件 ..."

if command -v nmap &>/dev/null; then
    # 使用nmap的ssl-enum-ciphers脚本
    print_info "使用nmap扫描支持的协议和密码套件（可能需要较长时间）..."
    NMAP_RESULT=$(nmap --script ssl-enum-ciphers -p "$TARGET_PORT" "$TARGET_HOST" 2>/dev/null | grep -E "TLSv|SSLv|least strength")

    if [ -n "$NMAP_RESULT" ]; then
        echo "    支持的协议和密码强度:"
        echo "$NMAP_RESULT" | while read line; do
            echo "    $line"
        done

        # 检查是否支持不安全的协议
        WEAK_PROTOCOLS=$(echo "$NMAP_RESULT" | grep -iE "SSLv2|SSLv3|TLSv1\.0|TLSv1\.1")
        if [ -n "$WEAK_PROTOCOLS" ]; then
            print_fail "支持不安全的协议版本:"
            echo "$WEAK_PROTOCOLS" | while read line; do
                echo "    $line"
            done
            print_info "建议: 在服务器配置中禁用SSLv2/SSLv3/TLSv1.0/TLSv1.1"
        fi

        # 检查密码强度
        WEAK_CIPHERS=$(echo "$NMAP_RESULT" | grep -i "weak")
        if [ -n "$WEAK_CIPHERS" ]; then
            print_warn "存在弱密码套件，建议升级"
        fi
    else
        print_warn "nmap扫描未返回结果，可能需要root权限"
    fi
else
    print_info "nmap不可用，使用openssl替代检查"
    # 使用openssl检查支持的协议
    for proto in tls1 tls1_1 tls1_2 tls1_3; do
        result=$(echo | openssl s_client -servername "$TARGET_HOST" -connect "${TARGET_HOST}:${TARGET_PORT}" -"$proto" 2>&1 | head -1)
        if echo "$result" | grep -q "CONNECTED"; then
            echo "    支持: ${proto}"
        else
            echo "    不支持: ${proto}"
        fi
    done
fi

echo ""

# ======================== 4. HTTP/2检查 ========================
print_info ">>> [4/4] 检查HTTP/2支持 ..."

if command -v curl &>/dev/null; then
    HTTP2_HEADER=$(curl -sI --http2 -o /dev/null -w '%{http_version}' "https://${TARGET_HOST}:${TARGET_PORT}/" 2>/dev/null)

    if [ "$HTTP2_HEADER" = "2" ]; then
        print_ok "服务器支持HTTP/2"
    elif [ "$HTTP2_HEADER" = "1.1" ]; then
        print_warn "服务器不支持HTTP/2，仅支持HTTP/1.1"
        print_info "建议: 启用HTTP/2以提升多路复用性能"
    else
        print_info "HTTP版本: ${HTTP2_HEADER}"
    fi

    # 检查HSTS
    HSTS_HEADER=$(curl -sI "https://${TARGET_HOST}:${TARGET_PORT}/" 2>/dev/null | grep -i "strict-transport-security")
    if [ -n "$HSTS_HEADER" ]; then
        print_ok "已启用HSTS: $HSTS_HEADER"
    else
        print_warn "未启用HSTS，建议添加Strict-Transport-Security头"
    fi
else
    print_warn "curl不可用，跳过HTTP/2检查"
fi

echo ""
echo "============================================================"
echo "                     诊断结论"
echo "============================================================"

ISSUE_COUNT=0

if [ "${TLS_MS:-0}" -gt 200 ]; then
    echo -e "  ${YELLOW}[警告]${NC} TLS握手时间偏长(${TLS_MS}ms)，影响HTTPS性能"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "${REMAIN_DAYS:-999}" -lt 30 ]; then
    echo -e "  ${RED}[严重]${NC} 证书即将过期(剩余${REMAIN_DAYS}天)，请尽快续签"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$ISSUE_COUNT" -eq 0 ]; then
    echo -e "  ${GREEN}[正常]${NC} TLS配置正常，证书有效"
fi

echo "============================================================"
