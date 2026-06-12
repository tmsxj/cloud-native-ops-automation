#!/bin/bash
# ============================================================
# 模块30-中间件故障排查脚本
# 功能: ES集群健康度排查
# 用法: ./check-elasticsearch.sh [host] [port]
# 示例: ./check-elasticsearch.sh 127.0.0.1 9200
# ============================================================

# ==================== 颜色输出函数 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_info() { echo -e "[INFO] $1"; }

# ==================== 参数解析 ====================
ES_HOST="${1:-127.0.0.1}"
ES_PORT="${2:-9200}"
ES_URL="http://${ES_HOST}:${ES_PORT}"

# ==================== 统计变量 ====================
FAIL_COUNT=0
WARN_COUNT=0
OK_COUNT=0

# ==================== 分隔线 ====================
print_separator() {
    echo "============================================================"
}

# ==================== 1. 检查ES服务连通性 ====================
print_info "1. 检查Elasticsearch服务连通性..."
print_separator

ES_VERSION=$(curl -s "${ES_URL}" 2>/dev/null | grep -oP '"number"\s*:\s*"\K[^"]+' | head -1)

if [ -n "$ES_VERSION" ]; then
    print_ok "Elasticsearch连接成功 (host=${ES_HOST}, port=${ES_PORT})"
    print_info "ES版本: ${ES_VERSION}"
    ((OK_COUNT++))
else
    print_fail "无法连接Elasticsearch！请检查: 1)服务是否启动 2)端口是否正确 3)防火墙设置"
    ((FAIL_COUNT++))
    echo ""
    echo "========== 诊断结论 =========="
    print_fail "ES服务不可达，请先确保Elasticsearch正常运行"
    echo "=============================="
    exit 1
fi

# ==================== 2. 检查集群健康状态 ====================
print_info ""
print_info "2. 检查集群健康状态..."
print_separator

CLUSTER_HEALTH=$(curl -s "${ES_URL}/_cluster/health?pretty" 2>/dev/null)

CLUSTER_NAME=$(echo "$CLUSTER_HEALTH" | grep '"cluster_name"' | awk -F'"' '{print $4}')
CLUSTER_STATUS=$(echo "$CLUSTER_HEALTH" | grep '"status"' | awk -F'"' '{print $4}')
NUMBER_OF_NODES=$(echo "$CLUSTER_HEALTH" | grep '"number_of_nodes"' | awk '{print $3}' | tr -d ',')
NUMBER_OF_DATA_NODES=$(echo "$CLUSTER_HEALTH" | grep '"number_of_data_nodes"' | awk '{print $3}' | tr -d ',')
ACTIVE_PRIMARY_SHARDS=$(echo "$CLUSTER_HEALTH" | grep '"active_primary_shards"' | awk '{print $3}' | tr -d ',')
ACTIVE_SHARDS=$(echo "$CLUSTER_HEALTH" | grep '"active_shards"' | awk '{print $3}' | tr -d ',')
RELOCATING_SHARDS=$(echo "$CLUSTER_HEALTH" | grep '"relocating_shards"' | awk '{print $3}' | tr -d ',')
INITIALIZING_SHARDS=$(echo "$CLUSTER_HEALTH" | grep '"initializing_shards"' | awk '{print $3}' | tr -d ',')
UNASSIGNED_SHARDS=$(echo "$CLUSTER_HEALTH" | grep '"unassigned_shards"' | awk '{print $3}' | tr -d ',')
PENDING_TASKS=$(echo "$CLUSTER_HEALTH" | grep '"number_of_pending_tasks"' | awk '{print $3}' | tr -d ',')

print_info "集群名称: ${CLUSTER_NAME}"
print_info "集群状态: ${CLUSTER_STATUS}"
print_info "节点数: ${NUMBER_OF_NODES} (数据节点: ${NUMBER_OF_DATA_NODES})"
print_info "活跃主分片: ${ACTIVE_PRIMARY_SHARDS}"
print_info "活跃分片总数: ${ACTIVE_SHARDS}"
print_info "正在迁移分片: ${RELOCATING_SHARDS}"
print_info "初始化中分片: ${INITIALIZING_SHARDS}"
print_info "未分配分片: ${UNASSIGNED_SHARDS}"
print_info "待处理任务: ${PENDING_TASKS}"

# 根据状态判断
case "$CLUSTER_STATUS" in
    "green")
        print_ok "集群状态为GREEN，一切正常"
        ((OK_COUNT++))
        ;;
    "yellow")
        print_warn "集群状态为YELLOW，存在未分配的副本分片"
        print_info "建议: 1)检查副本分片分配情况 2)确认数据节点数量是否足够"
        ((WARN_COUNT++))
        ;;
    "red")
        print_fail "集群状态为RED，存在未分配的主分片，部分数据不可用！"
        print_info "建议: 1)立即检查未分配分片原因 2)检查节点是否离线 3)检查磁盘空间"
        ((FAIL_COUNT++))
        ;;
    *)
        print_fail "无法获取集群状态"
        ((FAIL_COUNT++))
        ;;
esac

# 检查待处理任务
if [ -n "$PENDING_TASKS" ] && [ "$PENDING_TASKS" -gt 0 ]; then
    print_warn "集群存在 ${PENDING_TASKS} 个待处理任务，可能影响集群性能"
    ((WARN_COUNT++))
else
    print_ok "无待处理任务"
    ((OK_COUNT++))
fi

# ==================== 3. 检查节点状态 ====================
print_info ""
print_info "3. 检查节点状态..."
print_separator

NODES_INFO=$(curl -s "${ES_URL}/_cat/nodes?v&h=ip,name,node.role,heap.percent,ram.percent,cpu,load_1m,disk.total,disk.used_percent" 2>/dev/null)

if [ -n "$NODES_INFO" ]; then
    echo "$NODES_INFO"
    echo ""

    # 检查节点磁盘使用率
    DISK_HIGH=$(echo "$NODES_INFO" | awk 'NR>1 {if ($9+0 > 85) print $0}')
    if [ -n "$DISK_HIGH" ]; then
        print_fail "以下节点磁盘使用率超过85%，可能触发只读模式:"
        echo "$DISK_HIGH" | while read -r line; do
            print_info "  $line"
        done
        ((FAIL_COUNT++))
    else
        print_ok "所有节点磁盘使用率正常"
        ((OK_COUNT++))
    fi

    # 检查堆内存使用率
    HEAP_HIGH=$(echo "$NODES_INFO" | awk 'NR>1 {if ($4+0 > 85) print $0}')
    if [ -n "$HEAP_HIGH" ]; then
        print_warn "以下节点JVM堆内存使用率超过85%:"
        echo "$HEAP_HIGH" | while read -r line; do
            print_info "  $line"
        done
        ((WARN_COUNT++))
    else
        print_ok "所有节点JVM堆内存使用率正常"
        ((OK_COUNT++))
    fi
else
    print_warn "无法获取节点信息"
    ((WARN_COUNT++))
fi

# ==================== 4. 检查未分配分片详情 ====================
print_info ""
print_info "4. 检查未分配分片..."
print_separator

if [ "$UNASSIGNED_SHARDS" -gt 0 ]; then
    print_fail "存在 ${UNASSIGNED_SHARDS} 个未分配分片！"

    # 获取未分配分片详情
    UNASSIGNED_DETAIL=$(curl -s "${ES_URL}/_cat/shards?v" 2>/dev/null | grep "UNASSIGNED")
    if [ -n "$UNASSIGNED_DETAIL" ]; then
        echo ""
        echo "未分配分片详情:"
        echo "$UNASSIGNED_DETAIL" | head -20
    fi

    # 尝试获取未分配原因
    echo ""
    print_info "尝试获取未分配原因..."
    UNASSIGNED_REASON=$(curl -s "${ES_URL}/_cluster/allocation/explain?pretty" 2>/dev/null | grep -E '"explanation"|"decisions"' | head -5)
    if [ -n "$UNASSIGNED_REASON" ]; then
        echo "$UNASSIGNED_REASON" | while read -r line; do
            print_info "  $line"
        done
    fi

    print_info "建议: 1)检查磁盘水位线 2)检查节点是否离线 3)检查分片分配感知配置"
    ((FAIL_COUNT++))
else
    print_ok "无未分配分片"
    ((OK_COUNT++))
fi

# ==================== 5. 检查磁盘水位线 ====================
print_info ""
print_info "5. 检查磁盘水位线..."
print_separator

ALLOCATION_INFO=$(curl -s "${ES_URL}/_cat/allocation?v" 2>/dev/null)

if [ -n "$ALLOCATION_INFO" ]; then
    echo "$ALLOCATION_INFO"
    echo ""

    # 检查是否有节点达到flood stage
    FLOOD_STAGE=$(echo "$ALLOCATION_INFO" | awk 'NR>1 {if ($5+0 > 95) print $0}')
    if [ -n "$FLOOD_STAGE" ]; then
        print_fail "以下节点磁盘超过flood-stage水位线(95%)，索引将被设为只读！"
        echo "$FLOOD_STAGE" | while read -r line; do
            print_info "  $line"
        done
        print_info "紧急修复: curl -X PUT '${ES_URL}/_all/_settings' -d '{\"index.blocks.read_only_allow_delete\": null}'"
        ((FAIL_COUNT++))
    else
        # 检查high watermark
        HIGH_WM=$(echo "$ALLOCATION_INFO" | awk 'NR>1 {if ($4+0 > 90) print $0}')
        if [ -n "$HIGH_WM" ]; then
            print_warn "以下节点磁盘超过high水位线(90%)，不再分配新分片:"
            echo "$HIGH_WM" | while read -r line; do
                print_info "  $line"
            done
            ((WARN_COUNT++))
        else
            print_ok "磁盘水位线正常，所有节点在安全范围内"
            ((OK_COUNT++))
        fi
    fi
else
    print_warn "无法获取磁盘分配信息"
    ((WARN_COUNT++))
fi

# ==================== 6. 检查索引状态 ====================
print_info ""
print_info "6. 检查索引状态..."
print_separator"

# 获取索引列表及状态
INDICES_INFO=$(curl -s "${ES_URL}/_cat/indices?v&h=health,status,index,pri,rep,docs.count,store.size&health=red,yellow" 2>/dev/null)

if [ -n "$INDICES_INFO" ]; then
    RED_INDICES=$(echo "$INDICES_INFO" | awk '$1=="red"' | wc -l)
    YELLOW_INDICES=$(echo "$INDICES_INFO" | awk '$1=="yellow"' | wc -l)

    if [ "$RED_INDICES" -gt 0 ]; then
        print_fail "存在 ${RED_INDICES} 个RED状态索引:"
        echo "$INDICES_INFO" | awk '$1=="red"' | head -10
        ((FAIL_COUNT++))
    else
        print_ok "无RED状态索引"
        ((OK_COUNT++))
    fi

    if [ "$YELLOW_INDICES" -gt 0 ]; then
        print_warn "存在 ${YELLOW_INDICES} 个YELLOW状态索引:"
        echo "$INDICES_INFO" | awk '$1=="yellow"' | head -10
        ((WARN_COUNT++))
    else
        print_ok "无YELLOW状态索引"
        ((OK_COUNT++))
    fi
else
    print_info "所有索引状态正常"
    ((OK_COUNT++))
fi

# ==================== 7. 检查慢日志 ====================
print_info ""
print_info "7. 检查索引慢查询日志..."
print_separator"

SLOWLOG_QUERY=$(curl -s "${ES_URL}/_cat/indices?v&h=index" 2>/dev/null | awk 'NR>1 {print $1}' | head -3)

for idx in $SLOWLOG_QUERY; do
    SLOWLOG=$(curl -s "${ES_URL}/${idx}/_stats?pretty" 2>/dev/null | grep -A2 "search" | head -5)
    if [ -n "$SLOWLOG" ]; then
        print_info "索引 [${idx}] 搜索统计:"
        echo "$SLOWLOG"
    fi
done

# 检查慢日志配置
SLOWLOG_THRESHOLD=$(curl -s "${ES_URL}/_cluster/settings?include_defaults=true&flat_settings=true&filter_path=*.index.search.slowlog.threshold.query.warn" 2>/dev/null)
if [ -n "$SLOWLOG_THRESHOLD" ]; then
    print_info "慢查询日志阈值配置: ${SLOWLOG_THRESHOLD}"
fi

print_ok "慢日志检查完成"
((OK_COUNT++))

# ==================== 8. 检查线程池 ====================
print_info ""
print_info "8. 检查线程池状态..."
print_separator

THREAD_POOL=$(curl -s "${ES_URL}/_cat/thread_pool?v&h=name,active,queue,rejected,core,max" 2>/dev/null | grep -E "search|write|bulk")

if [ -n "$THREAD_POOL" ]; then
    echo "$THREAD_POOL"
    echo ""

    # 检查是否有rejected
    REJECTED=$(echo "$THREAD_POOL" | awk 'NR>1 {if ($4+0 > 0) print $0}')
    if [ -n "$REJECTED" ]; then
        print_fail "以下线程池存在拒绝请求(rejected)，说明集群处理能力不足:"
        echo "$REJECTED" | while read -r line; do
            print_info "  $line"
        done
        print_info "建议: 1)增加节点 2)优化查询 3)调整线程池配置"
        ((FAIL_COUNT++))
    else
        print_ok "线程池运行正常，无拒绝请求"
        ((OK_COUNT++))
    fi
else
    print_warn "无法获取线程池信息"
    ((WARN_COUNT++))
fi

# ==================== 诊断结论汇总 ====================
echo ""
print_separator
echo ""
echo "==================== Elasticsearch诊断结论汇总 ===================="
echo ""

TOTAL_CHECKS=$((OK_COUNT + WARN_COUNT + FAIL_COUNT))

echo -e "总检查项: ${TOTAL_CHECKS}  |  ${GREEN}正常: ${OK_COUNT}${NC}  |  ${YELLOW}警告: ${WARN_COUNT}${NC}  |  ${RED}异常: ${FAIL_COUNT}${NC}"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
    print_fail "ES集群存在 ${FAIL_COUNT} 个严重问题，需要立即处理！"
    echo ""
    print_info "常见修复方案:"
    echo "  1. RED状态 -> 检查未分配分片，修复节点，清理磁盘空间"
    echo "  2. 磁盘满 -> 清理旧索引，扩容磁盘，解除只读模式"
    echo "  3. 线程池拒绝 -> 扩容节点，优化查询和写入"
    echo "  4. 堆内存高 -> 调整JVM堆大小，优化查询复杂度"
elif [ "$WARN_COUNT" -gt 0 ]; then
    print_warn "ES集群存在 ${WARN_COUNT} 个警告项，建议持续关注"
    echo ""
    print_info "建议定期执行本脚本进行健康检查"
else
    print_ok "ES集群各项指标正常，运行健康"
fi

echo ""
print_separator
