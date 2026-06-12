#!/bin/bash
# ============================================================
# 模块30-中间件故障排查脚本
# 功能: Redis内存溢出与主从切换排查
# 用法: ./check-redis.sh [host] [port]
# 示例: ./check-redis.sh 127.0.0.1 6379
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
REDIS_HOST="${1:-127.0.0.1}"
REDIS_PORT="${2:-6379}"

REDIS_CLI="redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT}"

# ==================== 统计变量 ====================
FAIL_COUNT=0
WARN_COUNT=0
OK_COUNT=0

# ==================== 分隔线 ====================
print_separator() {
    echo "============================================================"
}

# ==================== 1. 检查Redis进程状态 ====================
print_info "1. 检查Redis进程状态..."
print_separator

# 通过redis-cli ping检查
PING_RESULT=$($REDIS_CLI ping 2>/dev/null)

if [ "$PING_RESULT" = "PONG" ]; then
    print_ok "Redis服务响应正常 (host=${REDIS_HOST}, port=${REDIS_PORT})"
    ((OK_COUNT++))
else
    # 尝试通过进程检查
    if pgrep -x "redis-server" > /dev/null 2>&1; then
        print_warn "Redis进程存在但无法连接 (host=${REDIS_HOST}, port=${REDIS_PORT})"
        ((WARN_COUNT++))
    else
        print_fail "Redis服务未运行！请检查redis-server进程"
        ((FAIL_COUNT++))
        echo ""
        echo "========== 诊断结论 =========="
        print_fail "Redis服务未启动，请执行: systemctl start redis"
        echo "=============================="
        exit 1
    fi
fi

# ==================== 2. 检查Redis版本信息 ====================
print_info ""
print_info "2. 检查Redis版本信息..."
print_separator

REDIS_VERSION=$($REDIS_CLI INFO server 2>/dev/null | grep "redis_version:" | cut -d: -f2 | tr -d '\r')
REDIS_UPTIME=$($REDIS_CLI INFO server 2>/dev/null | grep "uptime_in_seconds:" | cut -d: -f2 | tr -d '\r')
REDIS_UPTIME_DAYS=$((REDIS_UPTIME / 86400))

if [ -n "$REDIS_VERSION" ]; then
    print_info "Redis版本: ${REDIS_VERSION}"
    print_info "运行时间: ${REDIS_UPTIME}秒 (约${REDIS_UPTIME_DAYS}天)"
    print_ok "版本信息获取成功"
    ((OK_COUNT++))
else
    print_warn "无法获取Redis版本信息"
    ((WARN_COUNT++))
fi

# ==================== 3. 检查内存使用情况 ====================
print_info ""
print_info "3. 检查内存使用情况..."
print_separator

# 获取内存信息
USED_MEMORY=$($REDIS_CLI INFO memory 2>/dev/null | grep "used_memory_human:" | cut -d: -f2 | tr -d '\r')
USED_MEMORY_PEAK=$($REDIS_CLI INFO memory 2>/dev/null | grep "used_memory_peak_human:" | cut -d: -f2 | tr -d '\r')
USED_MEMORY_RSS=$($REDIS_CLI INFO memory 2>/dev/null | grep "used_memory_rss_human:" | cut -d: -f2 | tr -d '\r')
MAXMEMORY=$($REDIS_CLI INFO memory 2>/dev/null | grep "maxmemory_human:" | cut -d: -f2 | tr -d '\r')
MAXMEMORY_POLICY=$($REDIS_CLI INFO memory 2>/dev/null | grep "maxmemory_policy:" | cut -d: -f2 | tr -d '\r')
MEM_FRAGMENTATION_RATIO=$($REDIS_CLI INFO memory 2>/dev/null | grep "mem_fragmentation_ratio:" | cut -d: -f2 | tr -d '\r')

print_info "已用内存: ${USED_MEMORY}"
print_info "峰值内存: ${USED_MEMORY_PEAK}"
print_info "RSS内存: ${USED_MEMORY_RSS}"
print_info "最大内存限制: ${MAXMEMORY}"
print_info "淘汰策略: ${MAXMEMORY_POLICY}"
print_info "内存碎片率: ${MEM_FRAGMENTATION_RATIO}"

# 判断内存使用率
if [ "$MAXMEMORY" = "0" ] || [ -z "$MAXMEMORY" ]; then
    print_warn "未设置maxmemory限制！建议在生产环境中设置内存上限，防止OOM"
    ((WARN_COUNT++))
else
    # 提取数值进行比较
    USED_MEMORY_BYTES=$($REDIS_CLI INFO memory 2>/dev/null | grep "^used_memory:" | cut -d: -f2 | tr -d '\r')
    MAXMEMORY_BYTES=$($REDIS_CLI INFO memory 2>/dev/null | grep "^maxmemory:" | cut -d: -f2 | tr -d '\r')

    if [ -n "$USED_MEMORY_BYTES" ] && [ -n "$MAXMEMORY_BYTES" ] && [ "$MAXMEMORY_BYTES" -gt 0 ]; then
        MEM_RATIO=$((USED_MEMORY_BYTES * 100 / MAXMEMORY_BYTES))
        print_info "内存使用率: ${MEM_RATIO}%"

        if [ "$MEM_RATIO" -ge 90 ]; then
            print_fail "内存使用率超过90%！即将触发淘汰策略，可能导致数据丢失"
            print_info "建议: 1)扩容内存 2)清理无用Key 3)优化数据结构 4)检查是否有内存泄漏"
            ((FAIL_COUNT++))
        elif [ "$MEM_RATIO" -ge 70 ]; then
            print_warn "内存使用率超过70%，需要关注"
            ((WARN_COUNT++))
        else
            print_ok "内存使用率正常"
            ((OK_COUNT++))
        fi
    fi
fi

# 判断内存碎片率
if [ -n "$MEM_FRAGMENTATION_RATIO" ]; then
    # 提取整数部分
    FRAG_INT=${MEM_FRAGMENTATION_RATIO%.*}
    if [ "$FRAG_INT" -gt 15 ]; then
        print_fail "内存碎片率过高 (${MEM_FRAGMENTATION_RATIO})，浪费内存严重"
        print_info "建议: 执行 MEMORY PURGE 或重启Redis实例"
        ((FAIL_COUNT++))
    elif [ "$FRAG_INT" -gt 10 ]; then
        print_warn "内存碎片率偏高 (${MEM_FRAGMENTATION_RATIO})，建议关注"
        ((WARN_COUNT++))
    else
        print_ok "内存碎片率正常 (${MEM_FRAGMENTATION_RATIO})"
        ((OK_COUNT++))
    fi
fi

# ==================== 4. 检查大Key ====================
print_info ""
print_info "4. 检查大Key..."
print_separator

# 使用--bigkeys扫描
BIGKEYS_RESULT=$($REDIS_CLI --bigkeys -i 0.1 2>&1)
BIGKEYS_BIGGEST=$($REDIS_CLI --bigkeys -i 0.1 2>&1 | grep "Biggest" | tail -5)

if [ -n "$BIGKEYS_BIGGEST" ]; then
    echo "$BIGKEYS_BIGGEST" | while read -r line; do
        print_info "$line"
    done

    # 检查是否存在超过1MB的Key
    HAS_HUGE_KEY=$(echo "$BIGKEYS_RESULT" | grep -i "1.*MB\|2.*MB\|5.*MB\|10.*MB")
    if [ -n "$HAS_HUGE_KEY" ]; then
        print_warn "发现大Key (超过1MB)，可能导致阻塞或网络延迟"
        print_info "建议: 1)拆分大Key 2)使用HASH结构替代STRING 3)避免使用KEYS命令"
        ((WARN_COUNT++))
    else
        print_ok "未发现超大Key"
        ((OK_COUNT++))
    fi
else
    print_warn "无法扫描大Key (可能需要较长时间，跳过)"
    ((WARN_COUNT++))
fi

# ==================== 5. 检查主从复制状态 ====================
print_info ""
print_info "5. 检查主从复制状态..."
print_separator

ROLE=$($REDIS_CLI INFO replication 2>/dev/null | grep "role:" | cut -d: -f2 | tr -d '\r')

if [ "$ROLE" = "master" ]; then
    print_info "当前角色: 主节点 (master)"

    # 获取从节点信息
    CONNECTED_SLAVES=$($REDIS_CLI INFO replication 2>/dev/null | grep "connected_slaves:" | cut -d: -f2 | tr -d '\r')
    print_info "已连接从节点数: ${CONNECTED_SLAVES}"

    if [ "$CONNECTED_SLAVES" -eq 0 ]; then
        print_warn "无从节点连接，高可用架构缺失"
        ((WARN_COUNT++))
    else
        # 检查每个从节点的状态
        SLAVE_INFO=$($REDIS_CLI INFO replication 2>/dev/null | grep -E "slave[0-9]+:" | head -10)
        if [ -n "$SLAVE_INFO" ]; then
            echo "$SLAVE_INFO" | while read -r line; do
                print_info "$line"
            done
        fi

        # 检查从节点延迟
        SLAVE_LAG=$($REDIS_CLI INFO replication 2>/dev/null | grep "slave0:lag=" | grep -oP 'lag=\K[0-9]+' | head -1)
        if [ -n "$SLAVE_LAG" ] && [ "$SLAVE_LAG" -gt 10 ]; then
            print_fail "从节点复制延迟过大 (lag=${SLAVE_LAG})，主从数据不一致风险高"
            ((FAIL_COUNT++))
        else
            print_ok "从节点复制状态正常"
            ((OK_COUNT++))
        fi
    fi

elif [ "$ROLE" = "slave" ]; then
    print_info "当前角色: 从节点 (slave)"

    MASTER_LINK_STATUS=$($REDIS_CLI INFO replication 2>/dev/null | grep "master_link_status:" | cut -d: -f2 | tr -d '\r')
    MASTER_HOST=$($REDIS_CLI INFO replication 2>/dev/null | grep "master_host:" | cut -d: -f2 | tr -d '\r')
    MASTER_PORT=$($REDIS_CLI INFO replication 2>/dev/null | grep "master_port:" | cut -d: -f2 | tr -d '\r')
    MASTER_REPL_OFFSET=$($REDIS_CLI INFO replication 2>/dev/null | grep "master_repl_offset:" | cut -d: -f2 | tr -d '\r')
    SLAVE_REPL_OFFSET=$($REDIS_CLI INFO replication 2>/dev/null | grep "slave_repl_offset:" | cut -d: -f2 | tr -d '\r')

    print_info "主节点地址: ${MASTER_HOST}:${MASTER_PORT}"
    print_info "主从同步偏移量: master=${MASTER_REPL_OFFSET}, slave=${SLAVE_REPL_OFFSET}"

    if [ "$MASTER_LINK_STATUS" = "up" ]; then
        # 计算复制延迟
        if [ -n "$MASTER_REPL_OFFSET" ] && [ -n "$SLAVE_REPL_OFFSET" ]; then
            LAG=$((MASTER_REPL_OFFSET - SLAVE_REPL_OFFSET))
            if [ "$LAG" -gt 10000 ]; then
                print_fail "主从复制延迟过大 (offset差: ${LAG})，存在数据不一致风险"
                ((FAIL_COUNT++))
            elif [ "$LAG" -gt 1000 ]; then
                print_warn "主从复制存在一定延迟 (offset差: ${LAG})"
                ((WARN_COUNT++))
            else
                print_ok "主从复制状态正常，延迟在合理范围内"
                ((OK_COUNT++))
            fi
        fi
    else
        print_fail "与主节点连接断开！(master_link_status=${MASTER_LINK_STATUS})"
        print_info "建议: 1)检查主节点是否存活 2)检查网络连通性 3)检查认证配置"
        ((FAIL_COUNT++))
    fi
else
    print_info "当前角色: 单节点 (无主从配置)"
    print_warn "未配置主从复制，不具备高可用能力"
    ((WARN_COUNT++))
fi

# ==================== 6. 检查客户端连接 ====================
print_info ""
print_info "6. 检查客户端连接..."
print_separator

CONNECTED_CLIENTS=$($REDIS_CLI INFO clients 2>/dev/null | grep "connected_clients:" | cut -d: -f2 | tr -d '\r')
MAXCLIENTS=$($REDIS_CLI INFO clients 2>/dev/null | grep "maxclients:" | cut -d: -f2 | tr -d '\r')
BLOCKED_CLIENTS=$($REDIS_CLI INFO clients 2>/dev/null | grep "blocked_clients:" | cut -d: -f2 | tr -d '\r')

print_info "当前客户端连接数: ${CONNECTED_CLIENTS}"
print_info "最大客户端连接数: ${MAXCLIENTS}"
print_info "阻塞客户端数: ${BLOCKED_CLIENTS}"

if [ -n "$CONNECTED_CLIENTS" ] && [ -n "$MAXCLIENTS" ] && [ "$MAXCLIENTS" -gt 0 ]; then
    CLIENT_RATIO=$((CONNECTED_CLIENTS * 100 / MAXCLIENTS))
    print_info "客户端连接使用率: ${CLIENT_RATIO}%"

    if [ "$CLIENT_RATIO" -ge 90 ]; then
        print_fail "客户端连接数接近上限！可能无法接受新连接"
        ((FAIL_COUNT++))
    elif [ "$CLIENT_RATIO" -ge 70 ]; then
        print_warn "客户端连接数偏高，需要关注"
        ((WARN_COUNT++))
    else
        print_ok "客户端连接数正常"
        ((OK_COUNT++))
    fi
fi

if [ -n "$BLOCKED_CLIENTS" ] && [ "$BLOCKED_CLIENTS" -gt 0 ]; then
    print_warn "存在 ${BLOCKED_CLIENTS} 个阻塞客户端，可能影响Redis性能"
    ((WARN_COUNT++))
fi

# ==================== 7. 检查Key统计与过期 ====================
print_info ""
print_info "7. 检查Key统计与过期..."
print_separator

DB_SIZE=$($REDIS_CLI DBSIZE 2>/dev/null | cut -d: -f2 | tr -d '\r')
EXPIRED_KEYS=$($REDIS_CLI INFO stats 2>/dev/null | grep "expired_keys:" | cut -d: -f2 | tr -d '\r')
EVICTED_KEYS=$($REDIS_CLI INFO stats 2>/dev/null | grep "evicted_keys:" | cut -d: -f2 | tr -d '\r')
KEYSPACE_HITS=$($REDIS_CLI INFO stats 2>/dev/null | grep "keyspace_hits:" | cut -d: -f2 | tr -d '\r')
KEYSPACE_MISSES=$($REDIS_CLI INFO stats 2>/dev/null | grep "keyspace_misses:" | cut -d: -f2 | tr -d '\r')

print_info "总Key数量: ${DB_SIZE}"
print_info "已过期Key数: ${EXPIRED_KEYS}"
print_info "被淘汰Key数: ${EVICTED_KEYS}"

# 计算缓存命中率
if [ -n "$KEYSPACE_HITS" ] && [ -n "$KEYSPACE_MISSES" ]; then
    TOTAL_LOOKUPS=$((KEYSPACE_HITS + KEYSPACE_MISSES))
    if [ "$TOTAL_LOOKUPS" -gt 0 ]; then
        HIT_RATIO=$((KEYSPACE_HITS * 100 / TOTAL_LOOKUPS))
        print_info "缓存命中率: ${HIT_RATIO}% (命中:${KEYSPACE_HITS} / 未命中:${KEYSPACE_MISSES})"

        if [ "$HIT_RATIO" -lt 50 ]; then
            print_warn "缓存命中率过低 (${HIT_RATIO}%)，可能需要调整缓存策略或TTL"
            ((WARN_COUNT++))
        else
            print_ok "缓存命中率正常"
            ((OK_COUNT++))
        fi
    fi
fi

# 检查淘汰Key数量
if [ -n "$EVICTED_KEYS" ] && [ "$EVICTED_KEYS" -gt 0 ]; then
    print_warn "存在被淘汰的Key (${EVICTED_KEYS}个)，说明内存曾达到上限"
    ((WARN_COUNT++))
else
    print_ok "无Key被淘汰，内存充裕"
    ((OK_COUNT++))
fi

# ==================== 8. 检查持久化状态 ====================
print_info ""
print_info "8. 检查持久化状态..."
print_separator

RDB_LAST_OK=$($REDIS_CLI INFO persistence 2>/dev/null | grep "rdb_last_bgsave_status:" | cut -d: -f2 | tr -d '\r')
RDB_CHANGES_SINCE_LAST=$($REDIS_CLI INFO persistence 2>/dev/null | grep "rdb_changes_since_last_save:" | cut -d: -f2 | tr -d '\r')
AOF_ENABLED=$($REDIS_CLI INFO persistence 2>/dev/null | grep "aof_enabled:" | cut -d: -f2 | tr -d '\r')

if [ "$RDB_LAST_OK" = "ok" ]; then
    print_ok "RDB最近一次快照成功"
    ((OK_COUNT++))
else
    print_fail "RDB快照失败！状态: ${RDB_LAST_OK}"
    ((FAIL_COUNT++))
fi

print_info "距上次RDB保存的变更Key数: ${RDB_CHANGES_SINCE_LAST}"
if [ "$RDB_CHANGES_SINCE_LAST" -gt 10000 ]; then
    print_warn "距上次RDB保存变更Key数较多 (${RDB_CHANGES_SINCE_LAST})，建议检查save配置"
    ((WARN_COUNT++))
fi

print_info "AOF持久化: ${AOF_ENABLED}"
if [ "$AOF_ENABLED" = "1" ]; then
    AOF_LAST_OK=$($REDIS_CLI INFO persistence 2>/dev/null | grep "aof_last_bgrewrite_status:" | cut -d: -f2 | tr -d '\r')
    if [ "$AOF_LAST_OK" = "ok" ]; then
        print_ok "AOF重写状态正常"
        ((OK_COUNT++))
    else
        print_fail "AOF重写失败！状态: ${AOF_LAST_OK}"
        ((FAIL_COUNT++))
    fi
fi

# ==================== 诊断结论汇总 ====================
echo ""
print_separator
echo ""
echo "==================== Redis诊断结论汇总 ===================="
echo ""

TOTAL_CHECKS=$((OK_COUNT + WARN_COUNT + FAIL_COUNT))

echo -e "总检查项: ${TOTAL_CHECKS}  |  ${GREEN}正常: ${OK_COUNT}${NC}  |  ${YELLOW}警告: ${WARN_COUNT}${NC}  |  ${RED}异常: ${FAIL_COUNT}${NC}"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
    print_fail "Redis存在 ${FAIL_COUNT} 个严重问题，需要立即处理！"
    echo ""
    print_info "常见修复方案:"
    echo "  1. 内存即将耗尽 -> 扩容/清理Key/优化数据结构"
    echo "  2. 主从断开 -> 检查主节点状态和网络连通性"
    echo "  3. 内存碎片过高 -> 执行MEMORY PURGE或重启"
    echo "  4. RDB/AOF失败 -> 检查磁盘空间和权限"
elif [ "$WARN_COUNT" -gt 0 ]; then
    print_warn "Redis存在 ${WARN_COUNT} 个警告项，建议持续关注"
    echo ""
    print_info "建议定期执行本脚本进行健康检查"
else
    print_ok "Redis各项指标正常，运行健康"
fi

echo ""
print_separator
