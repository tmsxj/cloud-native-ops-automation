#!/bin/bash
# 模块29-K8S故障排查脚本
# 功能: 检查K8S节点健康状态，分析节点条件/资源/磁盘/网络等问题并给出修复建议
# 用法: ./check-node-health.sh [节点名称]
#   参数说明:
#     节点名称 - 可选，指定要检查的节点名称，默认检查所有节点

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
NODE_FILTER=""
if [ -n "$1" ]; then
    NODE_FILTER="$1"
    print_info "指定节点: $1"
fi

# ============================================================
# 阈值配置
# ============================================================
DISK_WARN_THRESHOLD=70       # 磁盘使用率警告阈值(%)
DISK_CRIT_THRESHOLD=85       # 磁盘使用率严重阈值(%)
MEM_ALLOC_WARN_THRESHOLD=70  # 内存分配率警告阈值(%)
MEM_ALLOC_CRIT_THRESHOLD=90  # 内存分配率严重阈值(%)
CPU_ALLOC_WARN_THRESHOLD=70  # CPU分配率警告阈值(%)
CPU_ALLOC_CRIT_THRESHOLD=90  # CPU分配率严重阈值(%)
PID_WARN_THRESHOLD=80        # PID使用率警告阈值(%)

print_info "=========================================="
print_info "K8S 节点健康状态检查"
if [ -n "$NODE_FILTER" ]; then
    print_info "节点过滤: ${NODE_FILTER}"
else
    print_info "检查范围: 所有节点"
fi
print_info "=========================================="

# ============================================================
# 1. 检查节点基本状态
# ============================================================
print_info ""
print_info ">>> [步骤1] 检查节点基本状态..."

NODES=$(kubectl get nodes --no-headers 2>/dev/null)

if [ -z "$NODES" ]; then
    print_fail "无法获取节点列表，请检查kubeconfig配置"
    exit 1
fi

# 应用节点过滤
if [ -n "$NODE_FILTER" ]; then
    NODES=$(echo "$NODES" | grep -i "$NODE_FILTER" || true)
    if [ -z "$NODES" ]; then
        print_fail "未找到匹配的节点: ${NODE_FILTER}"
        exit 1
    fi
fi

TOTAL_NODES=$(echo "$NODES" | wc -l)
READY_NODES=0
NOT_READY_NODES=0

print_info "节点状态总览:"
echo "$NODES" | while read -r node_line; do
    NODE_NAME=$(echo "$node_line" | awk '{print $1}')
    NODE_STATUS=$(echo "$node_line" | awk '{print $2}')
    ROLES=$(echo "$node_line" | awk '{for(i=3;i<=NF;i++) printf "%s ", $i; print ""}')
    VERSION=$(echo "$node_line" | grep -oP 'v\d+\.\d+\.\d+' || echo "unknown")

    # 检查节点状态
    if echo "$NODE_STATUS" | grep -q "Ready"; then
        # 检查是否有额外的状态标记(如SchedulingDisabled)
        if echo "$NODE_STATUS" | grep -q "SchedulingDisabled"; then
            print_warn "  ${NODE_NAME} - Ready,SchedulingDisabled (节点被封锁，不接受新Pod)"
        else
            print_ok "  ${NODE_NAME} - Ready (角色: ${ROLES} 版本: ${VERSION})"
        fi
    else
        print_fail "  ${NODE_NAME} - ${NODE_STATUS} (节点异常!)"
    fi
done

# 统计就绪/未就绪节点数
READY_NODES=$(echo "$NODES" | grep -c "Ready" || true)
NOT_READY_NODES=$((TOTAL_NODES - READY_NODES))

if [ "$NOT_READY_NODES" -gt 0 ]; then
    print_fail "有 ${NOT_READY_NODES}/${TOTAL_NODES} 个节点未就绪!"
else
    print_ok "所有 ${TOTAL_NODES} 个节点均处于就绪状态"
fi

# ============================================================
# 2. 检查节点详细条件(Conditions)
# ============================================================
print_info ""
print_info ">>> [步骤2] 检查节点详细条件(Conditions)..."

echo "$NODES" | while read -r node_line; do
    NODE_NAME=$(echo "$node_line" | awk '{print $1}')
    NODE_STATUS=$(echo "$node_line" | awk '{print $2}')

    echo ""
    print_info "--- 节点: ${NODE_NAME} ---"

    # 获取节点Conditions
    CONDITIONS=$(kubectl describe node "$NODE_NAME" 2>/dev/null | grep -A 20 "Conditions:" | grep -E "Type|Status|Reason|Message" | grep -v "^--" || true)

    if [ -z "$CONDITIONS" ]; then
        print_warn "  无法获取节点条件信息"
        continue
    fi

    # 解析关键条件
    # MemoryPressure
    MEM_PRESSURE=$(echo "$CONDITIONS" | grep -A 2 "MemoryPressure" | grep "Status" | awk '{print $2}' || true)
    if [ "$MEM_PRESSURE" = "True" ]; then
        print_fail "  MemoryPressure: True (节点内存压力过大!)"
        print_info "  [建议] 1. 检查哪些Pod占用内存最多: kubectl top pod -A --sort-by=memory | head -20"
        print_info "  [建议] 2. 考虑驱逐低优先级Pod或扩容节点"
    elif [ "$MEM_PRESSURE" = "Unknown" ]; then
        print_warn "  MemoryPressure: Unknown (Kubelet可能无法获取内存信息)"
    else
        print_ok "  MemoryPressure: False"
    fi

    # DiskPressure
    DISK_PRESSURE=$(echo "$CONDITIONS" | grep -A 2 "DiskPressure" | grep "Status" | awk '{print $2}' || true)
    if [ "$DISK_PRESSURE" = "True" ]; then
        print_fail "  DiskPressure: True (节点磁盘压力过大!)"
        print_info "  [建议] 1. 清理旧日志和容器镜像: docker system prune / crictl rmp"
        print_info "  [建议] 2. 清理kubelet日志: journalctl --vacuum-size=100M"
        print_info "  [建议] 3. 检查磁盘使用: df -h"
    elif [ "$DISK_PRESSURE" = "Unknown" ]; then
        print_warn "  DiskPressure: Unknown (Kubelet可能无法获取磁盘信息)"
    else
        print_ok "  DiskPressure: False"
    fi

    # PIDPressure
    PID_PRESSURE=$(echo "$CONDITIONS" | grep -A 2 "PIDPressure" | grep "Status" | awk '{print $2}' || true)
    if [ "$PID_PRESSURE" = "True" ]; then
        print_fail "  PIDPressure: True (节点PID资源耗尽!)"
        print_info "  [建议] 1. 检查是否有进程泄漏"
        print_info "  [建议] 2. 调整内核PID上限: sysctl kernel.pid_max"
    else
        print_ok "  PIDPressure: False"
    fi

    # Ready
    READY_COND=$(echo "$CONDITIONS" | grep -A 2 "Ready" | grep "Status" | awk '{print $2}' || true)
    if [ "$READY_COND" = "True" ]; then
        print_ok "  Ready: True"
    elif [ "$READY_COND" = "Unknown" ]; then
        print_fail "  Ready: Unknown (节点状态未知，Kubelet可能已停止!)"
        print_info "  [建议] 1. 检查Kubelet服务状态: systemctl status kubelet"
        print_info "  [建议] 2. 检查节点SSH连通性"
        print_info "  [建议] 3. 检查节点系统日志: journalctl -u kubelet -f"
    else
        print_fail "  Ready: False (节点未就绪!)"
        READY_REASON=$(echo "$CONDITIONS" | grep -A 2 "Ready" | grep "Reason" | awk '{print $2}' || true)
        if [ -n "$READY_REASON" ]; then
            print_fail "    原因: ${READY_REASON}"
        fi
    fi

    # NetworkUnavailable
    NET_UNAVAIL=$(echo "$CONDITIONS" | grep -A 2 "NetworkUnavailable" | grep "Status" | awk '{print $2}' || true)
    if [ "$NET_UNAVAIL" = "True" ]; then
        print_fail "  NetworkUnavailable: True (节点网络不可用!)"
        print_info "  [建议] 1. 检查CNI网络插件状态"
        print_info "  [建议] 2. 检查节点网络配置: ip addr show"
    else
        print_ok "  NetworkUnavailable: False"
    fi
done

# ============================================================
# 3. 检查节点资源分配情况
# ============================================================
print_info ""
print_info ">>> [步骤3] 检查节点资源分配情况..."

echo "$NODES" | while read -r node_line; do
    NODE_NAME=$(echo "$node_line" | awk '{print $1}')

    echo ""
    print_info "--- 节点: ${NODE_NAME} ---"

    # 获取资源分配信息
    ALLOC_INFO=$(kubectl describe node "$NODE_NAME" 2>/dev/null | grep -A 5 "Allocated resources" || true)

    if [ -z "$ALLOC_INFO" ]; then
        print_warn "  无法获取资源分配信息"
        continue
    fi

    # 解析CPU分配率
    CPU_LINE=$(echo "$ALLOC_INFO" | grep "cpu " || echo "$ALLOC_INFO" | grep "cpu(" || true)
    if [ -n "$CPU_LINE" ]; then
        CPU_PERCENT=$(echo "$CPU_LINE" | grep -oP '\d+(?=%)' | head -1)
        CPU_REQUEST=$(echo "$CPU_LINE" | grep -oP '\d+(?=%)' | head -1)
        if [ -n "$CPU_PERCENT" ]; then
            if [ "$CPU_PERCENT" -ge "$CPU_ALLOC_CRIT_THRESHOLD" ]; then
                print_fail "  CPU分配率: ${CPU_PERCENT}% (>=${CPU_ALLOC_CRIT_THRESHOLD}%, 严重!)"
                print_info "  [建议] 1. 检查CPU密集型Pod: kubectl top pod -A --sort-by=cpu | head -20"
                print_info "  [建议] 2. 考虑扩容或调整Pod的CPU requests"
            elif [ "$CPU_PERCENT" -ge "$CPU_ALLOC_WARN_THRESHOLD" ]; then
                print_warn "  CPU分配率: ${CPU_PERCENT}% (>=${CPU_ALLOC_WARN_THRESHOLD}%, 注意)"
            else
                print_ok "  CPU分配率: ${CPU_PERCENT}%"
            fi
        fi
    fi

    # 解析内存分配率
    MEM_LINE=$(echo "$ALLOC_INFO" | grep "memory" || true)
    if [ -n "$MEM_LINE" ]; then
        MEM_PERCENT=$(echo "$MEM_LINE" | grep -oP '\d+(?=%)' | head -1)
        if [ -n "$MEM_PERCENT" ]; then
            if [ "$MEM_PERCENT" -ge "$MEM_ALLOC_CRIT_THRESHOLD" ]; then
                print_fail "  内存分配率: ${MEM_PERCENT}% (>=${MEM_ALLOC_CRIT_THRESHOLD}%, 严重!)"
                print_info "  [建议] 1. 检查内存占用最多的Pod: kubectl top pod -A --sort-by=memory | head -20"
                print_info "  [建议] 2. 考虑扩容或调整Pod的内存requests"
            elif [ "$MEM_PERCENT" -ge "$MEM_ALLOC_WARN_THRESHOLD" ]; then
                print_warn "  内存分配率: ${MEM_PERCENT}% (>=${MEM_ALLOC_WARN_THRESHOLD}%, 注意)"
            else
                print_ok "  内存分配率: ${MEM_PERCENT}%"
            fi
        fi
    fi

    # 显示完整资源容量
    CAPACITY=$(kubectl describe node "$NODE_NAME" 2>/dev/null | grep -A 6 "Capacity:" | head -7 || true)
    if [ -n "$CAPACITY" ]; then
        print_info "  资源容量:"
        echo "$CAPACITY" | while read -r cap_line; do
            if echo "$cap_line" | grep -qiE "cpu|memory|pods|ephemeral-storage"; then
                print_info "    $cap_line"
            fi
        done
    fi
done

# ============================================================
# 4. 检查节点磁盘使用情况
# ============================================================
print_info ""
print_info ">>> [步骤4] 检查节点磁盘使用情况..."

# 通过kubectl describe获取ephemeral-storage信息
echo "$NODES" | while read -r node_line; do
    NODE_NAME=$(echo "$node_line" | awk '{print $1}')

    # 检查节点上的ephemeral-storage分配
    EPHEMERAL=$(kubectl describe node "$NODE_NAME" 2>/dev/null | grep -i "ephemeral-storage" | head -3 || true)
    if [ -n "$EPHEMERAL" ]; then
        EPHEMERAL_PERCENT=$(echo "$EPHEMERAL" | grep -oP '\d+(?=%)' | tail -1 || true)
        if [ -n "$EPHEMERAL_PERCENT" ]; then
            if [ "$EPHEMERAL_PERCENT" -ge "$DISK_CRIT_THRESHOLD" ]; then
                print_fail "  ${NODE_NAME} - ephemeral-storage使用率: ${EPHEMERAL_PERCENT}% (>=${DISK_CRIT_THRESHOLD}%, 严重!)"
            elif [ "$EPHEMERAL_PERCENT" -ge "$DISK_WARN_THRESHOLD" ]; then
                print_warn "  ${NODE_NAME} - ephemeral-storage使用率: ${EPHEMERAL_PERCENT}% (>=${DISK_WARN_THRESHOLD}%, 注意)"
            else
                print_ok "  ${NODE_NAME} - ephemeral-storage使用率: ${EPHEMERAL_PERCENT}%"
            fi
        fi
    fi
done

print_info ""
print_info "  [提示] 如需查看节点实际磁盘使用情况，请在节点上执行:"
print_info "  df -h"
print_info "  du -sh /var/lib/docker/* /var/lib/containerd/* /var/lib/kubelet/*"
print_info "  docker system df  (如果使用Docker)"
print_info "  crictl stats  (如果使用containerd)"

# ============================================================
# 5. 检查节点网络状态
# ============================================================
print_info ""
print_info ">>> [步骤5] 检查节点网络状态..."

echo "$NODES" | while read -r node_line; do
    NODE_NAME=$(echo "$node_line" | awk '{print $1}')

    # 获取节点IP地址
    NODE_IPS=$(kubectl get node "$NODE_NAME" -o jsonpath='{.status.addresses[*].address}' 2>/dev/null | tr ' ' '\n' || true)
    if [ -n "$NODE_IPS" ]; then
        print_info "  ${NODE_NAME} 地址:"
        echo "$NODE_IPS" | while read -r ip; do
            print_info "    $ip"
        done
    fi

    # 检查节点PodCIDR
    POD_CIDR=$(kubectl get node "$NODE_NAME" -o jsonpath='{.spec.podCIDR}' 2>/dev/null || true)
    if [ -n "$POD_CIDR" ]; then
        print_info "  ${NODE_NAME} PodCIDR: ${POD_CIDR}"
    fi
done

# 检查kube-proxy状态
print_info ""
print_info "  >> 检查kube-proxy状态..."
KUBE_PROXY=$(kubectl get pods -A --no-headers 2>/dev/null | grep -i "kube-proxy" || true)
if [ -z "$KUBE_PROXY" ]; then
    print_warn "  未找到kube-proxy Pod"
else
    echo "$KUBE_PROXY" | while read -r kp; do
        KP_STATUS=$(echo "$kp" | awk '{print $3}')
        KP_NAME=$(echo "$kp" | awk '{print $1}')
        KP_NS=$(echo "$kp" | awk '{print $2}')
        if [ "$KP_STATUS" = "Running" ]; then
            print_ok "  ${KP_NS}/${KP_NAME} - Running"
        else
            print_fail "  ${KP_NS}/${KP_NAME} - ${KP_STATUS} (异常!)"
        fi
    done
fi

# ============================================================
# 6. 检查节点系统信息(Kubelet版本等)
# ============================================================
print_info ""
print_info ">>> [步骤6] 检查集群版本信息..."

# 检查Kubernetes各组件版本
VERSION_INFO=$(kubectl version --short 2>/dev/null || kubectl version 2>/dev/null || true)
if [ -n "$VERSION_INFO" ]; then
    print_info "集群版本信息:"
    echo "$VERSION_INFO" | while read -r vline; do
        print_info "  $vline"
    done
fi

# 检查节点Kubelet版本一致性
print_info ""
print_info "  >> 检查节点Kubelet版本一致性..."
VERSIONS=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.status.nodeInfo.kubeletVersion}{"\n"}{end}' 2>/dev/null || true)
if [ -n "$VERSIONS" ]; then
    UNIQUE_VERSIONS=$(echo "$VERSIONS" | cut -d'|' -f2 | sort -u)
    VERSION_COUNT=$(echo "$UNIQUE_VERSIONS" | wc -l)
    if [ "$VERSION_COUNT" -gt 1 ]; then
        print_warn "  节点Kubelet版本不一致:"
        echo "$VERSIONS" | while read -r vline; do
            print_warn "    $(echo "$vline" | tr '|' ' ')"
        done
        print_info "  [建议] 统一所有节点的Kubernetes版本以避免兼容性问题"
    else
        print_ok "  所有节点Kubelet版本一致: $(echo "$UNIQUE_VERSIONS" | head -1)"
    fi
fi

# ============================================================
# 7. 检查节点污点和标签
# ============================================================
print_info ""
print_info ">>> [步骤7] 检查节点污点(Taints)和标签(Labels)..."

echo "$NODES" | while read -r node_line; do
    NODE_NAME=$(echo "$node_line" | awk '{print $1}')

    # 检查污点
    TAINTS=$(kubectl get node "$NODE_NAME" -o jsonpath='{.spec.taints[*].key}' 2>/dev/null | tr ' ' '\n' || true)
    if [ -n "$TAINTS" ] && [ "$TAINTS" != "" ]; then
        print_info "  ${NODE_NAME} 污点(Taints):"
        echo "$TAINTS" | while read -r taint; do
            if [ -n "$taint" ]; then
                print_warn "    $taint"
            fi
        done
    else
        print_ok "  ${NODE_NAME} 无污点(所有Pod可调度)"
    fi

    # 检查是否被封锁
    CORDONED=$(kubectl get node "$NODE_NAME" -o jsonpath='{.spec.unschedulable}' 2>/dev/null || true)
    if [ "$CORDONED" = "true" ]; then
        print_fail "  ${NODE_NAME} 已被封锁(unschedulable)，不接受新Pod"
        print_info "  [建议] 恢复调度: kubectl uncordon ${NODE_NAME}"
    fi
done

# ============================================================
# 检查总结
# ============================================================
echo ""
print_info "=========================================="
print_info "检查总结"
print_info "=========================================="

if [ "$NOT_READY_NODES" -gt 0 ]; then
    print_fail "结论: 有${NOT_READY_NODES}个节点未就绪，集群状态异常!"
else
    print_ok "结论: 所有${TOTAL_NODES}个节点均处于就绪状态"
fi

print_info ""
print_info "节点异常常见原因排查清单:"
print_info "  1. Kubelet停止     -> systemctl status kubelet / journalctl -u kubelet -f"
print_info "  2. 内存压力过大    -> MemoryPressure=True, 需清理或扩容"
print_info "  3. 磁盘空间不足    -> DiskPressure=True, 需清理磁盘"
print_info "  4. PID资源耗尽     -> PIDPressure=True, 需调整内核参数"
print_info "  5. 网络不可用      -> NetworkUnavailable=True, 检查CNI插件"
print_info "  6. 节点被封锁      -> unschedulable=true, kubectl uncordon"
print_info "  7. 版本不一致      -> 建议统一Kubernetes版本"

print_info ""
print_info "详细排查命令:"
print_info "  kubectl describe node <节点名>"
print_info "  kubectl get nodes -o wide"
print_info "  kubectl get nodes --show-labels"
print_info "  kubectl top node"
print_info "  ssh <节点名> 'df -h && free -h && uptime'"
