#!/bin/bash
# 模块29-K8S故障排查脚本
# 功能: 检查服务间调用超时，分析Endpoint/DNS/NetworkPolicy等问题并给出修复建议
# 用法: ./check-service-timeout.sh [namespace] [service名称]
#   参数说明:
#     namespace     - 可选，指定命名空间，默认检查所有命名空间(-A)
#     service名称   - 可选，指定要检查的Service名称

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
SVC_FILTER=""

if [ -n "$1" ]; then
    NS_ARG="-n $1"
    NAMESPACE="$1"
    print_info "指定命名空间: $1"
fi

if [ -n "$2" ]; then
    SVC_FILTER="$2"
    print_info "指定Service: $2"
fi

# ============================================================
# 阈值配置
# ============================================================
ENDPOINT_WARN_THRESHOLD=0     # Endpoint为0即告警

print_info "=========================================="
print_info "K8S 服务间调用超时检查"
print_info "命名空间: ${NAMESPACE}"
if [ -n "$SVC_FILTER" ]; then
    print_info "Service过滤: ${SVC_FILTER}"
fi
print_info "=========================================="

# ============================================================
# 1. 检查Service Endpoint状态
# ============================================================
print_info ""
print_info ">>> [步骤1] 检查Service Endpoint状态..."

# 获取所有Service及其Endpoint
SVC_LIST=$(kubectl get svc ${NS_ARG} --no-headers 2>/dev/null | grep -v "kubernetes" | grep -v "ClusterIP" || true)

if [ -z "$SVC_LIST" ]; then
    print_warn "没有发现自定义Service"
else
    # 应用Service过滤
    if [ -n "$SVC_FILTER" ]; then
        SVC_LIST=$(echo "$SVC_LIST" | grep -i "$SVC_FILTER" || true)
    fi

    if [ -z "$SVC_LIST" ]; then
        print_warn "没有匹配的Service: ${SVC_FILTER}"
    else
        NO_ENDPOINT_COUNT=0
        TOTAL_SVC=$(echo "$SVC_LIST" | wc -l)
        print_info "共发现 ${TOTAL_SVC} 个Service，正在检查Endpoint..."

        echo "$SVC_LIST" | while read -r svc_line; do
            SVC_NAME=$(echo "$svc_line" | awk '{print $1}')
            if [ "$NS_ARG" = "-A" ]; then
                SVC_NS=$(echo "$svc_line" | awk '{print $2}')
            else
                SVC_NS="$1"
            fi
            SVC_TYPE=$(echo "$svc_line" | awk '{print $3}')

            # 跳过ExternalName类型Service
            if [ "$SVC_TYPE" = "ExternalName" ]; then
                print_info "  ${SVC_NS}/${SVC_NAME} (ExternalName) - 跳过检查"
                continue
            fi

            # 获取Endpoint
            EP_INFO=$(kubectl get endpoints "$SVC_NAME" -n "$SVC_NS" --no-headers 2>/dev/null)
            if [ -z "$EP_INFO" ]; then
                print_warn "  ${SVC_NS}/${SVC_NAME} - 无Endpoint信息"
                continue
            fi

            # 检查是否有就绪的Endpoint地址
            # Endpoints列格式: IP:Port,IP:Port 或 <none>
            EP_ADDRESSES=$(kubectl get endpoints "$SVC_NAME" -n "$SVC_NS" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
            EP_NOT_READY=$(kubectl get endpoints "$SVC_NAME" -n "$SVC_NS" -o jsonpath='{.subsets[*].notReadyAddresses[*].ip}' 2>/dev/null)

            if [ -z "$EP_ADDRESSES" ]; then
                print_fail "  ${SVC_NS}/${SVC_NAME} - 无可用Endpoint (服务不可达!)"
                NO_ENDPOINT_COUNT=$((NO_ENDPOINT_COUNT + 1))

                # 检查是否有notReadyAddresses
                if [ -n "$EP_NOT_READY" ]; then
                    print_warn "    存在NotReady的Endpoint: ${EP_NOT_READY}"
                    print_info "    [建议] 检查对应Pod是否通过Readiness探针"
                fi

                # 检查是否有selector
                SELECTOR=$(kubectl get svc "$SVC_NAME" -n "$SVC_NS" -o jsonpath='{.spec.selector}' 2>/dev/null)
                if [ "$SELECTOR" = "{}" ] || [ -z "$SELECTOR" ]; then
                    print_warn "    Service没有配置selector，请检查是否需要手动创建Endpoint"
                fi
            else
                EP_COUNT=$(echo "$EP_ADDRESSES" | wc -w)
                if [ "$EP_COUNT" -eq 1 ]; then
                    print_ok "  ${SVC_NS}/${SVC_NAME} - Endpoint正常 (${EP_COUNT}个: ${EP_ADDRESSES})"
                else
                    print_ok "  ${SVC_NS}/${SVC_NAME} - Endpoint正常 (${EP_COUNT}个)"
                fi

                # 检查是否有notReady的地址
                if [ -n "$EP_NOT_READY" ]; then
                    NOT_READY_COUNT=$(echo "$EP_NOT_READY" | wc -w)
                    print_warn "    有${NOT_READY_COUNT}个NotReady的Endpoint"
                fi
            fi
        done
    fi
fi

# ============================================================
# 2. 检查DNS解析
# ============================================================
print_info ""
print_info ">>> [步骤2] 检查集群DNS解析..."

# 检查CoreDNS Pod状态
COREDNS_PODS=$(kubectl get pods -A -l k8s-app=kube-dns --no-headers 2>/dev/null || \
               kubectl get pods -A -l k8s-app=coredns --no-headers 2>/dev/null || true)

if [ -z "$COREDNS_PODS" ]; then
    print_fail "未找到CoreDNS/Kube-DNS Pod"
    print_info "  [建议] 检查DNS组件是否部署: kubectl get pods -A | grep -i dns"
else
    print_info "CoreDNS Pod状态:"
    echo "$COREDNS_PODS" | while read -r dns_pod; do
        DNS_POD_NAME=$(echo "$dns_pod" | awk '{print $1}')
        DNS_POD_NS=$(echo "$dns_pod" | awk '{print $2}')
        DNS_POD_STATUS=$(echo "$dns_pod" | awk '{print $3}')
        DNS_RESTARTS=$(echo "$dns_pod" | awk '{print $4}')

        if [ "$DNS_POD_STATUS" = "Running" ]; then
            # 检查重启次数
            DNS_RESTART_NUM=$(echo "$DNS_RESTARTS" | grep -oP '\d+' || echo "0")
            if [ "$DNS_RESTART_NUM" -ge 3 ]; then
                print_warn "  ${DNS_POD_NS}/${DNS_POD_NAME} - Running (重启${DNS_RESTARTS}次，注意)"
            else
                print_ok "  ${DNS_POD_NS}/${DNS_POD_NAME} - Running (重启${DNS_RESTARTS}次)"
            fi
        else
            print_fail "  ${DNS_POD_NS}/${DNS_POD_NAME} - ${DNS_POD_STATUS} (异常!)"
        fi
    done
fi

# 检查CoreDNS Service
COREDNS_SVC=$(kubectl get svc -A --no-headers 2>/dev/null | grep -i "kube-dns\|coredns" || true)
if [ -z "$COREDNS_SVC" ]; then
    print_fail "未找到kube-dns Service"
else
    print_ok "DNS Service:"
    echo "$COREDNS_SVC" | while read -r dns_svc; do
        print_ok "  $dns_svc"
    done
fi

# 尝试DNS解析测试(使用busybox)
print_info ""
print_info "  >> 执行DNS解析测试..."

# 测试集群内部DNS解析
DNS_TEST_SVC="kubernetes.default"
DNS_RESULT=$(kubectl run dns-test-$RANDOM --image=busybox:1.28 --restart=Never --rm -i -- \
    nslookup "$DNS_TEST_SVC" 2>/dev/null || true)

if echo "$DNS_RESULT" | grep -qi "Server\|Address\|Name:"; then
    print_ok "  DNS解析正常: ${DNS_TEST_SVC} 可以解析"
else
    print_fail "  DNS解析失败: ${DNS_TEST_SVC} 无法解析"
    print_info "  [建议] 1. 检查CoreDNS Pod是否正常运行"
    print_info "  [建议] 2. 检查CoreDNS配置: kubectl get configmap coredns -n kube-system -o yaml"
    print_info "  [建议] 3. 检查Pod的dnsPolicy配置"
fi

# 如果指定了Service，测试该Service的DNS解析
if [ -n "$SVC_FILTER" ] && [ -n "$1" ]; then
    FQDN="${SVC_FILTER}.${1}.svc.cluster.local"
    print_info "  >> 测试Service DNS: ${FQDN}"
    SVC_DNS_RESULT=$(kubectl run dns-test-$RANDOM --image=busybox:1.28 --restart=Never --rm -i -- \
        nslookup "$FQDN" 2>/dev/null || true)
    if echo "$SVC_DNS_RESULT" | grep -qi "Server\|Address\|Name:"; then
        print_ok "  Service DNS解析正常: ${FQDN}"
    else
        print_fail "  Service DNS解析失败: ${FQDN}"
        print_info "  [建议] 检查Service是否存在于命名空间 ${1}"
    fi
fi

# ============================================================
# 3. 检查NetworkPolicy
# ============================================================
print_info ""
print_info ">>> [步骤3] 检查NetworkPolicy..."

NETPOL_LIST=$(kubectl get networkpolicy ${NS_ARG} --no-headers 2>/dev/null || true)

if [ -z "$NETPOL_LIST" ]; then
    print_ok "没有配置NetworkPolicy，网络通信不受限制"
else
    NETPOL_COUNT=$(echo "$NETPOL_LIST" | wc -l)
    print_warn "发现 ${NETPOL_COUNT} 个NetworkPolicy(可能影响服务间通信):"
    echo "$NETPOL_LIST" | while read -r netpol; do
        print_warn "  $netpol"
    done

    print_info ""
    print_info "  [建议] 检查以下NetworkPolicy是否阻止了服务间通信:"
    print_info "  1. 入站(Ingress)规则是否允许源Pod访问"
    print_info "  2. 出站(Egress)规则是否允许目标Service"
    print_info "  3. 端口(port)规则是否匹配"
    print_info ""
    print_info "  查看NetworkPolicy详情:"
    echo "$NETPOL_LIST" | while read -r netpol; do
        NP_NAME=$(echo "$netpol" | awk '{print $1}')
        if [ "$NS_ARG" = "-A" ]; then
            NP_NS=$(echo "$netpol" | awk '{print $2}')
        else
            NP_NS="$1"
        fi
        print_info "    kubectl describe networkpolicy ${NP_NAME} -n ${NP_NS}"
    done
fi

# ============================================================
# 4. 检查Service配置常见问题
# ============================================================
print_info ""
print_info ">>> [步骤4] 检查Service配置常见问题..."

SVC_CHECK_LIST=$(kubectl get svc ${NS_ARG} --no-headers 2>/dev/null | grep -v "kubernetes" || true)

if [ -n "$SVC_FILTER" ]; then
    SVC_CHECK_LIST=$(echo "$SVC_CHECK_LIST" | grep -i "$SVC_FILTER" || true)
fi

if [ -n "$SVC_CHECK_LIST" ]; then
    echo "$SVC_CHECK_LIST" | while read -r svc_line; do
        SVC_NAME=$(echo "$svc_line" | awk '{print $1}')
        if [ "$NS_ARG" = "-A" ]; then
            SVC_NS=$(echo "$svc_line" | awk '{print $2}')
        else
            SVC_NS="$1"
        fi

        # 检查targetPort是否有效
        TARGET_PORT=$(kubectl get svc "$SVC_NAME" -n "$SVC_NS" -o jsonpath='{.spec.ports[*].targetPort}' 2>/dev/null)
        PORT=$(kubectl get svc "$SVC_NAME" -n "$SVC_NS" -o jsonpath='{.spec.ports[*].port}' 2>/dev/null)

        # 检查selector是否匹配Pod
        SELECTOR=$(kubectl get svc "$SVC_NAME" -n "$SVC_NS" -o jsonpath='{.spec.selector}' 2>/dev/null)
        if [ "$SELECTOR" = "{}" ] || [ -z "$SELECTOR" ]; then
            # 检查是否是Headless Service
            CLUSTER_IP=$(kubectl get svc "$SVC_NAME" -n "$SVC_NS" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
            if [ "$CLUSTER_IP" = "None" ]; then
                print_info "  ${SVC_NS}/${SVC_NAME} - Headless Service (ClusterIP=None)"
            else
                print_warn "  ${SVC_NS}/${SVC_NAME} - 无selector配置"
                print_info "    [建议] 如需手动管理Endpoint，请确保Endpoints资源已创建"
            fi
        fi

        # 检查Service端口和目标端口
        if [ -n "$TARGET_PORT" ] && [ -n "$PORT" ]; then
            print_info "  ${SVC_NS}/${SVC_NAME} - 端口映射: ${PORT} -> ${TARGET_PORT}"
        fi
    done
fi

# ============================================================
# 5. 检查CNI网络插件状态
# ============================================================
print_info ""
print_info ">>> [步骤5] 检查CNI网络插件状态..."

# 常见CNI插件检查
CNI_PODS=$(kubectl get pods -A --no-headers 2>/dev/null | grep -iE "calico|flannel|cilium|weave|canal|kube-ovn|multus" || true)

if [ -z "$CNI_PODS" ]; then
    print_warn "未检测到常见CNI网络插件Pod"
    print_info "  [建议] 检查CNI插件是否正确安装"
else
    print_info "CNI网络插件Pod状态:"
    echo "$CNI_PODS" | while read -r cni_pod; do
        CNI_STATUS=$(echo "$cni_pod" | awk '{print $3}')
        CNI_NAME=$(echo "$cni_pod" | awk '{print $1}')
        CNI_NS=$(echo "$cni_pod" | awk '{print $2}')

        if [ "$CNI_STATUS" = "Running" ]; then
            print_ok "  ${CNI_NS}/${CNI_NAME} - Running"
        else
            print_fail "  ${CNI_NS}/${CNI_NAME} - ${CNI_STATUS} (异常!)"
        fi
    done
fi

# ============================================================
# 检查总结
# ============================================================
echo ""
print_info "=========================================="
print_info "检查总结"
print_info "=========================================="

print_info "服务超时常见原因排查清单:"
print_info "  1. Endpoint无地址 -> 检查Pod是否Running且通过Readiness探针"
print_info "  2. DNS解析失败    -> 检查CoreDNS状态和配置"
print_info "  3. NetworkPolicy  -> 检查网络策略是否阻止通信"
print_info "  4. CNI插件异常    -> 检查网络插件Pod状态"
print_info "  5. 端口不匹配     -> 检查Service port与容器port是否一致"
print_info "  6. 防火墙/iptables -> 检查节点防火墙规则"

print_info ""
print_info "详细排查命令:"
print_info "  kubectl describe svc <service名> -n <命名空间>"
print_info "  kubectl get endpoints <service名> -n <命名空间>"
print_info "  kubectl run -it --rm debug --image=busybox:1.28 --restart=Never -- nslookup <service名>.<命名空间>.svc.cluster.local"
print_info "  kubectl run -it --rm debug --image=busybox:1.28 --restart=Never -- wget -qO- http://<service名>:<端口>"
print_info "  kubectl get networkpolicy -A"
