#!/bin/bash
# ============================================================================
# 模块34-版本发布脚本
# 脚本名称: deploy-canary.sh
# 功能: K8S金丝雀发布，通过Ingress权重控制灰度流量比例
# 用法: ./deploy-canary.sh <app-name> <namespace> <new-image> <canary-weight>
# 示例: ./deploy-canary.sh myapp default myapp:v2.1.0 10
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
CANARY_WEIGHT="${4:-10}"

if [ -z "$APP_NAME" ] || [ -z "$NEW_IMAGE" ]; then
    print_fail "用法: $0 <app-name> <namespace> <new-image> [canary-weight%]"
    print_info "示例: $0 myapp default myapp:v2.1.0 10"
    print_info "  canary-weight: 金丝雀流量百分比，默认10%"
    exit 1
fi

# 参数校验
if ! [[ "$CANARY_WEIGHT" =~ ^[0-9]+$ ]] || [ "$CANARY_WEIGHT" -lt 1 ] || [ "$CANARY_WEIGHT" -gt 50 ]; then
    print_warn "金丝雀权重应在1-50之间，当前值: ${CANARY_WEIGHT}%"
    CANARY_WEIGHT=10
fi

STABLE_DEPLOY="${APP_NAME}-stable"
CANARY_DEPLOY="${APP_NAME}-canary"
INGRESS_NAME="${APP_NAME}-ingress"
STABLE_WEIGHT=$((100 - CANARY_WEIGHT))

# ======================== 统计变量 ========================
FAIL_COUNT=0
WARN_COUNT=0
OK_COUNT=0

# ======================== 分隔线 ========================
print_separator() {
    echo "============================================================"
}

echo "============================================================"
print_info "K8S 金丝雀发布 (Canary)"
print_info "应用名称: ${APP_NAME}  |  命名空间: ${NAMESPACE}"
print_info "稳定版(Deployment): ${STABLE_DEPLOY}"
print_info "金丝雀(Deployment): ${CANARY_DEPLOY}"
print_info "新镜像: ${NEW_IMAGE}"
print_info "流量分配: 稳定版 ${STABLE_WEIGHT}% | 金丝雀 ${CANARY_WEIGHT}%"
print_info "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

# ======================== 1. 发布前检查 ========================
print_info ""
print_info ">>> [步骤1] 发布前环境检查..."
print_separator

# 检查稳定版Deployment
STABLE_CHECK=$(kubectl get deployment "$STABLE_DEPLOY" -n "$NAMESPACE" --no-headers 2>/dev/null)
if [ -z "$STABLE_CHECK" ]; then
    print_fail "稳定版 Deployment ${STABLE_DEPLOY} 不存在"
    ((FAIL_COUNT++))
    print_separator
    exit 1
fi

STABLE_IMAGE=$(kubectl get deployment "$STABLE_DEPLOY" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
STABLE_REPLICAS=$(kubectl get deployment "$STABLE_DEPLOY" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null)
STABLE_READY=$(kubectl get deployment "$STABLE_DEPLOY" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
print_info "稳定版镜像: ${STABLE_IMAGE}"
print_info "稳定版副本: ${STABLE_READY}/${STABLE_REPLICAS}"

if [ "$STABLE_READY" != "$STABLE_REPLICAS" ]; then
    print_warn "稳定版Pod未全部就绪 (${STABLE_READY}/${STABLE_REPLICAS})"
    ((WARN_COUNT++))
else
    print_ok "稳定版运行正常"
    ((OK_COUNT++))
fi

# 检查Ingress
INGRESS_CHECK=$(kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" --no-headers 2>/dev/null)
if [ -z "$INGRESS_CHECK" ]; then
    print_warn "Ingress ${INGRESS_NAME} 不存在，将创建金丝雀Ingress"
    ((WARN_COUNT++))
else
    print_ok "Ingress ${INGRESS_NAME} 已存在"
    ((OK_COUNT++))
fi

# ======================== 2. 部署金丝雀版本 ========================
print_info ""
print_info ">>> [步骤2] 部署金丝雀版本..."
print_separator

# 金丝雀副本数: 至少1个，不超过稳定版的50%
CANARY_REPLICAS=1
if [ "$STABLE_REPLICAS" -ge 4 ]; then
    CANARY_REPLICAS=$((STABLE_REPLICAS / 2))
fi

CANARY_EXISTS=$(kubectl get deployment "$CANARY_DEPLOY" -n "$NAMESPACE" --no-headers 2>/dev/null)

if [ -n "$CANARY_EXISTS" ]; then
    print_info "金丝雀 Deployment已存在，更新镜像..."
    kubectl set image deployment/"$CANARY_DEPLOY" -n "$NAMESPACE" \
        "${APP_NAME}=${NEW_IMAGE}" 2>&1
    if [ $? -ne 0 ]; then
        print_fail "金丝雀镜像更新失败"
        ((FAIL_COUNT++))
    else
        print_ok "金丝雀镜像已更新为: ${NEW_IMAGE}"
        ((OK_COUNT++))
    fi
else
    print_info "创建金丝雀 Deployment (副本数: ${CANARY_REPLICAS})..."
    cat <<EOF | kubectl apply -n "$NAMESPACE" -f - 2>&1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${CANARY_DEPLOY}
  namespace: ${NAMESPACE}
spec:
  replicas: ${CANARY_REPLICAS}
  selector:
    matchLabels:
      app: ${APP_NAME}
      track: canary
  template:
    metadata:
      labels:
        app: ${APP_NAME}
        track: canary
    spec:
      containers:
      - name: ${APP_NAME}
        image: ${NEW_IMAGE}
        ports:
        - containerPort: 8080
EOF

    if [ $? -ne 0 ]; then
        print_fail "金丝雀 Deployment 创建失败"
        ((FAIL_COUNT++))
        print_separator
        exit 1
    fi
    print_ok "金丝雀 Deployment 已创建"
    ((OK_COUNT++))
fi

# ======================== 3. 配置Ingress权重 ========================
print_info ""
print_info ">>> [步骤3] 配置Ingress流量权重..."
print_separator

# 获取当前Ingress的host和path
INGRESS_HOST=$(kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)
INGRESS_PATH=$(kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].http.paths[0].path}' 2>/dev/null)

if [ -z "$INGRESS_HOST" ]; then
    INGRESS_HOST="example.com"
fi
if [ -z "$INGRESS_PATH" ]; then
    INGRESS_PATH="/"
fi

# 创建/更新带权重的Ingress (Nginx Ingress Controller annotations)
cat <<EOF | kubectl apply -n "$NAMESPACE" -f - 2>&1
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${INGRESS_NAME}
  namespace: ${NAMESPACE}
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "${CANARY_WEIGHT}"
spec:
  rules:
  - host: ${INGRESS_HOST}
    http:
      paths:
      - path: ${INGRESS_PATH}
        pathType: Prefix
        backend:
          service:
            name: ${CANARY_DEPLOY}-service
            port:
              number: 80
EOF

if [ $? -eq 0 ]; then
    print_ok "Ingress权重已配置: 稳定版 ${STABLE_WEIGHT}% / 金丝雀 ${CANARY_WEIGHT}%"
    ((OK_COUNT++))
else
    print_fail "Ingress配置失败"
    ((FAIL_COUNT++))
fi

# ======================== 4. 等待金丝雀就绪 ========================
print_info ""
print_info ">>> [步骤4] 等待金丝雀版本就绪..."
print_separator

TIMEOUT=180
ELAPSED=0

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    CANARY_READY=$(kubectl get deployment "$CANARY_DEPLOY" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)

    if [ "$CANARY_READY" = "$CANARY_REPLICAS" ] && [ -n "$CANARY_READY" ]; then
        print_ok "金丝雀版本就绪 (${CANARY_READY}/${CANARY_REPLICAS})"
        ((OK_COUNT++))
        break
    fi

    CANARY_CRASH=$(kubectl get pods -n "$NAMESPACE" -l "track=canary" --no-headers 2>/dev/null | grep -c "CrashLoop\|Error\|OOMKilled" || true)
    if [ "$CANARY_CRASH" -gt 0 ]; then
        print_fail "金丝雀版本有 ${CANARY_CRASH} 个异常Pod"
        ((FAIL_COUNT++))
        break
    fi

    print_info "金丝雀启动中... 就绪: ${CANARY_READY:-0}/${CANARY_REPLICAS} (${ELAPSED}s)"
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    print_fail "金丝雀启动超时 (${TIMEOUT}s)"
    ((FAIL_COUNT++))
fi

# ======================== 5. 灰度观察提示 ========================
print_info ""
print_info ">>> [步骤5] 灰度观察..."
print_separator

print_info "金丝雀发布已生效，当前 ${CANARY_WEIGHT}% 流量指向新版本"
print_info ""
print_info "观察指标:"
print_info "  1. 错误率: kubectl logs -n ${NAMESPACE} -l track=canary --tail=100 | grep -i error"
print_info "  2. 响应时间: 观察APM监控面板"
print_info "  3. 业务指标: 检查订单/交易等核心指标是否异常"
print_info ""
print_info "逐步放量命令:"
print_info "  20%: kubectl annotate ingress ${INGRESS_NAME} -n ${NAMESPACE} nginx.ingress.kubernetes.io/canary-weight=20 --overwrite"
print_info "  50%: kubectl annotate ingress ${INGRESS_NAME} -n ${NAMESPACE} nginx.ingress.kubernetes.io/canary-weight=50 --overwrite"
print_info "  100%: 删除金丝雀Ingress，将稳定版替换为新版本"
print_info ""
print_info "紧急回滚命令:"
print_info "  kubectl delete ingress ${INGRESS_NAME} -n ${NAMESPACE}"
print_info "  kubectl delete deployment ${CANARY_DEPLOY} -n ${NAMESPACE}"

# ======================== 发布总结 ========================
echo ""
print_separator
echo ""
echo "==================== 金丝雀发布总结 ===================="
echo ""

TOTAL_CHECKS=$((OK_COUNT + WARN_COUNT + FAIL_COUNT))

echo -e "总检查项: ${TOTAL_CHECKS}  |  ${GREEN}正常: ${OK_COUNT}${NC}  |  ${YELLOW}警告: ${WARN_COUNT}${NC}  |  ${RED}异常: ${FAIL_COUNT}${NC}"
echo ""
print_info "稳定版: ${STABLE_DEPLOY} (镜像: ${STABLE_IMAGE}, 流量: ${STABLE_WEIGHT}%)"
print_info "金丝雀: ${CANARY_DEPLOY} (镜像: ${NEW_IMAGE}, 流量: ${CANARY_WEIGHT}%)"

if [ "$FAIL_COUNT" -gt 0 ]; then
    print_fail "结论: 金丝雀发布存在异常，建议回滚"
elif [ "$WARN_COUNT" -gt 0 ]; then
    print_warn "结论: 金丝雀已部署，存在警告项，请观察后决定是否放量"
else
    print_ok "结论: 金丝雀发布成功，请观察指标后逐步放量"
fi

echo ""
print_info "建议观察时间: 30分钟~2小时，无异常后逐步提升至100%"
print_separator
