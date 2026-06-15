#!/bin/bash
# ============================================================================
# 模块34-版本发布脚本
# 脚本名称: deploy-blue-green.sh
# 功能: K8S蓝绿发布，通过切换Service selector实现零停机发布
# 用法: ./deploy-blue-green.sh <app-name> <namespace> <new-image> <green-deploy>
# 示例: ./deploy-blue-green.sh myapp default myapp:v2.1.0 myapp-green
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
APP_NAME="${1:-}"
NAMESPACE="${2:-default}"
NEW_IMAGE="${3:-}"
GREEN_DEPLOY="${4:-${APP_NAME}-green}"

if [ -z "$APP_NAME" ] || [ -z "$NEW_IMAGE" ]; then
    print_fail "用法: $0 <app-name> <namespace> <new-image> [green-deploy-name]"
    print_info "示例: $0 myapp default myapp:v2.1.0 myapp-green"
    exit 1
fi

BLUE_DEPLOY="${APP_NAME}-blue"
SERVICE_NAME="${APP_NAME}-service"

# ======================== 统计变量 ========================
FAIL_COUNT=0
WARN_COUNT=0
OK_COUNT=0

# ======================== 分隔线 ========================
print_separator() {
    echo "============================================================"
}

echo "============================================================"
print_info "K8S 蓝绿发布"
print_info "应用名称: ${APP_NAME}  |  命名空间: ${NAMESPACE}"
print_info "蓝环境(Deployment): ${BLUE_DEPLOY}"
print_info "绿环境(Deployment): ${GREEN_DEPLOY}"
print_info "Service: ${SERVICE_NAME}"
print_info "新镜像: ${NEW_IMAGE}"
print_info "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

# ======================== 1. 发布前检查 ========================
print_info ""
print_info ">>> [步骤1] 发布前环境检查..."
print_separator

# 检查当前蓝环境状态
BLUE_CHECK=$(kubectl get deployment "$BLUE_DEPLOY" -n "$NAMESPACE" --no-headers 2>/dev/null)
if [ -z "$BLUE_CHECK" ]; then
    print_fail "蓝环境 Deployment ${BLUE_DEPLOY} 不存在"
    ((FAIL_COUNT++))
    print_info "请确认蓝环境已正确部署"
    print_separator
    exit 1
fi

BLUE_IMAGE=$(kubectl get deployment "$BLUE_DEPLOY" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
BLUE_REPLICAS=$(kubectl get deployment "$BLUE_DEPLOY" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null)
BLUE_READY=$(kubectl get deployment "$BLUE_DEPLOY" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
print_info "蓝环境镜像: ${BLUE_IMAGE}"
print_info "蓝环境副本: ${BLUE_READY}/${BLUE_REPLICAS}"

if [ "$BLUE_READY" != "$BLUE_REPLICAS" ]; then
    print_warn "蓝环境Pod未全部就绪 (${BLUE_READY}/${BLUE_REPLICAS})"
    ((WARN_COUNT++))
else
    print_ok "蓝环境运行正常"
    ((OK_COUNT++))
fi

# 检查Service是否存在
SVC_CHECK=$(kubectl get service "$SERVICE_NAME" -n "$NAMESPACE" --no-headers 2>/dev/null)
if [ -z "$SVC_CHECK" ]; then
    print_fail "Service ${SERVICE_NAME} 不存在"
    ((FAIL_COUNT++))
    print_info "请确认Service已正确配置"
    print_separator
    exit 1
fi

# 检查当前Service指向
CURRENT_SELECTOR=$(kubectl get service "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.selector.version}' 2>/dev/null)
print_info "Service当前指向: version=${CURRENT_SELECTOR}"

if [ "$CURRENT_SELECTOR" = "green" ]; then
    print_warn "Service当前已指向绿环境，本次发布将替换绿环境"
    ((WARN_COUNT++))
else
    print_ok "Service当前指向蓝环境"
    ((OK_COUNT++))
fi

# ======================== 2. 部署绿环境 ========================
print_info ""
print_info ">>> [步骤2] 部署绿环境..."
print_separator

# 检查绿环境是否已存在
GREEN_EXISTS=$(kubectl get deployment "$GREEN_DEPLOY" -n "$NAMESPACE" --no-headers 2>/dev/null)

if [ -n "$GREEN_EXISTS" ]; then
    print_info "绿环境已存在，更新镜像..."
    kubectl set image deployment/"$GREEN_DEPLOY" -n "$NAMESPACE" \
        "${APP_NAME}=${NEW_IMAGE}" 2>&1
    if [ $? -ne 0 ]; then
        print_fail "绿环境镜像更新失败"
        ((FAIL_COUNT++))
    else
        print_ok "绿环境镜像已更新为: ${NEW_IMAGE}"
        ((OK_COUNT++))
    fi
else
    print_info "创建绿环境 Deployment..."
    cat <<EOF | kubectl apply -n "$NAMESPACE" -f - 2>&1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${GREEN_DEPLOY}
  namespace: ${NAMESPACE}
spec:
  replicas: ${BLUE_REPLICAS}
  selector:
    matchLabels:
      app: ${APP_NAME}
      version: green
  template:
    metadata:
      labels:
        app: ${APP_NAME}
        version: green
    spec:
      containers:
      - name: ${APP_NAME}
        image: ${NEW_IMAGE}
        ports:
        - containerPort: 8080
EOF

    if [ $? -ne 0 ]; then
        print_fail "绿环境 Deployment 创建失败"
        ((FAIL_COUNT++))
        print_separator
        exit 1
    fi
    print_ok "绿环境 Deployment 已创建"
    ((OK_COUNT++))
fi

# ======================== 3. 等待绿环境就绪 ========================
print_info ""
print_info ">>> [步骤3] 等待绿环境就绪..."
print_separator

TIMEOUT=300
ELAPSED=0

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    GREEN_READY=$(kubectl get deployment "$GREEN_DEPLOY" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    GREEN_REPLICAS=$(kubectl get deployment "$GREEN_DEPLOY" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null)

    if [ "$GREEN_READY" = "$GREEN_REPLICAS" ] && [ -n "$GREEN_READY" ]; then
        print_ok "绿环境就绪 (${GREEN_READY}/${GREEN_REPLICAS})"
        ((OK_COUNT++))
        break
    fi

    # 检查绿环境Pod异常
    GREEN_CRASH=$(kubectl get pods -n "$NAMESPACE" -l "version=green" --no-headers 2>/dev/null | grep -c "CrashLoop\|Error\|OOMKilled" || true)
    if [ "$GREEN_CRASH" -gt 0 ]; then
        print_fail "绿环境有 ${GREEN_CRASH} 个异常Pod，部署失败"
        ((FAIL_COUNT++))
        break
    fi

    print_info "绿环境启动中... 就绪: ${GREEN_READY:-0}/${GREEN_REPLICAS} (${ELAPSED}s)"
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    print_fail "绿环境启动超时 (${TIMEOUT}s)"
    ((FAIL_COUNT++))
fi

# ======================== 4. 切换流量到绿环境 ========================
print_info ""
print_info ">>> [步骤4] 切换Service流量到绿环境..."
print_separator

if [ "$FAIL_COUNT" -gt 0 ]; then
    print_warn "绿环境存在异常，跳过流量切换"
    ((WARN_COUNT++))
else
    print_info "执行: kubectl patch service ${SERVICE_NAME} -p '{\"spec\":{\"selector\":{\"version\":\"green\"}}}'"
    kubectl patch service "$SERVICE_NAME" -n "$NAMESPACE" -p '{"spec":{"selector":{"version":"green"}}}' 2>&1

    if [ $? -eq 0 ]; then
        print_ok "Service已切换到绿环境"
        ((OK_COUNT++))
    else
        print_fail "Service切换失败！请手动执行切换命令"
        ((FAIL_COUNT++))
    fi
fi

# ======================== 5. 验证与清理 ========================
print_info ""
print_info ">>> [步骤5] 发布后验证..."
print_separator

# 验证Service指向
VERIFY_SELECTOR=$(kubectl get service "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.selector.version}' 2>/dev/null)
if [ "$VERIFY_SELECTOR" = "green" ]; then
    print_ok "Service确认指向绿环境"
    ((OK_COUNT++))
else
    print_fail "Service指向异常: version=${VERIFY_SELECTOR}"
    ((FAIL_COUNT++))
fi

# 检查蓝环境状态（保留，便于紧急回滚）
print_info "蓝环境保留运行中，可用于紧急回滚"
print_info "回滚命令: kubectl patch service ${SERVICE_NAME} -p '{\"spec\":{\"selector\":{\"version\":\"blue\"}}}'"

# ======================== 发布总结 ========================
echo ""
print_separator
echo ""
echo "==================== 蓝绿发布总结 ===================="
echo ""

TOTAL_CHECKS=$((OK_COUNT + WARN_COUNT + FAIL_COUNT))

echo -e "总检查项: ${TOTAL_CHECKS}  |  ${GREEN}正常: ${OK_COUNT}${NC}  |  ${YELLOW}警告: ${WARN_COUNT}${NC}  |  ${RED}异常: ${FAIL_COUNT}${NC}"
echo ""
print_info "蓝环境: ${BLUE_DEPLOY} (镜像: ${BLUE_IMAGE})"
print_info "绿环境: ${GREEN_DEPLOY} (镜像: ${NEW_IMAGE})"
print_info "Service: ${SERVICE_NAME} -> version=${VERIFY_SELECTOR}"

if [ "$FAIL_COUNT" -gt 0 ]; then
    print_fail "结论: 蓝绿发布存在异常"
    print_info "回滚命令: kubectl patch service ${SERVICE_NAME} -n ${NAMESPACE} -p '{\"spec\":{\"selector\":{\"version\":\"blue\"}}}'"
elif [ "$WARN_COUNT" -gt 0 ]; then
    print_warn "结论: 蓝绿发布完成，存在警告项"
else
    print_ok "结论: 蓝绿发布成功，流量已切换到绿环境"
fi

echo ""
print_info "清理建议: 确认稳定后(建议观察24h)，可删除蓝环境: kubectl delete deploy ${BLUE_DEPLOY} -n ${NAMESPACE}"
print_separator
