#!/bin/bash
# 模块29-K8S故障排查脚本
# 功能: 检查Pod频繁重启，分析重启原因(OOMKilled/探针失败/崩溃等)并给出修复建议
# 用法: ./check-pod-restart.sh [namespace] [pod名称关键词]
#   参数说明:
#     namespace      - 可选，指定命名空间，默认检查所有命名空间(-A)
#     pod名称关键词  - 可选，过滤特定Pod名称(模糊匹配)

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
POD_FILTER=""

if [ -n "$1" ]; then
    NS_ARG="-n $1"
    NAMESPACE="$1"
    print_info "指定命名空间: $1"
fi

if [ -n "$2" ]; then
    POD_FILTER="$2"
    print_info "过滤Pod名称关键词: $2"
fi

# ============================================================
# 阈值配置
# ============================================================
RESTART_WARN_THRESHOLD=5     # 重启次数警告阈值
RESTART_CRIT_THRESHOLD=20    # 重启次数严重阈值
RESTART_RATE_WARN=3         # 最近1小时内重启次数警告阈值

print_info "=========================================="
print_info "K8S Pod 频繁重启检查"
print_info "命名空间: ${NAMESPACE}"
if [ -n "$POD_FILTER" ]; then
    print_info "Pod过滤: ${POD_FILTER}"
fi
print_info "=========================================="

# ============================================================
# 1. 获取重启次数最多的Pod列表
# ============================================================
print_info ""
print_info ">>> [步骤1] 获取重启次数最多的Pod列表..."

# 使用kubectl获取Pod列表并按重启次数排序
ALL_PODS=$(kubectl get pods ${NS_ARG} -o json 2>/dev/null)

if [ -z "$ALL_PODS" ] || echo "$ALL_PODS" | grep -q "error"; then
    print_fail "无法获取Pod列表，请检查kubeconfig配置"
    exit 1
fi

# 提取有重启记录的Pod信息
RESTART_PODS=$(kubectl get pods ${NS_ARG} -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{range .status.containerStatuses[*]}{.name}{"="}{.restartCount}{";"}{end}{"\n"}{end}' 2>/dev/null)

if [ -z "$RESTART_PODS" ]; then
    print_ok "当前没有Pod重启记录"
    echo ""
    print_ok "检查完成: 所有Pod运行稳定"
    exit 0
fi

# 解析并按重启次数排序
declare -A POD_RESTART_MAP
declare -A POD_NS_MAP
MAX_RESTART=0

while IFS= read -r line; do
    if [ -z "$line" ]; then
        continue
    fi
    NS=$(echo "$line" | cut -d'|' -f1)
    POD=$(echo "$line" | cut -d'|' -f2)
    CONTAINERS=$(echo "$line" | cut -d'|' -f3)

    # 应用Pod名称过滤
    if [ -n "$POD_FILTER" ]; then
        if ! echo "$POD" | grep -qi "$POD_FILTER"; then
            continue
        fi
    fi

    TOTAL_RESTART=0
    IFS=';' read -ra CONT_ARRAY <<< "$CONTAINERS"
    for cont_info in "${CONT_ARRAY[@]}"; do
        if [ -z "$cont_info" ]; then
            continue
        fi
        RESTART_COUNT=$(echo "$cont_info" | grep -oP '\d+$')
        TOTAL_RESTART=$((TOTAL_RESTART + RESTART_COUNT))
    done

    if [ "$TOTAL_RESTART" -gt 0 ]; then
        KEY="${NS}/${POD}"
        POD_RESTART_MAP[$KEY]=$TOTAL_RESTART
        POD_NS_MAP[$KEY]="$CONTAINERS"
        if [ "$TOTAL_RESTART" -gt "$MAX_RESTART" ]; then
            MAX_RESTART=$TOTAL_RESTART
        fi
    fi
done <<< "$RESTART_PODS"

# 检查是否有需要关注的Pod
if [ ${#POD_RESTART_MAP[@]} -eq 0 ]; then
    print_ok "没有发现重启的Pod"
    echo ""
    print_ok "检查完成: 所有Pod运行稳定"
    exit 0
fi

# 按重启次数排序输出
print_info "重启Pod列表(按重启次数排序):"
echo ""

PROBLEM_COUNT=0
for KEY in $(for k in "${!POD_RESTART_MAP[@]}"; do echo "$k ${POD_RESTART_MAP[$k]}"; done | sort -t' ' -k2 -rn | cut -d' ' -f1); do
    RESTART=${POD_RESTART_MAP[$KEY]}
    CONTAINERS=${POD_NS_MAP[$KEY]}

    if [ "$RESTART" -ge "$RESTART_CRIT_THRESHOLD" ]; then
        print_fail "  ${KEY} - 总重启次数: ${RESTART} (>=${RESTART_CRIT_THRESHOLD}，严重!)"
        PROBLEM_COUNT=$((PROBLEM_COUNT + 1))
    elif [ "$RESTART" -ge "$RESTART_WARN_THRESHOLD" ]; then
        print_warn "  ${KEY} - 总重启次数: ${RESTART} (>=${RESTART_WARN_THRESHOLD}，警告)"
        PROBLEM_COUNT=$((PROBLEM_COUNT + 1))
    else
        print_info "  ${KEY} - 总重启次数: ${RESTART}"
    fi

    # 显示各容器重启详情
    IFS=';' read -ra CONT_ARRAY <<< "$CONTAINERS"
    for cont_info in "${CONT_ARRAY[@]}"; do
        if [ -n "$cont_info" ]; then
            print_info "    容器: $cont_info"
        fi
    done
done

# ============================================================
# 2. 深入分析重启原因
# ============================================================
print_info ""
print_info ">>> [步骤2] 深入分析重启原因..."

for KEY in $(for k in "${!POD_RESTART_MAP[@]}"; do echo "$k ${POD_RESTART_MAP[$k]}"; done | sort -t' ' -k2 -rn | cut -d' ' -f1); do
    RESTART=${POD_RESTART_MAP[$KEY]}
    NS=$(echo "$KEY" | cut -d'/' -f1)
    POD=$(echo "$KEY" | cut -d'/' -f2)

    # 只分析重启次数超过警告阈值的Pod
    if [ "$RESTART" -lt "$RESTART_WARN_THRESHOLD" ]; then
        continue
    fi

    echo ""
    print_info "--- 分析 Pod: ${POD} (命名空间: ${NS}, 重启: ${RESTART}次) ---"

    # ----------------------------------------------------------
    # 2.1 检查OOMKilled (内存溢出)
    # ----------------------------------------------------------
    print_info "  >> 检查OOMKilled..."
    OOM_CHECK=$(kubectl describe pod "$POD" -n "$NS" 2>/dev/null | grep -i "OOMKilled\|Out of memory\|OOM")
    if [ -n "$OOM_CHECK" ]; then
        print_fail "  [原因] 容器因内存溢出(OOMKilled)被杀死"
        echo "$OOM_CHECK" | while read -r oom_line; do
            print_fail "    $oom_line"
        done
        print_info "  [建议] 1. 增加容器的内存limit: resources.limits.memory"
        print_info "  [建议] 2. 检查应用是否存在内存泄漏"
        print_info "  [建议] 3. 使用heap dump分析内存使用情况"
        print_info "  [建议] 4. 临时方案: kubectl top pod ${POD} -n ${NS} 查看实际内存用量"
    else
        print_ok "  未检测到OOMKilled"
    fi

    # ----------------------------------------------------------
    # 2.2 检查Liveness/Readiness探针失败
    # ----------------------------------------------------------
    print_info "  >> 检查探针(Probe)配置..."
    PROBE_YAML=$(kubectl get pod "$POD" -n "$NS" -o yaml 2>/dev/null | grep -A 10 "livenessProbe\|readinessProbe\|startupProbe" || true)
    if [ -n "$PROBE_YAML" ]; then
        # 检查探针事件
        PROBE_EVENTS=$(kubectl describe pod "$POD" -n "$NS" 2>/dev/null | grep -i "Liveness\|Readiness\|probe\|health" | grep -i "failed\|error\|timeout" || true)
        if [ -n "$PROBE_EVENTS" ]; then
            print_fail "  [原因] 健康检查探针失败导致容器重启"
            echo "$PROBE_EVENTS" | while read -r pe; do
                print_warn "    $pe"
            done
            print_info "  [建议] 1. 检查探针配置是否合理(路径/端口/超时时间)"
            print_info "  [建议] 2. 增大initialDelaySeconds和timeoutSeconds"
            print_info "  [建议] 3. 增大failureThreshold避免偶发失败导致重启"
            print_info "  [建议] 4. 进入容器手动检查健康端点: kubectl exec -it ${POD} -n ${NS} -- curl localhost:<端口>/<路径>"
        else
            print_ok "  探针配置正常，未发现探针失败事件"
        fi
    else
        print_info "  未配置健康检查探针"
    fi

    # ----------------------------------------------------------
    # 2.3 检查容器退出状态码
    # ----------------------------------------------------------
    print_info "  >> 检查容器退出状态码..."
    EXIT_CODE=$(kubectl describe pod "$POD" -n "$NS" 2>/dev/null | grep -E "Exit Code|exit code|Last State|State:" | head -10)
    if [ -n "$EXIT_CODE" ]; then
        echo "$EXIT_CODE" | while read -r ec; do
            if echo "$ec" | grep -q "137"; then
                print_fail "    退出码137: 容器被SIGKILL杀死(可能是OOM或手动kill)"
            elif echo "$ec" | grep -q "1"; then
                print_warn "    退出码1: 应用程序错误退出"
            elif echo "$ec" | grep -q "0"; then
                print_ok "    退出码0: 正常退出"
            else
                print_info "    $ec"
            fi
        done
    else
        print_info "  未获取到退出状态码信息"
    fi

    # ----------------------------------------------------------
    # 2.4 检查容器日志(最近错误)
    # ----------------------------------------------------------
    print_info "  >> 检查容器最近日志(最后20行)..."
    LAST_LOGS=$(kubectl logs "$POD" -n "$NS" --tail=20 2>/dev/null || true)
    if [ -n "$LAST_LOGS" ]; then
        # 检查日志中是否有错误关键字
        ERROR_LOGS=$(echo "$LAST_LOGS" | grep -iE "error|exception|fatal|panic|crash|stacktrace|timeout" || true)
        if [ -n "$ERROR_LOGS" ]; then
            print_fail "  [原因] 容器日志中发现错误信息:"
            echo "$ERROR_LOGS" | head -5 | while read -r err; do
                print_warn "    $err"
            done
            print_info "  [建议] 查看完整日志: kubectl logs ${POD} -n ${NS} --previous"
        else
            print_ok "  容器日志中未发现明显错误"
        fi
    else
        print_warn "  无法获取容器日志"
    fi

    # ----------------------------------------------------------
    # 2.5 检查资源使用情况
    # ----------------------------------------------------------
    print_info "  >> 检查资源使用情况..."
    RESOURCE_USAGE=$(kubectl top pod "$POD" -n "$NS" --no-headers 2>/dev/null || true)
    if [ -n "$RESOURCE_USAGE" ]; then
        print_info "  资源使用: $RESOURCE_USAGE"
        # 检查是否接近limit
        CPU_USAGE=$(echo "$RESOURCE_USAGE" | awk '{print $2}' | grep -oP '\d+' | head -1)
        MEM_USAGE=$(echo "$RESOURCE_USAGE" | awk '{print $3}' | grep -oP '\d+' | head -1)
        if [ -n "$MEM_USAGE" ] && [ "$MEM_USAGE" -ge 900 ]; then
            print_warn "  内存使用较高(${MEM_USAGE}Mi)，接近limit可能导致OOM"
        fi
    else
        print_warn "  无法获取资源使用数据(metrics-server可能未安装)"
    fi
done

# ============================================================
# 3. 检查最近1小时内重启频率
# ============================================================
print_info ""
print_info ">>> [步骤3] 检查最近重启频率..."

RECENT_RESTART_PODS=$(kubectl get pods ${NS_ARG} -o json 2>/dev/null | python3 -c "
import json, sys
from datetime import datetime, timedelta, timezone

data = json.load(sys.stdin)
one_hour_ago = datetime.now(timezone.utc) - timedelta(hours=1)
results = []

for pod in data.get('items', []):
    ns = pod['metadata']['namespace']
    name = pod['metadata']['name']
    for cs in (pod.get('status', {}).get('containerStatuses', []) or []):
        if cs.get('lastState', {}).get('terminated', {}).get('finishedAt'):
            finished = cs['lastState']['terminated']['finishedAt']
            try:
                t = datetime.fromisoformat(finished.replace('Z', '+00:00'))
                if t > one_hour_ago:
                    results.append(f'{ns}/{name} - 容器:{cs[\"name\"]} 最后退出时间:{finished} 退出码:{cs[\"lastState\"][\"terminated\"][\"exitCode\"]}')
            except:
                pass
        # 检查restartCount和containerID变化
        restart_count = cs.get('restartCount', 0)
        if restart_count >= 3:
            results.append(f'{ns}/{name} - 容器:{cs[\"name\"]} 累计重启:{restart_count}次')

for r in sorted(set(results)):
    print(r)
" 2>/dev/null || true)

if [ -n "$RECENT_RESTART_PODS" ]; then
    print_warn "最近1小时内有频繁重启的Pod:"
    echo "$RECENT_RESTART_PODS" | while read -r rp; do
        print_warn "  $rp"
    done
else
    print_ok "最近1小时内未检测到频繁重启"
fi

# ============================================================
# 检查总结
# ============================================================
echo ""
print_info "=========================================="
print_info "检查总结"
print_info "=========================================="

if [ "$PROBLEM_COUNT" -gt 0 ]; then
    if [ "$MAX_RESTART" -ge "$RESTART_CRIT_THRESHOLD" ]; then
        print_fail "结论: 发现Pod严重频繁重启(最高${MAX_RESTART}次)，需要立即处理!"
    else
        print_warn "结论: 发现${PROBLEM_COUNT}个Pod重启次数较多，需要关注"
    fi
    print_info ""
    print_info "常见重启原因排查清单:"
    print_info "  1. OOMKilled    -> 增大内存limit或修复内存泄漏"
    print_info "  2. 探针失败     -> 调整探针参数(initialDelaySeconds/timeoutSeconds)"
    print_info "  3. 应用崩溃     -> 查看应用日志和stacktrace"
    print_info "  4. 资源限制     -> 检查CPU/内存limit是否合理"
    print_info "  5. 配置错误     -> 检查ConfigMap/Secret挂载是否正确"
else
    print_ok "结论: 所有Pod重启次数在正常范围内"
fi

print_info ""
print_info "详细排查命令:"
print_info "  kubectl describe pod <pod名> -n <命名空间>"
print_info "  kubectl logs <pod名> -n <命名空间> --previous"
print_info "  kubectl top pod <pod名> -n <命名空间>"
