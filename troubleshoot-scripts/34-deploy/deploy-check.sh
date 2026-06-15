#!/bin/bash
# ============================================================================
# 模块34-版本发布脚本
# 脚本名称: deploy-check.sh
# 功能: 发布后健康检查，验证新版本Pod/Service/Ingress/业务接口全部正常
# 用法: ./deploy-check.sh <deployment> <namespace> [health-url] [expected-code]
# 示例: ./deploy-check.sh myapp default http://myapp.example.com/health 200
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
HEALTH_URL="${3:-}"
EXPECTED_CODE="${4:-200}"

if [ -z "$DEPLOY_NAME" ]; then
    print_fail "用法: $0 <deployment> <namespace> [health-url] [expected-code]"
    print_info "示例: $0 myapp default http://myapp.example.com/health 200"
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
print_info "发布后健康检查"
print_info "Deployment: ${DEPLOY_NAME}  |  Namespace: ${NAMESPACE}"
if [ -n "$HEALTH_URL" ]; then
    print_info "健康检查URL: ${HEALTH_URL} (期望状态码: ${EXPECTED_CODE})"
fi
print_info "检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

# ======================== 1. Deployment状态检查 ========================
print_info ""
print_info ">>> [步骤1] 检查Deployment状态..."
print_separator

DEPLOY_CHECK=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" --no-headers 2>/dev/null)
if [ -z "$DEPLOY_CHECK" ]; then
    print_fail "Deployment ${DEPLOY_NAME} 不存在"
    ((FAIL_COUNT++))
    print_separator
    exit 1
fi

DEPLOY_IMAGE=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
DEPLOY_REPLICAS=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null)
DEPLOY_READY=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
DEPLOY_UPDATED=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.status.updatedReplicas}' 2>/dev/null)
DEPLOY_AVAILABLE=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.status.availableReplicas}' 2>/dev/null)

print_info "镜像: ${DEPLOY_IMAGE}"
print_info "副本: 就绪=${DEPLOY_READY:-0} / 更新=${DEPLOY_UPDATED:-0} / 可用=${DEPLOY_AVAILABLE:-0} / 期望=${DEPLOY_REPLICAS}"

# 就绪副本检查
if [ "$DEPLOY_READY" = "$DEPLOY_REPLICAS" ]; then
    print_ok "所有副本就绪 (${DEPLOY_READY}/${DEPLOY_REPLICAS})"
    ((OK_COUNT++))
elif [ -z "$DEPLOY_READY" ] || [ "$DEPLOY_READY" = "0" ]; then
    print_fail "无就绪副本！发布可能失败"
    ((FAIL_COUNT++))
else
    print_warn "部分副本就绪 (${DEPLOY_READY}/${DEPLOY_REPLICAS})"
    ((WARN_COUNT++))
fi

# 更新副本检查
if [ "$DEPLOY_UPDATED" = "$DEPLOY_REPLICAS" ]; then
    print_ok "所有副本已更新到最新版本"
    ((OK_COUNT++))
else
    print_warn "部分副本尚未更新 (${DEPLOY_UPDATED:-0}/${DEPLOY_REPLICAS})"
    ((WARN_COUNT++))
fi

# ======================== 2. Pod状态检查 ========================
print_info ""
print_info ">>> [步骤2] 检查Pod状态..."
print_separator

POD_LIST=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOY_NAME" --no-headers 2>/dev/null)
if [ -z "$POD_LIST" ]; then
    print_fail "未找到关联Pod"
    ((FAIL_COUNT++))
else
    POD_COUNT=$(echo "$POD_LIST" | wc -l)
    RUNNING_COUNT=$(echo "$POD_LIST" | grep -c "Running" || true)
    CRASH_COUNT=$(echo "$POD_LIST" | grep -c "CrashLoop\|Error" || true)
    PENDING_COUNT=$(echo "$POD_LIST" | grep -c "Pending" || true)
    RESTART_PODS=$(echo "$POD_LIST" | awk '{if($4>0) print $1}')

    print_info "Pod总数: ${POD_COUNT}  |  Running: ${RUNNING_COUNT}  |  CrashLoop: ${CRASH_COUNT}  |  Pending: ${PENDING_COUNT}"

    if [ "$CRASH_COUNT" -gt 0 ]; then
        print_fail "有 ${CRASH_COUNT} 个Pod处于CrashLoop/Error状态"
        echo "$POD_LIST" | grep -E "CrashLoop|Error" | while read -r line; do
            print_fail "  $line"
        done
        ((FAIL_COUNT++))
    else
        print_ok "无CrashLoop/Error Pod"
        ((OK_COUNT++))
    fi

    if [ "$PENDING_COUNT" -gt 0 ]; then
        print_warn "有 ${PENDING_COUNT} 个Pod处于Pending状态"
        ((WARN_COUNT++))
    else
        print_ok "无Pending Pod"
        ((OK_COUNT++))
    fi

    # 检查重启次数
    if [ -n "$RESTART_PODS" ]; then
        RESTART_COUNT=$(echo "$RESTART_PODS" | wc -l)
        if [ "$RESTART_COUNT" -gt 0 ]; then
            print_warn "有 ${RESTART_COUNT} 个Pod存在重启记录:"
            echo "$POD_LIST" | awk '{if($4>0) print}' | while read -r line; do
                print_warn "  $line"
            done
            ((WARN_COUNT++))
        else
            print_ok "无异常重启"
            ((OK_COUNT++))
        fi
    else
        print_ok "无异常重启"
        ((OK_COUNT++))
    fi
fi

# ======================== 3. Service与Endpoint检查 ========================
print_info ""
print_info ">>> [步骤3] 检查Service与Endpoint..."
print_separator

# 查找关联Service
SVC_LIST=$(kubectl get svc -n "$NAMESPACE" --no-headers 2>/dev/null | grep "$DEPLOY_NAME" || true)
if [ -z "$SVC_LIST" ]; then
    print_warn "未找到关联Service (匹配: ${DEPLOY_NAME})"
    ((WARN_COUNT++))
else
    echo "$SVC_LIST" | while read -r svc; do
        SVC_NAME=$(echo "$svc" | awk '{print $1}')
        SVC_TYPE=$(echo "$svc" | awk '{print $2}')
        SVC_PORT=$(echo "$svc" | awk '{print $5}' | cut -d':' -f2 | cut -d'/' -f1)
        print_info "Service: ${SVC_NAME} (类型: ${SVC_TYPE}, 端口: ${SVC_PORT})"

        # 检查Endpoint
        EP_COUNT=$(kubectl get endpoints "$SVC_NAME" -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)
        if [ "$EP_COUNT" -gt 0 ]; then
            print_ok "Endpoint就绪 (${EP_COUNT}个地址)"
        else
            print_fail "Endpoint无就绪地址！Service无法转发流量"
        fi
    done
    ((OK_COUNT++))
fi

# ======================== 4. Ingress检查 ========================
print_info ""
print_info ">>> [步骤4] 检查Ingress..."
print_separator

INGRESS_LIST=$(kubectl get ingress -n "$NAMESPACE" --no-headers 2>/dev/null | grep "$DEPLOY_NAME" || true)
if [ -z "$INGRESS_LIST" ]; then
    print_info "未找到关联Ingress (非必须)"
else
    echo "$INGRESS_LIST" | while read -r ing; do
        ING_NAME=$(echo "$ing" | awk '{print $1}')
        ING_HOST=$(echo "$ing" | awk '{print $3}')
        ING_ADDR=$(kubectl get ingress "$ING_NAME" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        print_info "Ingress: ${ING_NAME} (Host: ${ING_HOST}, Address: ${ING_ADDR:-未分配})"

        if [ -n "$ING_ADDR" ]; then
            print_ok "Ingress已分配外部IP"
        else
            print_warn "Ingress未分配外部IP，可能还在初始化"
        fi
    done
    ((OK_COUNT++))
fi

# ======================== 5. 业务健康检查 ========================
print_info ""
print_info ">>> [步骤5] 业务健康检查..."
print_separator

if [ -z "$HEALTH_URL" ]; then
    print_info "未提供健康检查URL，跳过HTTP检查"
    print_info "提示: 可传入URL参数进行业务级验证"
    print_info "  用法: $0 ${DEPLOY_NAME} ${NAMESPACE} http://your-app/health 200"
else
    if command -v curl &>/dev/null; then
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$HEALTH_URL" 2>/dev/null)
        HTTP_TIME=$(curl -s -o /dev/null -w "%{time_total}" --max-time 10 "$HEALTH_URL" 2>/dev/null)

        print_info "请求URL: ${HEALTH_URL}"
        print_info "HTTP状态码: ${HTTP_CODE} (期望: ${EXPECTED_CODE})"
        print_info "响应时间: ${HTTP_TIME}s"

        if [ "$HTTP_CODE" = "$EXPECTED_CODE" ]; then
            print_ok "业务健康检查通过 (HTTP ${HTTP_CODE})"
            ((OK_COUNT++))
        else
            print_fail "业务健康检查失败! HTTP ${HTTP_CODE} != ${EXPECTED_CODE}"
            ((FAIL_COUNT++))
        fi

        # 响应时间阈值
        HTTP_TIME_INT=${HTTP_TIME%.*}
        if [ "$HTTP_TIME_INT" -gt 5 ]; then
            print_warn "响应时间过长 (${HTTP_TIME}s > 5s)"
            ((WARN_COUNT++))
        elif [ "$HTTP_TIME_INT" -gt 2 ]; then
            print_warn "响应时间偏长 (${HTTP_TIME}s > 2s)"
            ((WARN_COUNT++))
        else
            print_ok "响应时间正常 (${HTTP_TIME}s)"
            ((OK_COUNT++))
        fi
    else
        print_warn "curl命令不可用，跳过HTTP检查"
        ((WARN_COUNT++))
    fi
fi

# ======================== 检查总结 ========================
echo ""
print_separator
echo ""
echo "==================== 发布后健康检查总结 ===================="
echo ""

TOTAL_CHECKS=$((OK_COUNT + WARN_COUNT + FAIL_COUNT))

echo -e "总检查项: ${TOTAL_CHECKS}  |  ${GREEN}正常: ${OK_COUNT}${NC}  |  ${YELLOW}警告: ${WARN_COUNT}${NC}  |  ${RED}异常: ${FAIL_COUNT}${NC}"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
    print_fail "结论: 发布后检查存在 ${FAIL_COUNT} 个异常，建议回滚"
    print_info "回滚命令: kubectl rollout undo deployment/${DEPLOY_NAME} -n ${NAMESPACE}"
elif [ "$WARN_COUNT" -gt 0 ]; then
    print_warn "结论: 发布后检查存在 ${WARN_COUNT} 个警告，建议持续观察"
    print_info "观察命令: kubectl get pods -n ${NAMESPACE} -l app=${DEPLOY_NAME} -w"
else
    print_ok "结论: 发布后所有检查通过，服务运行正常"
fi

echo ""
print_separator
