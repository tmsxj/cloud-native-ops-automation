#!/bin/bash
# ============================================================================
# 模块34-版本发布脚本
# 脚本名称: deploy-rollout.sh
# 功能: K8S滚动更新部署，支持自定义滚动策略与发布验证
# 用法: ./deploy-rollout.sh <deployment> <namespace> <image> [max-surge] [max-unavailable]
# 示例: ./deploy-rollout.sh myapp default myapp:v2.1.0 1 0
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
IMAGE="${3:-}"
MAX_SURGE="${4:-1}"
MAX_UNAVAIL="${5:-0}"

if [ -z "$DEPLOY_NAME" ] || [ -z "$IMAGE" ]; then
    print_fail "用法: $0 <deployment> <namespace> <image> [max-surge] [max-unavailable]"
    print_info "示例: $0 myapp default myapp:v2.1.0 1 0"
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
print_info "K8S 滚动更新部署"
print_info "Deployment: ${DEPLOY_NAME}  |  Namespace: ${NAMESPACE}"
print_info "目标镜像: ${IMAGE}"
print_info "滚动策略: maxSurge=${MAX_SURGE}, maxUnavailable=${MAX_UNAVAIL}"
print_info "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

# ======================== 1. 发布前检查 ========================
print_info ""
print_info ">>> [步骤1] 发布前环境检查..."
print_separator

# 检查kubectl是否可用
if ! command -v kubectl &>/dev/null; then
    print_fail "kubectl 命令不可用，请确认K8S环境"
    exit 1
fi
print_ok "kubectl 命令可用"

# 检查Deployment是否存在
DEPLOY_CHECK=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" --no-headers 2>/dev/null)
if [ -z "$DEPLOY_CHECK" ]; then
    print_fail "Deployment ${DEPLOY_NAME} 不存在于命名空间 ${NAMESPACE}"
    ((FAIL_COUNT++))
    print_separator
    echo ""
    print_fail "发布终止: 目标Deployment不存在"
    exit 1
fi
print_ok "Deployment ${DEPLOY_NAME} 存在"

# 记录当前镜像版本
OLD_IMAGE=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
OLD_REPLICAS=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null)
print_info "当前镜像: ${OLD_IMAGE}"
print_info "当前副本数: ${OLD_REPLICAS}"

# 检查当前Pod状态
CURRENT_READY=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
if [ "$CURRENT_READY" != "$OLD_REPLICAS" ]; then
    print_warn "当前就绪副本数(${CURRENT_READY})不等于期望副本数(${OLD_REPLICAS})，建议等待稳定后再发布"
    ((WARN_COUNT++))
else
    print_ok "所有Pod就绪 (${CURRENT_READY}/${OLD_REPLICAS})"
    ((OK_COUNT++))
fi

# ======================== 2. 执行滚动更新 ========================
print_info ""
print_info ">>> [步骤2] 执行滚动更新..."
print_separator

START_TIME=$(date +%s)

kubectl set image deployment/"$DEPLOY_NAME" -n "$NAMESPACE" \
    "${DEPLOY_NAME}=${IMAGE}" --record=true 2>&1

if [ $? -ne 0 ]; then
    print_fail "滚动更新执行失败！"
    ((FAIL_COUNT++))
    print_separator
    echo ""
    print_fail "发布终止: kubectl set image 失败"
    exit 1
fi
print_ok "滚动更新指令已下发"

# ======================== 3. 监控滚动更新过程 ========================
print_info ""
print_info ">>> [步骤3] 监控滚动更新过程..."
print_separator

TIMEOUT=300
ELAPSED=0
ROLLBACK_NEEDED=false

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    DEPLOY_STATUS=$(kubectl rollout status deployment/"$DEPLOY_NAME" -n "$NAMESPACE" --timeout=10s 2>&1)
    ROLLOUT_EXIT=$?

    if [ "$ROLLOUT_EXIT" -eq 0 ]; then
        print_ok "滚动更新完成"
        ((OK_COUNT++))
        break
    fi

    # 检查是否有Pod异常
    CRASH_PODS=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOY_NAME" --no-headers 2>/dev/null | grep -c "CrashLoop\|Error\|OOMKilled" || true)
    if [ "$CRASH_PODS" -gt 0 ]; then
        print_fail "检测到 ${CRASH_PODS} 个异常Pod (CrashLoop/Error/OOMKilled)"
        ROLLBACK_NEEDED=true
        break
    fi

    # 显示进度
    NEW_READY=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    NEW_UPDATED=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.status.updatedReplicas}' 2>/dev/null)
    print_info "更新中... 已更新: ${NEW_UPDATED}/${OLD_REPLICAS}, 就绪: ${NEW_READY}/${OLD_REPLICAS} (${ELAPSED}s)"

    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    print_fail "滚动更新超时 (${TIMEOUT}s)，可能需要手动干预"
    ROLLBACK_NEEDED=true
    ((FAIL_COUNT++))
fi

# ======================== 4. 发布后验证 ========================
print_info ""
print_info ">>> [步骤4] 发布后健康验证..."
print_separator

# 检查新版本镜像是否生效
NEW_IMAGE=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
if [ "$NEW_IMAGE" = "$IMAGE" ]; then
    print_ok "镜像版本已更新为: ${NEW_IMAGE}"
    ((OK_COUNT++))
else
    print_fail "镜像版本未更新! 当前: ${NEW_IMAGE}, 期望: ${IMAGE}"
    ((FAIL_COUNT++))
fi

# 检查Pod就绪状态
FINAL_READY=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
if [ "$FINAL_READY" = "$OLD_REPLICAS" ]; then
    print_ok "所有Pod就绪 (${FINAL_READY}/${OLD_REPLICAS})"
    ((OK_COUNT++))
else
    print_fail "Pod就绪数异常 (${FINAL_READY}/${OLD_REPLICAS})"
    ((FAIL_COUNT++))
fi

# 检查是否有重启
RESTART_PODS=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOY_NAME" --no-headers 2>/dev/null | awk '{if($4>0) print $1}' | wc -l)
if [ "$RESTART_PODS" -gt 0 ]; then
    print_warn "有 ${RESTART_PODS} 个Pod存在重启记录，建议检查日志"
    ((WARN_COUNT++))
else
    print_ok "无异常重启"
    ((OK_COUNT++))
fi

# ======================== 5. 回滚判断 ========================
print_info ""
print_info ">>> [步骤5] 回滚判断..."
print_separator

if [ "$ROLLBACK_NEEDED" = true ]; then
    print_warn "检测到异常，执行自动回滚..."
    kubectl rollout undo deployment/"$DEPLOY_NAME" -n "$NAMESPACE" 2>&1
    if [ $? -eq 0 ]; then
        print_warn "已回滚到上一版本: ${OLD_IMAGE}"
        ((WARN_COUNT++))
    else
        print_fail "回滚失败！请手动执行: kubectl rollout undo deployment/${DEPLOY_NAME} -n ${NAMESPACE}"
        ((FAIL_COUNT++))
    fi
else
    print_ok "发布正常，无需回滚"
    ((OK_COUNT++))
fi

# ======================== 发布总结 ========================
echo ""
print_separator
echo ""
echo "==================== 滚动更新发布总结 ===================="
echo ""

TOTAL_CHECKS=$((OK_COUNT + WARN_COUNT + FAIL_COUNT))

echo -e "总检查项: ${TOTAL_CHECKS}  |  ${GREEN}正常: ${OK_COUNT}${NC}  |  ${YELLOW}警告: ${WARN_COUNT}${NC}  |  ${RED}异常: ${FAIL_COUNT}${NC}"
echo ""
print_info "发布耗时: ${DURATION}秒"
print_info "旧版本: ${OLD_IMAGE}"
print_info "新版本: ${IMAGE}"

if [ "$ROLLBACK_NEEDED" = true ]; then
    print_fail "结论: 发布异常，已回滚到旧版本"
    print_info "建议: 1.检查新版本镜像 2.查看Pod日志 3.修复后重新发布"
elif [ "$FAIL_COUNT" -gt 0 ]; then
    print_fail "结论: 发布完成但存在异常，请检查"
elif [ "$WARN_COUNT" -gt 0 ]; then
    print_warn "结论: 发布完成，存在警告项需关注"
else
    print_ok "结论: 滚动更新发布成功，所有检查通过"
fi

echo ""
print_separator
