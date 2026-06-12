#!/bin/bash
# 模块29-K8S故障排查脚本
# 功能: 检查Ingress访问异常，分析Ingress控制器/配置/后端Service等问题并给出修复建议
# 用法: ./check-ingress.sh [namespace] [ingress名称]
#   参数说明:
#     namespace       - 可选，指定命名空间，默认检查所有命名空间(-A)
#     ingress名称     - 可选，指定要检查的Ingress名称

# ============================================================
# 颜色函数定义
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_info() { echo -e "[INFO] $1"; }

# ============================================================
# 参数处理
# ============================================================
NS_ARG="-A"
NAMESPACE="所有命名空间"
INGRESS_FILTER=""

if [ -n "$1" ]; then
    NS_ARG="-n $1"
    NAMESPACE="$1"
    print_info "指定命名空间: $1"
fi

if [ -n "$2" ]; then
    INGRESS_FILTER="$2"
    print_info "指定Ingress: $2"
fi

# ============================================================
# 阈值配置
# ============================================================
INGRESS_CTRL_WARN_RESTART=3   # Ingress控制器重启警告阈值

print_info "=========================================="
print_info "K8S Ingress 访问异常检查"
print_info "命名空间: ${NAMESPACE}"
if [ -n "$INGRESS_FILTER" ]; then
    print_info "Ingress过滤: ${INGRESS_FILTER}"
fi
print_info "=========================================="

# ============================================================
# 1. 检查Ingress控制器Pod状态
# ============================================================
print_info ""
print_info ">>> [步骤1] 检查Ingress控制器Pod状态..."

# 尝试常见的Ingress控制器命名空间
INGRESS_NS_FOUND=""
for ns in ingress-nginx nginx-ingress kube-system ingress; do
    INGRESS_CTRL_PODS=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -iE "nginx|ingress-controller|traefik|haproxy" || true)
    if [ -n "$INGRESS_CTRL_PODS" ]; then
        INGRESS_NS_FOUND="$ns"
        break
    fi
done

if [ -z "$INGRESS_NS_FOUND" ]; then
    print_fail "未找到Ingress控制器Pod"
    print_info "  [建议] 检查是否已安装Ingress控制器(如nginx-ingress/traefik)"
    print_info "  [建议] 常见安装方式: helm install ingress-nginx ingress-nginx/ingress-nginx"
else
    print_info "Ingress控制器命名空间: ${INGRESS_NS_FOUND}"
    print_info "Ingress控制器Pod状态:"
    echo "$INGRESS_CTRL_PODS" | while read -r pod_line; do
        POD_NAME=$(echo "$pod_line" | awk '{print $1}')
        POD_NS=$(echo "$pod_line" | awk '{print $2}')
        POD_STATUS=$(echo "$pod_line" | awk '{print $3}')
        POD_RESTARTS=$(echo "$pod_line" | awk '{print $4}')

        if [ "$POD_STATUS" = "Running" ]; then
            RESTART_NUM=$(echo "$POD_RESTARTS" | grep -oP '\d+' || echo "0")
            if [ "$RESTART_NUM" -ge "$INGRESS_CTRL_WARN_RESTART" ]; then
                print_warn "  ${POD_NS}/${POD_NAME} - Running (重启${POD_RESTARTS}次，注意)"
            else
                print_ok "  ${POD_NS}/${POD_NAME} - Running (重启${POD_RESTARTS}次)"
            fi

            # 检查容器就绪状态
            READY=$(echo "$pod_line" | awk '{print $2}')
            READY_1=$(echo "$READY" | cut -d'/' -f1)
            READY_2=$(echo "$READY" | cut -d'/' -f2)
            if [ "$READY_1" -lt "$READY_2" ]; then
                print_warn "    容器未完全就绪: ${READY_1}/${READY_2}"
            fi
        else
            print_fail "  ${POD_NS}/${POD_NAME} - ${POD_STATUS} (异常!)"
        fi
    done

    # 检查Ingress控制器Service
    print_info ""
    print_info "Ingress控制器Service:"
    INGRESS_SVCS=$(kubectl get svc -n "$INGRESS_NS_FOUND" --no-headers 2>/dev/null | grep -iE "nginx|ingress|traefik" || true)
    if [ -n "$INGRESS_SVCS" ]; then
        echo "$INGRESS_SVCS" | while read -r isvc; do
            ISVC_NAME=$(echo "$isvc" | awk '{print $1}')
            ISVC_TYPE=$(echo "$isvc" | awk '{print $3}')
            ISVC_IP=$(echo "$isvc" | awk '{print $4}')

            if [ "$ISVC_TYPE" = "LoadBalancer" ]; then
                EXT_IP=$(echo "$isvc" | awk '{print $5}')
                if [ "$EXT_IP" = "<pending>" ] || [ -z "$EXT_IP" ]; then
                    print_fail "  ${ISVC_NAME} - LoadBalancer IP: ${EXT_IP} (未分配!)"
                    print_info "    [建议] 检查云厂商负载均衡器配置或使用NodePort替代"
                else
                    print_ok "  ${ISVC_NAME} - ${ISVC_TYPE} 外部IP: ${EXT_IP}"
                fi
            elif [ "$ISVC_TYPE" = "NodePort" ]; then
                PORTS=$(echo "$isvc" | awk '{print $6}')
                print_ok "  ${ISVC_NAME} - ${ISVC_TYPE} 端口: ${PORTS}"
            else
                print_info "  ${ISVC_NAME} - ${ISVC_TYPE} ClusterIP: ${ISVC_IP}"
            fi
        done
    else
        print_warn "  未找到Ingress控制器Service"
    fi

    # 检查Ingress控制器配置(ConfigMap)
    print_info ""
    print_info "Ingress控制器ConfigMap:"
    INGRESS_CM=$(kubectl get configmap -n "$INGRESS_NS_FOUND" --no-headers 2>/dev/null | grep -iE "nginx|ingress" || true)
    if [ -n "$INGRESS_CM" ]; then
        echo "$INGRESS_CM" | while read -r icm; do
            print_info "  $icm"
        done
    fi
fi

# ============================================================
# 2. 检查Ingress资源配置
# ============================================================
print_info ""
print_info ">>> [步骤2] 检查Ingress资源配置..."

INGRESS_LIST=$(kubectl get ingress ${NS_ARG} --no-headers 2>/dev/null || true)

if [ -z "$INGRESS_LIST" ]; then
    print_warn "没有发现Ingress资源"
else
    # 应用Ingress过滤
    if [ -n "$INGRESS_FILTER" ]; then
        INGRESS_LIST=$(echo "$INGRESS_LIST" | grep -i "$INGRESS_FILTER" || true)
    fi

    if [ -z "$INGRESS_LIST" ]; then
        print_warn "没有匹配的Ingress: ${INGRESS_FILTER}"
    else
        INGRESS_COUNT=$(echo "$INGRESS_LIST" | wc -l)
        print_info "共发现 ${INGRESS_COUNT} 个Ingress资源"

        echo "$INGRESS_LIST" | while read -r ing_line; do
            ING_NAME=$(echo "$ing_line" | awk '{print $1}')
            if [ "$NS_ARG" = "-A" ]; then
                ING_NS=$(echo "$ing_line" | awk '{print $2}')
            else
                ING_NS="$1"
            fi
            ING_CLASS=$(echo "$ing_line" | awk '{print $3}')
            ING_HOSTS=$(echo "$ing_line" | awk '{print $4}')
            ING_ADDR=$(echo "$ing_line" | awk '{print $5}')

            echo ""
            print_info "--- Ingress: ${ING_NS}/${ING_NAME} ---"

            # 检查Ingress Class
            if [ -z "$ING_CLASS" ] || [ "$ING_CLASS" = "<none>" ]; then
                print_warn "  未指定IngressClass"
                print_info "  [建议] 指定annotations或ingressClassName以确保路由到正确的控制器"
            else
                print_ok "  IngressClass: ${ING_CLASS}"
            fi

            # 检查Host和Address
            print_info "  Hosts: ${ING_HOSTS}"
            print_info "  Address: ${ING_ADDR}"

            if [ -z "$ING_ADDR" ] || [ "$ING_ADDR" = "<none>" ]; then
                print_warn "  未分配外部地址"
            fi

            # 检查TLS配置
            TLS_CONFIG=$(kubectl get ingress "$ING_NAME" -n "$ING_NS" -o jsonpath='{.spec.tls}' 2>/dev/null)
            if [ -n "$TLS_CONFIG" ] && [ "$TLS_CONFIG" != "[]" ]; then
                TLS_HOSTS=$(kubectl get ingress "$ING_NAME" -n "$ING_NS" -o jsonpath='{range .spec.tls[*]}{.hosts[*]}{","}{end}' 2>/dev/null)
                TLS_SECRET=$(kubectl get ingress "$ING_NAME" -n "$ING_NS" -o jsonpath='{range .spec.tls[*]}{.secretName}{","}{end}' 2>/dev/null)
                print_info "  TLS Hosts: ${TLS_HOSTS}"
                print_info "  TLS Secret: ${TLS_SECRET}"

                # 检查Secret是否存在
                IFS=',' read -ra SECRETS <<< "$TLS_SECRET"
                for secret in "${SECRETS[@]}"; do
                    if [ -n "$secret" ]; then
                        SECRET_CHECK=$(kubectl get secret "$secret" -n "$ING_NS" --no-headers 2>/dev/null || true)
                        if [ -z "$SECRET_CHECK" ]; then
                            print_fail "  TLS Secret '${secret}' 不存在! HTTPS将无法工作"
                            print_info "  [建议] 创建TLS Secret: kubectl create secret tls <名称> --cert=tls.crt --key=tls.key"
                        else
                            SECRET_TYPE=$(echo "$SECRET_CHECK" | awk '{print $3}')
                            if [ "$SECRET_TYPE" = "kubernetes.io/tls" ]; then
                                print_ok "  TLS Secret '${secret}' 存在且类型正确"
                            else
                                print_warn "  TLS Secret '${secret}' 类型为${SECRET_TYPE}，建议使用kubernetes.io/tls"
                            fi
                        fi
                    fi
                done
            else
                print_info "  未配置TLS (仅HTTP)"
            fi

            # 检查后端Service规则
            print_info "  >> 检查后端路由规则..."
            BACKEND_RULES=$(kubectl get ingress "$ING_NAME" -n "$ING_NS" -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
rules = data.get('spec', {}).get('rules', [])
default_backend = data.get('spec', {}).get('defaultBackend', {})

if default_backend:
    svc = default_backend.get('service', {})
    print(f'  默认后端: Service={svc.get(\"name\",\"N/A\")}, Port={svc.get(\"port\",{}).get(\"number\",\"N/A\")}')

for rule in rules:
    host = rule.get('host', '*')
    http = rule.get('http', {})
    paths = http.get('paths', [])
    for path in paths:
        backend = path.get('backend', {})
        svc_name = backend.get('service', {}).get('name', 'N/A')
        svc_port = backend.get('service', {}).get('port', {}).get('number', 'N/A')
        path_val = path.get('path', '/')
        path_type = path.get('pathType', 'N/A')
        print(f'  Host: {host} Path: {path_val} ({path_type}) -> Service: {svc_name}:{svc_port}')
" 2>/dev/null || true)

            if [ -n "$BACKEND_RULES" ]; then
                echo "$BACKEND_RULES" | while read -r rule; do
                    print_info "    $rule"
                done

                # 提取后端Service名并检查
                BACKEND_SVCS=$(kubectl get ingress "$ING_NAME" -n "$ING_NS" -o jsonpath='{.spec.rules[*].http.paths[*].backend.service.name}' 2>/dev/null | tr ' ' '\n' | sort -u || true)
                if [ -n "$BACKEND_SVCS" ]; then
                    echo "$BACKEND_SVCS" | while read -r bs; do
                        if [ -z "$bs" ]; then
                            continue
                        fi
                        # 检查后端Service是否存在
                        BS_CHECK=$(kubectl get svc "$bs" -n "$ING_NS" --no-headers 2>/dev/null || true)
                        if [ -z "$BS_CHECK" ]; then
                            print_fail "  后端Service '${bs}' 不存在于命名空间 ${ING_NS}!"
                            print_info "  [建议] 检查Ingress配置中的Service名称是否正确"
                        else
                            print_ok "  后端Service '${bs}' 存在"

                            # 检查后端Service的Endpoint
                            BS_EP=$(kubectl get endpoints "$bs" -n "$ING_NS" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
                            if [ -z "$BS_EP" ]; then
                                print_fail "  后端Service '${bs}' 无可用Endpoint (流量无法到达后端!)"
                                print_info "  [建议] 检查Service '${bs}' 的selector是否匹配到Pod"
                            else
                                EP_COUNT=$(echo "$BS_EP" | wc -w)
                                print_ok "  后端Service '${bs}' 有${EP_COUNT}个Endpoint"
                            fi
                        fi
                    done
                fi
            else
                print_warn "  无法解析后端路由规则"
            fi

            # 检查Annotations
            print_info "  >> 检查Annotations..."
            ANNOTATIONS=$(kubectl get ingress "$ING_NAME" -n "$ING_NS" -o jsonpath='{.metadata.annotations}' 2>/dev/null)
            if [ -n "$ANNOTATIONS" ] && [ "$ANNOTATIONS" != "map[]" ]; then
                # 检查常见问题annotations
                if echo "$ANNOTATIONS" | grep -qi "rewrite-target\|ssl-redirect\|proxy-body-size\|proxy-read-timeout\|cors"; then
                    print_info "  发现关键Annotations配置"
                fi

                # 检查nginx相关超时配置
                PROXY_TIMEOUT=$(kubectl get ingress "$ING_NAME" -n "$ING_NS" -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/proxy-read-timeout}' 2>/dev/null)
                if [ -n "$PROXY_TIMEOUT" ]; then
                    print_info "  proxy-read-timeout: ${PROXY_TIMEOUT}s"
                    if [ "$PROXY_TIMEOUT" -lt 60 ]; then
                        print_warn "  proxy-read-timeout较小(${PROXY_TIMEOUT}s)，可能导致长连接超时"
                    fi
                fi

                PROXY_BODY_SIZE=$(kubectl get ingress "$ING_NAME" -n "$ING_NS" -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/proxy-body-size}' 2>/dev/null)
                if [ -n "$PROXY_BODY_SIZE" ]; then
                    print_info "  proxy-body-size: ${PROXY_BODY_SIZE}"
                fi
            else
                print_info "  未配置特殊Annotations"
            fi
        done
    fi
fi

# ============================================================
# 3. 检查Ingress Class资源
# ============================================================
print_info ""
print_info ">>> [步骤3] 检查IngressClass资源..."

INGRESS_CLASSES=$(kubectl get ingressclass --no-headers 2>/dev/null || true)
if [ -z "$INGRESS_CLASSES" ]; then
    print_warn "没有定义IngressClass资源"
    print_info "  [建议] 创建IngressClass以明确指定Ingress控制器"
else
    print_info "可用IngressClass:"
    echo "$INGRESS_CLASSES" | while read -r ic; do
        IC_NAME=$(echo "$ic" | awk '{print $1}')
        IC_CTRL=$(echo "$ic" | awk '{print $2}')
        print_ok "  ${IC_NAME} (控制器: ${IC_CTRL})"
    done
fi

# ============================================================
# 4. 检查Ingress控制器日志
# ============================================================
print_info ""
print_info ">>> [步骤4] 检查Ingress控制器最近日志..."

if [ -n "$INGRESS_NS_FOUND" ]; then
    # 获取控制器Pod名称
    CTRL_POD=$(kubectl get pods -n "$INGRESS_NS_FOUND" --no-headers 2>/dev/null | grep -iE "nginx|ingress-controller" | head -1 | awk '{print $1}')
    if [ -n "$CTRL_POD" ]; then
        CTRL_LOGS=$(kubectl logs "$CTRL_POD" -n "$INGRESS_NS_FOUND" --tail=30 2>/dev/null || true)
        if [ -n "$CTRL_LOGS" ]; then
            ERROR_COUNT=$(echo "$CTRL_LOGS" | grep -ciE "error|warn|fail|timeout|refused|upstream" || echo "0")
            if [ "$ERROR_COUNT" -gt 0 ]; then
                print_warn "Ingress控制器日志中发现 ${ERROR_COUNT} 条警告/错误:"
                echo "$CTRL_LOGS" | grep -iE "error|warn|fail|timeout|refused|upstream" | tail -5 | while read -r log_line; do
                    print_warn "  $log_line"
                done
            else
                print_ok "Ingress控制器日志正常(最近30行无错误)"
            fi
        else
            print_warn "无法获取Ingress控制器日志"
        fi
    fi
else
    print_warn "跳过日志检查(未找到Ingress控制器)"
fi

# ============================================================
# 检查总结
# ============================================================
echo ""
print_info "=========================================="
print_info "检查总结"
print_info "=========================================="

print_info "Ingress访问异常常见原因排查清单:"
print_info "  1. 控制器Pod异常  -> 检查Ingress控制器Pod状态和日志"
print_info "  2. Service无Endpoint -> 检查后端Service是否正确关联Pod"
print_info "  3. IngressClass错误 -> 检查ingressClassName是否匹配控制器"
print_info "  4. TLS证书问题    -> 检查Secret是否存在且类型正确"
print_info "  5. 路径配置错误    -> 检查path和pathType配置"
print_info "  6. 超时配置过小    -> 检查proxy-read-timeout等annotations"
print_info "  7. LoadBalancer未分配 -> 检查云厂商LB配置"

print_info ""
print_info "详细排查命令:"
print_info "  kubectl get ingress -A -o wide"
print_info "  kubectl describe ingress <ingress名> -n <命名空间>"
print_info "  kubectl get svc -n <ingress控制器命名空间>"
print_info "  kubectl logs -n <ingress控制器命名空间> <控制器pod名> --tail=100"
print_info "  kubectl get ingressclass"
