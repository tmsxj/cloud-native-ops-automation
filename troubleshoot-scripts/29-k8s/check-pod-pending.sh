#!/bin/bash
# 模块29-K8S故障排查脚本
# 功能: 检查Pod Pending状态，分析Pending原因并给出修复建议
# 用法: ./check-pod-pending.sh [namespace]
#   参数说明:
#     namespace  - 可选，指定命名空间，默认检查所有命名空间(-A)

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
if [ -n "$1" ]; then
    NS_ARG="-n $1"
    NAMESPACE="$1"
    print_info "指定命名空间: $1"
fi

# ============================================================
# 阈值配置
# ============================================================
# Pending Pod数量阈值
PENDING_WARN_THRESHOLD=3    # 警告阈值
PENDING_CRIT_THRESHOLD=10   # 严重阈值

print_info "=========================================="
print_info "K8S Pod Pending 状态检查"
print_info "命名空间: ${NAMESPACE}"
print_info "=========================================="

# ============================================================
# 1. 获取Pending状态的Pod列表
# ============================================================
print_info ""
print_info ">>> [步骤1] 获取Pending状态的Pod列表..."

PENDING_PODS=$(kubectl get pods ${NS_ARG} --field-selector=status.phase=Pending --no-headers 2>/dev/null)

if [ -z "$PENDING_PODS" ]; then
    print_ok "当前没有处于Pending状态的Pod"
    echo ""
    print_ok "检查完成: 集群Pod调度正常"
    exit 0
fi

# 统计Pending Pod数量
PENDING_COUNT=$(echo "$PENDING_PODS" | wc -l)

# 根据阈值判断严重程度
if [ "$PENDING_COUNT" -ge "$PENDING_CRIT_THRESHOLD" ]; then
    print_fail "发现 ${PENDING_COUNT} 个Pending Pod (>=${PENDING_CRIT_THRESHOLD}，严重!)"
elif [ "$PENDING_COUNT" -ge "$PENDING_WARN_THRESHOLD" ]; then
    print_warn "发现 ${PENDING_COUNT} 个Pending Pod (>=${PENDING_WARN_THRESHOLD}，警告)"
else
    print_warn "发现 ${PENDING_COUNT} 个Pending Pod"
fi

# 显示Pending Pod列表
echo ""
print_info "Pending Pod列表:"
echo "$PENDING_PODS" | while read -r line; do
    print_fail "  $line"
done

# ============================================================
# 2. 分析每个Pending Pod的原因
# ============================================================
print_info ""
print_info ">>> [步骤2] 分析Pending原因..."

echo "$PENDING_PODS" | while read -r pod_info; do
    # 解析Pod名和命名空间
    POD_NAME=$(echo "$pod_info" | awk '{print $1}')
    if [ "$NS_ARG" = "-A" ]; then
        POD_NS=$(echo "$pod_info" | awk '{print $2}')
    else
        POD_NS="$1"
    fi

    echo ""
    print_info "--- 分析 Pod: ${POD_NAME} (命名空间: ${POD_NS}) ---"

    # 获取Pod的Events信息来分析Pending原因
    EVENTS=$(kubectl describe pod "$POD_NAME" -n "$POD_NS" 2>/dev/null | grep -A 5 "Events:" | grep -E "Warning|Failed|Insufficient|Unschedulable|NodeAffinity|MatchInterPodAffinity|NodeSelector|PersistentVolumeClaim")

    if [ -z "$EVENTS" ]; then
        # 尝试从describe输出中获取更多信息
        REASON=$(kubectl describe pod "$POD_NAME" -n "$POD_NS" 2>/dev/null | grep -E "State:|Reason:|Message:" | tail -5)
        if [ -n "$REASON" ]; then
            echo "$REASON" | while read -r rline; do
                print_warn "  $rline"
            done
        else
            print_warn "  无法获取详细事件信息，请手动检查: kubectl describe pod ${POD_NAME} -n ${POD_NS}"
        fi
    else
        echo "$EVENTS" | while read -r event; do
            print_warn "  $event"
        done
    fi

    # ============================================================
    # 2.1 检查是否因资源不足导致Pending
    # ============================================================
    if echo "$EVENTS" | grep -qi "Insufficient"; then
        print_fail "  [原因] 节点资源不足(CPU/内存)"
        print_info "  [建议] 1. 扩容集群节点数量"
        print_info "  [建议] 2. 调整Pod的requests/limits配置"
        print_info "  [建议] 3. 检查是否有异常Pod占用过多资源"
    fi

    # ============================================================
    # 2.2 检查是否因NodeSelector/NodeAffinity导致Pending
    # ============================================================
    if echo "$EVENTS" | grep -qi "NodeSelector\|NodeAffinity\|MatchInterPodAffinity\|didn't match Pod's node affinity"; then
        print_fail "  [原因] 节点选择器/亲和性不匹配"
        print_info "  [建议] 1. 检查Pod的nodeSelector和nodeAffinity配置"
        print_info "  [建议] 2. 确认目标节点是否存在且标签匹配"
        print_info "  [建议] 3. 查看节点标签: kubectl get nodes --show-labels"
    fi

    # ============================================================
    # 2.3 检查是否因污点容忍度导致Pending
    # ============================================================
    if echo "$EVENTS" | grep -qi "Taint\|taint"; then
        print_fail "  [原因] 节点污点(Taint)导致无法调度"
        print_info "  [建议] 1. 为Pod添加对应的Toleration"
        print_info "  [建议] 2. 或修改节点的Taint配置"
        print_info "  [建议] 3. 查看节点污点: kubectl describe node <节点名> | grep Taints"
    fi

    # ============================================================
    # 2.4 检查是否因PVC导致Pending
    # ============================================================
    if echo "$EVENTS" | grep -qi "PersistentVolumeClaim\|pvc\|volume"; then
        print_fail "  [原因] 存储卷(PVC)未绑定"
        print_info "  [建议] 1. 检查PVC状态: kubectl get pvc -n ${POD_NS}"
        print_info "  [建议] 2. 检查StorageClass是否存在"
        print_info "  [建议] 3. 检查PV是否已正确创建"
    fi
done

# ============================================================
# 3. 检查节点资源概况
# ============================================================
print_info ""
print_info ">>> [步骤3] 检查集群节点资源概况..."

NODES=$(kubectl get nodes --no-headers 2>/dev/null)
if [ -z "$NODES" ]; then
    print_fail "无法获取节点列表"
else
    NODE_COUNT=$(echo "$NODES" | wc -l)
    READY_COUNT=$(echo "$NODES" | grep -c "Ready" || true)
    NOT_READY_COUNT=$((NODE_COUNT - READY_COUNT))

    print_info "总节点数: ${NODE_COUNT}, 就绪: ${READY_COUNT}, 未就绪: ${NOT_READY_COUNT}"

    if [ "$NOT_READY_COUNT" -gt 0 ]; then
        print_fail "有 ${NOT_READY_COUNT} 个节点未就绪，可能导致Pod无法调度"
    else
        print_ok "所有节点均处于就绪状态"
    fi

    # 检查是否有不可调度节点(Cordoned)
    CORDONED=$(kubectl get nodes -l '!node.kubernetes.io/unschedulable=' --no-headers 2>/dev/null | grep -c "SchedulingDisabled" || true)
    if [ "$CORDONED" -gt 0 ]; then
        print_warn "有 ${CORDONED} 个节点被标记为不可调度(SchedulingDisabled)"
        print_info "  如需恢复调度: kubectl uncordon <节点名>"
    fi

    # 显示各节点资源分配情况
    echo ""
    print_info "节点资源分配详情:"
    echo "$NODES" | while read -r node_line; do
        NODE_NAME=$(echo "$node_line" | awk '{print $1}')
        NODE_STATUS=$(echo "$node_line" | awk '{print $2}')
        # 获取节点资源分配百分比
        ALLOCATABLE=$(kubectl describe node "$NODE_NAME" 2>/dev/null | grep -A 3 "Allocated resources" | head -4)
        if [ -n "$ALLOCATABLE" ]; then
            CPU_PERCENT=$(echo "$ALLOCATABLE" | grep cpu | grep -oP '\d+(?=%)' | head -1)
            MEM_PERCENT=$(echo "$ALLOCATABLE" | grep memory | grep -oP '\d+(?=%)' | head -1)

            if [ -n "$CPU_PERCENT" ] && [ "$CPU_PERCENT" -ge 90 ]; then
                print_fail "  节点 ${NODE_NAME}: CPU分配 ${CPU_PERCENT}% (>=90%, 资源紧张)"
            elif [ -n "$CPU_PERCENT" ] && [ "$CPU_PERCENT" -ge 70 ]; then
                print_warn "  节点 ${NODE_NAME}: CPU分配 ${CPU_PERCENT}% (>=70%, 注意)"
            elif [ -n "$CPU_PERCENT" ]; then
                print_ok "  节点 ${NODE_NAME}: CPU分配 ${CPU_PERCENT}%"
            fi

            if [ -n "$MEM_PERCENT" ] && [ "$MEM_PERCENT" -ge 90 ]; then
                print_fail "  节点 ${NODE_NAME}: 内存分配 ${MEM_PERCENT}% (>=90%, 资源紧张)"
            elif [ -n "$MEM_PERCENT" ] && [ "$MEM_PERCENT" -ge 70 ]; then
                print_warn "  节点 ${NODE_NAME}: 内存分配 ${MEM_PERCENT}% (>=70%, 注意)"
            elif [ -n "$MEM_PERCENT" ]; then
                print_ok "  节点 ${NODE_NAME}: 内存分配 ${MEM_PERCENT}%"
            fi
        fi
    done
fi

# ============================================================
# 4. 检查PVC状态
# ============================================================
print_info ""
print_info ">>> [步骤4] 检查PVC状态..."

PVC_PENDING=$(kubectl get pvc ${NS_ARG} --no-headers 2>/dev/null | grep -i "Pending" || true)
if [ -z "$PVC_PENDING" ]; then
    print_ok "没有处于Pending状态的PVC"
else
    PVC_PENDING_COUNT=$(echo "$PVC_PENDING" | wc -l)
    print_fail "发现 ${PVC_PENDING_COUNT} 个Pending状态的PVC:"
    echo "$PVC_PENDING" | while read -r pvc; do
        print_fail "  $pvc"
    done
    print_info "  [建议] 1. 检查StorageClass是否配置正确"
    print_info "  [建议] 2. 检查后端存储系统是否可用"
    print_info "  [建议] 3. 查看PVC事件: kubectl describe pvc <pvc名> -n <命名空间>"
fi

# ============================================================
# 5. 检查Pod Disruption Budget (PDB)
# ============================================================
print_info ""
print_info ">>> [步骤5] 检查PodDisruptionBudget..."

PDB_LIST=$(kubectl get pdb ${NS_ARG} --no-headers 2>/dev/null || true)
if [ -z "$PDB_LIST" ]; then
    print_ok "没有配置PDB，不影响调度"
else
    print_info "当前PDB配置:"
    echo "$PDB_LIST" | while read -r pdb; do
        print_info "  $pdb"
    done
    print_info "  [提示] PDB可能阻止Pod驱逐和重新调度，请确认配置是否合理"
fi

# ============================================================
# 检查总结
# ============================================================
echo ""
print_info "=========================================="
print_info "检查总结"
print_info "=========================================="

if [ "$PENDING_COUNT" -ge "$PENDING_CRIT_THRESHOLD" ]; then
    print_fail "结论: Pending Pod数量过多(${PENDING_COUNT}个)，集群调度严重异常!"
    print_info "  紧急建议: 1.立即扩容节点 2.检查资源异常Pod 3.调整调度策略"
elif [ "$PENDING_COUNT" -ge "$PENDING_WARN_THRESHOLD" ]; then
    print_warn "结论: Pending Pod数量较多(${PENDING_COUNT}个)，需要关注"
    print_info "  建议: 1.分析Pending原因 2.评估是否需要扩容 3.优化资源分配"
else
    print_warn "结论: 有${PENDING_COUNT}个Pending Pod，建议排查原因"
fi

print_info "详细排查命令:"
print_info "  kubectl describe pod <pod名> -n <命名空间>"
print_info "  kubectl get events -n <命名空间> --sort-by=.lastTimestamp"
