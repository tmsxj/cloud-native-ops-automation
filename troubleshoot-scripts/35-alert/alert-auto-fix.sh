#!/bin/bash
# ============================================================================
# 模块35-告警处理脚本
# 脚本名称: alert-auto-fix.sh
# 功能: 自动止血操作，根据告警类型执行预设的恢复策略
# 用法: ./alert-auto-fix.sh <alert-type> [namespace] [target]
# 示例: ./alert-auto-fix.sh pod-restart default myapp
#        ./alert-auto-fix.sh disk-clean /data 80
#        ./alert-auto-fix.sh svc-restart default mysql
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

# ======================== 参数解析 ========================
ALERT_TYPE="${1:-}"
PARAM1="${2:-}"
PARAM2="${3:-}"

if [ -z "$ALERT_TYPE" ]; then
    print_fail "用法: $0 <alert-type> [param1] [param2]"
    print_info ""
    print_info "支持的告警类型:"
    print_info "  pod-restart   - 重启异常Pod (参数: namespace deployment)"
    print_info "  disk-clean    - 清理磁盘空间 (参数: 目录 清理阈值%)"
    print_info "  svc-restart   - 重启K8S Service关联Pod (参数: namespace deployment)"
    print_info "  conn-kill     - 清理异常TCP连接 (参数: 端口 最大连接数)"
    print_info "  node-cordon   - 隔离异常节点 (参数: 节点名)"
    print_info "  deploy-scale  - 扩容Deployment (参数: namespace deployment 副本数)"
    print_info ""
    print_info "示例:"
    print_info "  $0 pod-restart default myapp"
    print_info "  $0 disk-clean /data 80"
    print_info "  $0 deploy-scale default myapp 5"
    exit 1
fi

# ======================== 统计变量 ========================
FAIL_COUNT=0
WARN_COUNT=0
OK_COUNT=0
ACTION_COUNT=0

# ======================== 分隔线 ========================
print_separator() {
    echo "============================================================"
}

echo "============================================================"
print_info "告警自动止血"
print_info "告警类型: ${ALERT_TYPE}"
print_info "执行时间: $(date '+%Y-%m-%d %H:%M:%S')"
print_info "操作人: $(whoami)"
echo "============================================================"

# ======================== 通用函数 ========================

# 记录操作日志
log_action() {
    local action="$1"
    local result="$2"
    ACTION_COUNT=$((ACTION_COUNT + 1))
    print_info "操作记录[${ACTION_COUNT}]: ${action} -> ${result}"
}

# ======================== 1. Pod重启止血 ========================
do_pod_restart() {
    local ns="${1:-default}"
    local deploy="${2:-}"

    if [ -z "$deploy" ]; then
        print_fail "缺少deployment名称"
        ((FAIL_COUNT++))
        return
    fi

    print_info ""
    print_info ">>> 执行Pod重启止血..."
    print_separator

    # 检查Deployment是否存在
    if ! kubectl get deployment "$deploy" -n "$ns" --no-headers &>/dev/null; then
        print_fail "Deployment ${deploy} 不存在于命名空间 ${ns}"
        ((FAIL_COUNT++))
        return
    fi

    # 记录当前Pod状态
    BEFORE_REPLICAS=$(kubectl get deployment "$deploy" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    print_info "重启前就绪副本: ${BEFORE_REPLICAS}"

    # 执行滚动重启
    print_info "执行: kubectl rollout restart deployment/${deploy} -n ${ns}"
    kubectl rollout restart deployment/"$deploy" -n "$ns" 2>&1

    if [ $? -eq 0 ]; then
        print_ok "滚动重启指令已下发"
        log_action "restart-deploy" "成功"
        ((OK_COUNT++))
    else
        print_fail "滚动重启失败"
        log_action "restart-deploy" "失败"
        ((FAIL_COUNT++))
        return
    fi

    # 等待重启完成
    print_info "等待Pod重启完成..."
    kubectl rollout status deployment/"$deploy" -n "$ns" --timeout=120s 2>&1
    if [ $? -eq 0 ]; then
        AFTER_REPLICAS=$(kubectl get deployment "$deploy" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
        print_ok "Pod重启完成 (就绪: ${AFTER_REPLICAS})"
        log_action "pod-restart-wait" "成功"
        ((OK_COUNT++))
    else
        print_fail "Pod重启超时"
        log_action "pod-restart-wait" "超时"
        ((FAIL_COUNT++))
    fi
}

# ======================== 2. 磁盘清理止血 ========================
do_disk_clean() {
    local target_dir="${1:-/tmp}"
    local threshold="${2:-80}"

    print_info ""
    print_info ">>> 执行磁盘清理止血..."
    print_separator

    # 检查磁盘使用率
    DISK_USAGE=$(df "$target_dir" | awk 'NR==2{print $5}' | tr -d '%')
    print_info "目标目录: ${target_dir}"
    print_info "当前磁盘使用率: ${DISK_USAGE}%"

    if [ "$DISK_USAGE" -lt "$threshold" ]; then
        print_ok "磁盘使用率(${DISK_USAGE}%)低于阈值(${threshold}%)，无需清理"
        ((OK_COUNT++))
        return
    fi

    print_warn "磁盘使用率(${DISK_USAGE}%)超过阈值(${threshold}%)，开始清理..."

    # 清理1: 删除7天前的旧日志
    OLD_LOGS=$(find "$target_dir" -name "*.log" -mtime +7 -type f 2>/dev/null | wc -l)
    if [ "$OLD_LOGS" -gt 0 ]; then
        print_info "清理7天前旧日志文件: ${OLD_LOGS}个"
        find "$target_dir" -name "*.log" -mtime +7 -type f -delete 2>/dev/null
        log_action "clean-old-logs" "删除${OLD_LOGS}个文件"
        ((OK_COUNT++))
    fi

    # 清理2: 清理Docker无用镜像
    if command -v docker &>/dev/null; then
        DOCKER_SPACE=$(docker system df 2>/dev/null | grep "Images" | awk '{print $NF}')
        print_info "清理Docker无用镜像..."
        docker image prune -f --filter "until=168h" &>/dev/null
        if [ $? -eq 0 ]; then
            print_ok "Docker无用镜像已清理"
            log_action "docker-prune" "成功"
            ((OK_COUNT++))
        fi
    fi

    # 清理3: 清理系统日志
    if command -v journalctl &>/dev/null; then
        print_info "清理系统日志(保留3天)..."
        journalctl --vacuum-time=3d &>/dev/null
        log_action "journal-clean" "成功"
        ((OK_COUNT++))
    fi

    # 清理4: 清理临时文件
    TMP_SIZE=$(du -sh /tmp 2>/dev/null | awk '{print $1}')
    if [ -n "$TMP_SIZE" ]; then
        print_info "清理/tmp目录 (当前大小: ${TMP_SIZE})..."
        find /tmp -type f -atime +3 -delete 2>/dev/null
        log_action "tmp-clean" "成功"
        ((OK_COUNT++))
    fi

    # 检查清理后使用率
    AFTER_USAGE=$(df "$target_dir" | awk 'NR==2{print $5}' | tr -d '%')
    print_info "清理后磁盘使用率: ${AFTER_USAGE}%"
    FREED=$((DISK_USAGE - AFTER_USAGE))
    print_info "释放空间: 约${FREED}%"

    if [ "$AFTER_USAGE" -lt "$threshold" ]; then
        print_ok "磁盘使用率已降至安全范围"
        ((OK_COUNT++))
    else
        print_fail "磁盘使用率仍然偏高(${AFTER_USAGE}%)，需手动清理"
        ((FAIL_COUNT++))
    fi
}

# ======================== 3. 节点隔离止血 ========================
do_node_cordon() {
    local node_name="${1:-}"

    if [ -z "$node_name" ]; then
        print_fail "缺少节点名称"
        ((FAIL_COUNT++))
        return
    fi

    print_info ""
    print_info ">>> 执行节点隔离止血..."
    print_separator

    # 检查节点是否存在
    if ! kubectl get node "$node_name" --no-headers &>/dev/null; then
        print_fail "节点 ${node_name} 不存在"
        ((FAIL_COUNT++))
        return
    fi

    # 检查节点状态
    NODE_STATUS=$(kubectl get node "$node_name" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    print_info "节点状态: ${NODE_STATUS}"

    # 驱逐节点上的Pod
    print_info "驱逐节点上的Pod..."
    kubectl drain "$node_name" --ignore-daemonsets --delete-emptydir-data --grace-period=60 --timeout=120s 2>&1
    if [ $? -eq 0 ]; then
        print_ok "节点Pod驱逐完成"
        log_action "node-drain" "成功"
        ((OK_COUNT++))
    else
        print_fail "节点Pod驱逐失败"
        log_action "node-drain" "失败"
        ((FAIL_COUNT++))
        return
    fi

    # 隔离节点
    kubectl cordon "$node_name" 2>&1
    if [ $? -eq 0 ]; then
        print_ok "节点 ${node_name} 已隔离，不再调度新Pod"
        log_action "node-cordon" "成功"
        ((OK_COUNT++))
    else
        print_fail "节点隔离失败"
        log_action "node-cordon" "失败"
        ((FAIL_COUNT++))
    fi

    print_info "恢复命令: kubectl uncordon ${node_name}"
}

# ======================== 4. Deployment扩容止血 ========================
do_deploy_scale() {
    local ns="${1:-default}"
    local deploy="${2:-}"
    local replicas="${3:-}"

    if [ -z "$deploy" ] || [ -z "$replicas" ]; then
        print_fail "缺少deployment名称或副本数"
        ((FAIL_COUNT++))
        return
    fi

    print_info ""
    print_info ">>> 执行Deployment扩容止血..."
    print_separator

    # 检查Deployment
    if ! kubectl get deployment "$deploy" -n "$ns" --no-headers &>/dev/null; then
        print_fail "Deployment ${deploy} 不存在于命名空间 ${ns}"
        ((FAIL_COUNT++))
        return
    fi

    BEFORE_REPLICAS=$(kubectl get deployment "$deploy" -n "$ns" -o jsonpath='{.spec.replicas}' 2>/dev/null)
    print_info "扩容前副本数: ${BEFORE_REPLICAS}"
    print_info "目标副本数: ${replicas}"

    if [ "$replicas" -le "$BEFORE_REPLICAS" ]; then
        print_warn "目标副本数(${replicas})不大于当前副本数(${BEFORE_REPLICAS})，跳过"
        ((WARN_COUNT++))
        return
    fi

    kubectl scale deployment "$deploy" -n "$ns" --replicas="$replicas" 2>&1
    if [ $? -eq 0 ]; then
        print_ok "扩容指令已下发 (${BEFORE_REPLICAS} -> ${replicas})"
        log_action "deploy-scale" "成功"
        ((OK_COUNT++))

        # 等待扩容完成
        print_info "等待扩容完成..."
        sleep 5
        AFTER_READY=$(kubectl get deployment "$deploy" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
        print_info "当前就绪副本: ${AFTER_READY}/${replicas}"
    else
        print_fail "扩容失败"
        log_action "deploy-scale" "失败"
        ((FAIL_COUNT++))
    fi
}

# ======================== 5. 异常连接清理止血 ========================
do_conn_kill() {
    local port="${1:-}"
    local max_conn="${2:-1000}"

    if [ -z "$port" ]; then
        print_fail "缺少端口号"
        ((FAIL_COUNT++))
        return
    fi

    print_info ""
    print_info ">>> 执行异常连接清理..."
    print_separator

    # 统计连接数
    ESTABLISHED=$(ss -tan | grep ":${port}" | grep -c "ESTAB" || true)
    TIME_WAIT=$(ss -tan | grep ":${port}" | grep -c "TIME-WAIT" || true)
    CLOSE_WAIT=$(ss -tan | grep ":${port}" | grep -c "CLOSE-WAIT" || true)

    print_info "端口 ${port} 连接状态:"
    print_info "  ESTABLISHED: ${ESTABLISHED}"
    print_info "  TIME-WAIT: ${TIME_WAIT}"
    print_info "  CLOSE-WAIT: ${CLOSE_WAIT}"

    if [ "$ESTABLISHED" -lt "$max_conn" ]; then
        print_ok "连接数(${ESTABLISHED})未超过阈值(${max_conn})"
        ((OK_COUNT++))
        return
    fi

    print_warn "连接数(${ESTABLISHED})超过阈值(${max_conn})，执行清理..."

    # 优化内核参数(临时生效)
    print_info "优化内核TCP参数..."
    sysctl -w net.ipv4.tcp_tw_reuse=1 &>/dev/null
    sysctl -w net.ipv4.tcp_fin_timeout=15 &>/dev/null
    log_action "tcp-tune" "已优化tw_reuse和fin_timeout"
    ((OK_COUNT++))

    # 清理CLOSE_WAIT连接
    if [ "$CLOSE_WAIT" -gt 0 ]; then
        print_warn "存在 ${CLOSE_WAIT} 个CLOSE-WAIT连接，建议检查应用代码"
        print_info "CLOSE-WAIT通常表示应用未正确关闭连接"
        ((WARN_COUNT++))
    fi

    AFTER_ESTABLISHED=$(ss -tan | grep ":${port}" | grep -c "ESTAB" || true)
    print_info "处理后连接数: ${AFTER_ESTABLISHED}"
}

# ======================== 执行对应止血操作 ========================
case "$ALERT_TYPE" in
    pod-restart)
        do_pod_restart "$PARAM1" "$PARAM2"
        ;;
    disk-clean)
        do_disk_clean "$PARAM1" "$PARAM2"
        ;;
    node-cordon)
        do_node_cordon "$PARAM1"
        ;;
    deploy-scale)
        do_deploy_scale "$PARAM1" "$PARAM2" "$PARAM3"
        ;;
    conn-kill)
        do_conn_kill "$PARAM1" "$PARAM2"
        ;;
    svc-restart)
        do_pod_restart "$PARAM1" "$PARAM2"
        ;;
    *)
        print_fail "不支持的告警类型: ${ALERT_TYPE}"
        print_info "支持的类型: pod-restart, disk-clean, node-cordon, deploy-scale, conn-kill, svc-restart"
        ((FAIL_COUNT++))
        ;;
esac

# ======================== 止血总结 ========================
echo ""
print_separator
echo ""
echo "==================== 自动止血总结 ===================="
echo ""

TOTAL_CHECKS=$((OK_COUNT + WARN_COUNT + FAIL_COUNT))

echo -e "总检查项: ${TOTAL_CHECKS}  |  ${GREEN}正常: ${OK_COUNT}${NC}  |  ${YELLOW}警告: ${WARN_COUNT}${NC}  |  ${RED}异常: ${FAIL_COUNT}${NC}"
echo ""
print_info "执行操作数: ${ACTION_COUNT}"
print_info "告警类型: ${ALERT_TYPE}"

if [ "$FAIL_COUNT" -gt 0 ]; then
    print_fail "结论: 自动止血存在失败项，请手动介入"
    print_info "建议: 1.检查操作日志 2.手动执行失败操作 3.联系值班人员"
elif [ "$WARN_COUNT" -gt 0 ]; then
    print_warn "结论: 自动止血完成，存在警告项需关注"
else
    print_ok "结论: 自动止血成功，请持续观察服务状态"
fi

echo ""
print_separator
