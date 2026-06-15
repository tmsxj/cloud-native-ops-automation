#!/bin/bash
# ============================================================================
# 模块35-告警处理脚本
# 脚本名称: alert-triage.sh
# 功能: 告警分级处理，根据告警内容自动判断P0/P1/P2级别并给出处理流程
# 用法: ./alert-triage.sh <alert-message> [alert-source]
# 示例: ./alert-triage.sh "MySQL连接数超过90%" "Prometheus"
#        echo "告警内容" | ./alert-triage.sh
# ============================================================================

# ======================== 颜色输出函数定义 ========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_info() { echo -e "[INFO] $1"; }
print_p0()   { echo -e "${RED}[P0-紧急]${NC} $1"; }
print_p1()   { echo -e "${YELLOW}[P1-重要]${NC} $1"; }
print_p2()   { echo -e "${BLUE}[P2-一般]${NC} $1"; }

# ======================== 参数解析 ========================
ALERT_MSG="${1:-}"
ALERT_SOURCE="${2:-unknown}"

# 支持管道输入
if [ -z "$ALERT_MSG" ] && [ ! -t 0 ]; then
    ALERT_MSG=$(cat)
fi

if [ -z "$ALERT_MSG" ]; then
    print_fail "用法: $0 <alert-message> [alert-source]"
    print_info "示例: $0 \"MySQL连接数超过90%\" Prometheus"
    print_info "       echo \"告警内容\" | $0"
    exit 1
fi

# ======================== 统计变量 ========================
FAIL_COUNT=0
WARN_COUNT=0
OK_COUNT=0

# ======================== 分隔线 ========================
print_separator() {
    echo "============================================================"
}

echo "============================================================"
print_info "告警分级处理"
print_info "告警来源: ${ALERT_SOURCE}"
print_info "告警时间: $(date '+%Y-%m-%d %H:%M:%S')"
print_info "告警内容: ${ALERT_MSG}"
echo "============================================================"

# ======================== 1. 告警分级 ========================
print_info ""
print_info ">>> [步骤1] 告警分级判定..."
print_separator

ALERT_LEVEL=""
ALERT_REASON=""

# P0判定规则: 核心服务完全不可用、数据丢失风险、安全事件
if echo "$ALERT_MSG" | grep -qiE "down|unreachable|critical|emergency|数据丢失|宕机|全站不可用|服务熔断|OOM Kill|磁盘满|证书过期"; then
    ALERT_LEVEL="P0"
    ALERT_REASON="核心服务不可用/数据风险/安全事件"
    print_p0 "告警级别: P0 (紧急) - ${ALERT_REASON}"
    ((FAIL_COUNT++))
# P1判定规则: 性能严重下降、部分功能不可用、资源即将耗尽
elif echo "$ALERT_MSG" | grep -qiE "warning|high|degraded|慢查询|连接数超过|CPU超过|内存超过|磁盘使用率|Pod重启|CrashLoop|延迟|超时|timeout|502|503|500"; then
    ALERT_LEVEL="P1"
    ALERT_REASON="性能下降/部分功能异常/资源告警"
    print_p1 "告警级别: P1 (重要) - ${ALERT_REASON}"
    ((WARN_COUNT++))
# P2判定规则: 一般性告警、预警信息、非核心服务异常
else
    ALERT_LEVEL="P2"
    ALERT_REASON="一般性告警/预警信息"
    print_p2 "告警级别: P2 (一般) - ${ALERT_REASON}"
    ((OK_COUNT++))
fi

# ======================== 2. 告警分类 ========================
print_info ""
print_info ">>> [步骤2] 告警分类..."
print_separator

ALERT_CATEGORY=""

if echo "$ALERT_MSG" | grep -qiE "CPU|内存|磁盘|负载|load|memory|disk"; then
    ALERT_CATEGORY="资源类"
    print_info "告警分类: 资源类 (CPU/内存/磁盘)"
elif echo "$ALERT_MSG" | grep -qiE "MySQL|Redis|Kafka|Elasticsearch|Nginx|数据库|缓存|消息队列"; then
    ALERT_CATEGORY="中间件类"
    print_info "告警分类: 中间件类 (数据库/缓存/MQ)"
elif echo "$ALERT_MSG" | grep -qiE "Pod|Deployment|Service|Ingress|Node|K8S|Kubernetes|容器"; then
    ALERT_CATEGORY="K8S类"
    print_info "告警分类: K8S类 (Pod/Service/Node)"
elif echo "$ALERT_MSG" | grep -qiE "网络|DNS|TCP|TLS|证书|certificate|ping|丢包"; then
    ALERT_CATEGORY="网络类"
    print_info "告警分类: 网络类 (DNS/TCP/TLS/证书)"
elif echo "$ALERT_MSG" | grep -qiE "安全|漏洞|攻击|入侵|DDoS|防火墙|firewall| brute|inject"; then
    ALERT_CATEGORY="安全类"
    print_info "告警分类: 安全类 (漏洞/攻击/入侵)"
else
    ALERT_CATEGORY="其他"
    print_info "告警分类: 其他"
fi

# ======================== 3. 处理流程 ========================
print_info ""
print_info ">>> [步骤3] 处理流程..."
print_separator

case "$ALERT_LEVEL" in
    P0)
        print_p0 "【P0处理流程 - 紧急】"
        print_info "  1. 立即确认: 判断是否为真告警(排除误报)"
        print_info "  2. 立即止血: 执行紧急操作(重启/回滚/扩容/降级)"
        print_info "  3. 通知升级: 电话通知技术负责人+项目经理"
        print_info "  4. 持续监控: 每5分钟确认一次恢复状态"
        print_info "  5. 事后复盘: 24小时内完成复盘报告"
        echo ""
        print_info "  响应时间要求: < 5分钟"
        print_info "  恢复时间要求: < 30分钟"
        ;;
    P1)
        print_p1 "【P1处理流程 - 重要】"
        print_info "  1. 确认告警: 查看监控面板，确认影响范围"
        print_info "  2. 初步排查: 根据告警分类执行对应排查脚本"
        print_info "  3. 止血操作: 必要时执行重启/扩容/限流"
        print_info "  4. 通知团队: 群内通知相关人员"
        print_info "  5. 跟踪处理: 持续关注直到恢复"
        echo ""
        print_info "  响应时间要求: < 15分钟"
        print_info "  恢复时间要求: < 2小时"
        ;;
    P2)
        print_p2 "【P2处理流程 - 一般】"
        print_info "  1. 记录告警: 确认告警内容并记录"
        print_info "  2. 评估影响: 判断是否需要立即处理"
        print_info "  3. 排查处理: 在工作时间内处理"
        print_info "  4. 更新状态: 处理后更新告警状态"
        echo ""
        print_info "  响应时间要求: < 4小时"
        print_info "  恢复时间要求: < 24小时"
        ;;
esac

# ======================== 4. 推荐排查脚本 ========================
print_info ""
print_info ">>> [步骤4] 推荐排查脚本..."
print_separator

case "$ALERT_CATEGORY" in
    资源类)
        print_info "  ./31-linux/check-cpu.sh"
        print_info "  ./31-linux/check-memory.sh"
        print_info "  ./31-linux/check-diskio.sh"
        ;;
    中间件类)
        if echo "$ALERT_MSG" | grep -qi "mysql"; then
            print_info "  ./30-middleware/check-mysql.sh"
        fi
        if echo "$ALERT_MSG" | grep -qi "redis"; then
            print_info "  ./30-middleware/check-redis.sh"
        fi
        if echo "$ALERT_MSG" | grep -qi "kafka"; then
            print_info "  ./30-middleware/check-kafka.sh"
        fi
        if echo "$ALERT_MSG" | grep -qi "nginx"; then
            print_info "  ./30-middleware/check-nginx.sh"
        fi
        if echo "$ALERT_MSG" | grep -qi "elasticsearch\|es"; then
            print_info "  ./30-middleware/check-elasticsearch.sh"
        fi
        ;;
    K8S类)
        print_info "  ./29-k8s/check-pod-pending.sh"
        print_info "  ./29-k8s/check-pod-restart.sh"
        print_info "  ./29-k8s/check-node-health.sh"
        print_info "  ./29-k8s/check-service-timeout.sh"
        ;;
    网络类)
        print_info "  ./32-network/check-dns.sh"
        print_info "  ./32-network/check-network-latency.sh"
        print_info "  ./32-network/check-tcp-conn.sh"
        print_info "  ./32-network/check-tls.sh"
        ;;
    安全类)
        print_info "  ./32-network/check-tcp-conn.sh  (检查异常连接)"
        print_info "  ./32-network/check-tls.sh  (检查证书状态)"
        ;;
    *)
        print_info "  按需选择对应模块排查脚本"
        ;;
esac

# ======================== 5. 告警记录 ========================
print_info ""
print_info ">>> [步骤5] 生成告警记录..."
print_separator

ALERT_ID=$(date '+%Y%m%d%H%M%S')
ALERT_LOG="/tmp/alert-triage-${ALERT_ID}.log"

cat > "$ALERT_LOG" <<EOF
告警ID: ${ALERT_ID}
告警时间: $(date '+%Y-%m-%d %H:%M:%S')
告警来源: ${ALERT_SOURCE}
告警级别: ${ALERT_LEVEL}
告警分类: ${ALERT_CATEGORY}
告警内容: ${ALERT_MSG}
处理状态: 待处理
EOF

if [ -f "$ALERT_LOG" ]; then
    print_ok "告警记录已保存: ${ALERT_LOG}"
    ((OK_COUNT++))
else
    print_warn "告警记录保存失败"
    ((WARN_COUNT++))
fi

# ======================== 处理总结 ========================
echo ""
print_separator
echo ""
echo "==================== 告警分级总结 ===================="
echo ""

TOTAL_CHECKS=$((OK_COUNT + WARN_COUNT + FAIL_COUNT))

echo -e "总检查项: ${TOTAL_CHECKS}  |  ${GREEN}正常: ${OK_COUNT}${NC}  |  ${YELLOW}警告: ${WARN_COUNT}${NC}  |  ${RED}异常: ${FAIL_COUNT}${NC}"
echo ""
print_info "告警级别: ${ALERT_LEVEL}"
print_info "告警分类: ${ALERT_CATEGORY}"
print_info "告警记录: ${ALERT_LOG}"

if [ "$ALERT_LEVEL" = "P0" ]; then
    print_p0 "结论: P0紧急告警，请立即响应！"
elif [ "$ALERT_LEVEL" = "P1" ]; then
    print_p1 "结论: P1重要告警，请在15分钟内响应"
else
    print_p2 "结论: P2一般告警，请在4小时内处理"
fi

echo ""
print_separator
