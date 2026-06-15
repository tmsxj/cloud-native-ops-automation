#!/bin/bash
# ============================================================================
# 模块34-版本发布脚本
# 脚本名称: deploy-rollback.sh
# 功能: K8S一键回滚，支持回滚到指定版本或上一版本
# 用法: ./deploy-rollback.sh <deployment> <namespace> [revision]
# 示例: ./deploy-rollback.sh myapp default          # 回滚到上一版本
#        ./deploy-rollback.sh myapp default 2        # 回滚到revision 2
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
DEPLOY_NAME="${1:-}"
NAMESPACE="${2:-default}"
REVISION="${3:-}"

if [ -z "$DEPLOY_NAME" ]; then
    print_fail "用法: $0 <deployment> <namespace> [revision]"
    print_info "示例: $0 myapp default          # 回滚到上一版本"
    print_info "       $0 myapp default 2        # 回滚到revision 2"
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
print_info "K8S 一键回滚"
print_info "Deployment: ${DEPLOY_NAME}  |  Namespace: ${NAMESPACE}"
print_info "回滚时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

# ======================== 1. 回滚前检查 ========================
print_info ""
print_info ">>> [步骤1] 回滚前状态检查..."
print_separator

# 检查Deployment是否存在
DEPLOY_CHECK=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" --no-headers 2>/dev/null)
if [ -z "$DEPLOY_CHECK" ]; then
    print_fail "Deployment ${DEPLOY_NAME} 不存在于命名空间 ${NAMESPACE}"
    exit 1
fi
print_ok "Deployment ${DEPLOY_NAME} 存在"

# 记录当前状态
CURRENT_IMAGE=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
CURRENT_REPLICAS=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null)
CURRENT_READY=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
CURRENT_REVISION=$(kubectl rollout history deployment/"$DEPLOY_NAME" -n "$NAMESPACE" 2>/dev/null | tail -1 | awk '{print $1}' | tr -d '#')

print_info "当前镜像: ${CURRENT_IMAGE}"
print_info "当前副本: ${CURRENT_READY}/${CURRENT_REPLICAS}"
print_info "当前版本: revision #${CURRENT_REVISION}"

# 检查当前Pod健康状态
UNHEALTHY_PODS=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOY_NAME" --no-headers 2>/dev/null | grep -c "CrashLoop\|Error\|OOMKilled\|Pending" || true)
if [ "$UNHEALTHY_PODS" -gt 0 ]; then
    print_warn "当前有 ${UNHEALTHY_PODS} 个异常Pod，回滚是正确操作"
    ((WARN_COUNT++))
else
    print_info "当前Pod状态正常，请确认是否需要回滚"
fi

# ======================== 2. 查看发布历史 ========================
print_info ""
print_info ">>> [步骤2] 查看发布历史..."
print_separator

HISTORY=$(kubectl rollout history deployment/"$DEPLOY_NAME" -n "$NAMESPACE" 2>/dev/null)
if [ -z "$HISTORY" ]; then
    print_fail "无法获取发布历史，请确认Deployment是否有--record记录"
    ((FAIL_COUNT++))
else
    print_info "发布历史:"
    echo "$HISTORY" | tail -10 | while read -r line; do
        print_info "  $line"
    done
    ((OK_COUNT++))
fi

# ======================== 3. 执行回滚 ========================
print_info ""
print_info ">>> [步骤3] 执行回滚..."
print_separator

ROLLBACK_START=$(date +%s)

if [ -n "$REVISION" ]; then
    print_info "回滚到指定版本: revision #${REVISION}"
    kubectl rollout undo deployment/"$DEPLOY_NAME" -n "$NAMESPACE" --to-revision="$REVISION" 2>&1
else
    print_info "回滚到上一版本"
    kubectl rollout undo deployment/"$DEPLOY_NAME" -n "$NAMESPACE" 2>&1
fi

if [ $? -ne 0 ]; then
    print_fail "回滚执行失败！"
    ((FAIL_COUNT++))
    print_separator
    exit 1
fi
print_ok "回滚指令已下发"
((OK_COUNT++))

# ======================== 4. 等待回滚完成 ========================
print_info ""
print_info ">>> [步骤4] 等待回滚完成..."
print_separator

TIMEOUT=300
ELAPSED=0

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    ROLLOUT_STATUS=$(kubectl rollout status deployment/"$DEPLOY_NAME" -n "$NAMESPACE" --timeout=10s 2>&1)
    ROLLOUT_EXIT=$?

    if [ "$ROLLOUT_EXIT" -eq 0 ]; then
        print_ok "回滚完成"
        ((OK_COUNT++))
        break
    fi

    ROLLBACK_READY=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    print_info "回滚中... 就绪: ${ROLLBACK_READY:-0}/${CURRENT_REPLICAS} (${ELAPSED}s)"
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

ROLLBACK_END=$(date +%s)
ROLLBACK_DURATION=$((ROLLBACK_END - ROLLBACK_START))

if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    print_fail "回滚超时 (${TIMEOUT}s)，请手动检查"
    ((FAIL_COUNT++))
fi

# ======================== 5. 回滚后验证 ========================
print_info ""
print_info ">>> [步骤5] 回滚后验证..."
print_separator

# 检查回滚后镜像
NEW_IMAGE=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
if [ "$NEW_IMAGE" != "$CURRENT_IMAGE" ]; then
    print_ok "镜像已变更: ${CURRENT_IMAGE} -> ${NEW_IMAGE}"
    ((OK_COUNT++))
else
    print_warn "镜像未变更，可能回滚到了相同版本"
    ((WARN_COUNT++))
fi

# 检查Pod就绪
FINAL_READY=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
if [ "$FINAL_READY" = "$CURRENT_REPLICAS" ]; then
    print_ok "所有Pod就绪 (${FINAL_READY}/${CURRENT_REPLICAS})"
    ((OK_COUNT++))
else
    print_fail "Pod就绪数异常 (${FINAL_READY}/${CURRENT_REPLICAS})"
    ((FAIL_COUNT++))
fi

# 检查异常Pod
FINAL_UNHEALTHY=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOY_NAME" --no-headers 2>/dev/null | grep -c "CrashLoop\|Error\|OOMKilled" || true)
if [ "$FINAL_UNHEALTHY" -gt 0 ]; then
    print_fail "仍有 ${FINAL_UNHEALTHY} 个异常Pod，回滚后问题未解决"
    ((FAIL_COUNT++))
else
    print_ok "无异常Pod"
    ((OK_COUNT++))
fi

# ======================== 回滚总结 ========================
echo ""
print_separator
echo ""
echo "==================== 回滚总结 ===================="
echo ""

TOTAL_CHECKS=$((OK_COUNT + WARN_COUNT + FAIL_COUNT))

echo -e "总检查项: ${TOTAL_CHECKS}  |  ${GREEN}正常: ${OK_COUNT}${NC}  |  ${YELLOW}警告: ${WARN_COUNT}${NC}  |  ${RED}异常: ${FAIL_COUNT}${NC}"
echo ""
print_info "回滚前镜像: ${CURRENT_IMAGE}"
print_info "回滚后镜像: ${NEW_IMAGE}"
print_info "回滚耗时: ${ROLLBACK_DURATION}秒"

if [ "$FAIL_COUNT" -gt 0 ]; then
    print_fail "结论: 回滚完成但存在异常，请进一步排查"
    print_info "建议: 1.检查Pod日志 2.检查镜像是否可用 3.确认配置是否正确"
elif [ "$WARN_COUNT" -gt 0 ]; then
    print_warn "结论: 回滚完成，存在警告项需关注"
else
    print_ok "结论: 回滚成功，服务已恢复正常"
fi

echo ""
print_separator
