#!/bin/bash
# ============================================================
# 模块30-中间件故障排查脚本
# 功能: Kafka消息堆积排查
# 用法: ./check-kafka.sh [bootstrap-server]
# 示例: ./check-kafka.sh localhost:9092
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
BOOTSTRAP_SERVER="${1:-localhost:9092}"

# Kafka命令行工具路径（根据实际安装位置调整）
KAFKA_HOME="${KAFKA_HOME:-/opt/kafka}"
KAFKA_BIN="${KAFKA_HOME}/bin"

# 如果KAFKA_HOME下没有工具，尝试从PATH中查找
if [ ! -d "$KAFKA_BIN" ]; then
    # 尝试查找kafka脚本
    KAFKA_SCRIPT=$(which kafka-topics.sh 2>/dev/null || which kafka-topics 2>/dev/null)
    if [ -n "$KAFKA_SCRIPT" ]; then
        KAFKA_BIN=$(dirname "$KAFKA_SCRIPT")
    fi
fi

# ==================== 统计变量 ====================
FAIL_COUNT=0
WARN_COUNT=0
OK_COUNT=0

# ==================== 分隔线 ====================
print_separator() {
    echo "============================================================"
}

# ==================== 辅助函数: 执行Kafka命令 ====================
run_kafka_cmd() {
    local cmd="$1"
    if [ -f "${KAFKA_BIN}/${cmd}" ]; then
        "${KAFKA_BIN}/${cmd}" --bootstrap-server "${BOOTSTRAP_SERVER}" "${@:2}" 2>/dev/null
    elif command -v "${cmd}" &>/dev/null; then
        "${cmd}" --bootstrap-server "${BOOTSTRAP_SERVER}" "${@:2}" 2>/dev/null
    else
        print_warn "未找到Kafka命令行工具: ${cmd}"
        print_info "请设置KAFKA_HOME环境变量或将Kafka bin目录加入PATH"
        return 1
    fi
}

# ==================== 1. 检查Broker连通性 ====================
print_info "1. 检查Kafka Broker连通性..."
print_separator

# 通过列出Topic来测试Broker连通性
TOPIC_LIST=$(run_kafka_cmd kafka-topics.sh --list)

if [ $? -eq 0 ]; then
    TOPIC_COUNT=$(echo "$TOPIC_LIST" | wc -l)
    print_ok "Broker连接成功 (bootstrap-server=${BOOTSTRAP_SERVER})"
    print_info "当前Topic数量: ${TOPIC_COUNT}"
    ((OK_COUNT++))

    # 显示Topic列表（最多20个）
    if [ "$TOPIC_COUNT" -gt 0 ]; then
        print_info "Topic列表 (最多显示20个):"
        echo "$TOPIC_LIST" | head -20 | while read -r topic; do
            print_info "  - ${topic}"
        done
        if [ "$TOPIC_COUNT" -gt 20 ]; then
            print_info "  ... 还有 $((TOPIC_COUNT - 20)) 个Topic"
        fi
    fi
else
    # 尝试通过端口检查
    BROKER_HOST=$(echo "$BOOTSTRAP_SERVER" | cut -d: -f1)
    BROKER_PORT=$(echo "$BOOTSTRAP_SERVER" | cut -d: -f2)

    if timeout 3 bash -c "echo > /dev/tcp/${BROKER_HOST}/${BROKER_PORT}" 2>/dev/null; then
        print_warn "Broker端口可达但Kafka命令行工具不可用"
        ((WARN_COUNT++))
    else
        print_fail "无法连接Kafka Broker！请检查: 1)Broker是否启动 2)端口是否正确 3)防火墙设置"
        ((FAIL_COUNT++))
        echo ""
        echo "========== 诊断结论 =========="
        print_fail "Kafka Broker不可达，请先确保Kafka服务正常运行"
        echo "=============================="
        exit 1
    fi
fi

# ==================== 2. 检查Broker集群信息 ====================
print_info ""
print_info "2. 检查Broker集群信息..."
print_separator

CLUSTER_META=$(run_kafka_cmd kafka-broker-api-versions.sh 2>/dev/null | head -5)

if [ $? -eq 0 ]; then
    print_ok "Broker API版本查询成功，Broker正常响应"
    ((OK_COUNT++))
else
    print_warn "无法获取Broker API版本信息"
    ((WARN_COUNT++))
fi

# 获取集群元数据
CLUSTER_DESC=$(run_kafka_cmd kafka-metadata.sh --cluster-id 2>/dev/null || run_kafka_cmd kafka-cluster.sh --cluster-id 2>/dev/null)
if [ -n "$CLUSTER_DESC" ]; then
    print_info "集群ID: ${CLUSTER_DESC}"
fi

# 获取Broker列表
BROKER_LIST=$(run_kafka_cmd kafka-broker-api-versions.sh 2>/dev/null | grep "id:" | head -5)
if [ -n "$BROKER_LIST" ]; then
    print_info "Broker节点信息:"
    echo "$BROKER_LIST" | while read -r line; do
        print_info "  ${line}"
    done
    ((OK_COUNT++))
fi

# ==================== 3. 检查消费者组与消息堆积 ====================
print_info ""
print_info "3. 检查消费者组与消息堆积..."
print_separator

# 获取所有消费者组
CONSUMER_GROUPS=$(run_kafka_cmd kafka-consumer-groups.sh --list)

if [ -z "$CONSUMER_GROUPS" ]; then
    print_warn "未发现活跃的消费者组"
    ((WARN_COUNT++))
else
    GROUP_COUNT=$(echo "$CONSUMER_GROUPS" | wc -l)
    print_info "消费者组数量: ${GROUP_COUNT}"

    TOTAL_LAG=0
    LAG_CRITICAL_GROUPS=""
    LAG_WARNING_GROUPS=""
    ACTIVE_GROUPS=0
    EMPTY_GROUPS=0

    # 遍历每个消费者组
    while read -r GROUP; do
        [ -z "$GROUP" ] && continue

        # 获取消费者组详情
        GROUP_DETAIL=$(run_kafka_cmd kafka-consumer-groups.sh --describe --group "${GROUP}")
        if [ $? -ne 0 ]; then
            continue
        fi

        # 检查消费者组状态
        GROUP_STATE=$(echo "$GROUP_DETAIL" | grep -E "^\s*${GROUP}" | awk '{print $NF}' | tr -d ',')

        if [ "$GROUP_STATE" = "Empty" ]; then
            ((EMPTY_GROUPS++))
            # Empty组可能有堆积
            GROUP_LAG=$(echo "$GROUP_DETAIL" | awk 'NR>1 && $6 ~ /^[0-9]+$/ {sum+=$6} END {print sum+0}')
            if [ "$GROUP_LAG" -gt 0 ]; then
                LAG_CRITICAL_GROUPS="${LAG_CRITICAL_GROUPS}\n  [无消费者] ${GROUP}: LAG=${GROUP_LAG}"
                TOTAL_LAG=$((TOTAL_LAG + GROUP_LAG))
            fi
        elif [ "$GROUP_STATE" = "Stable" ] || [ "$GROUP_STATE" = "PreparingRebalance" ] || [ "$GROUP_STATE" = "CompletingRebalance" ] || [ "$GROUP_STATE" = "Rebalancing" ]; then
            ((ACTIVE_GROUPS++))
            # 计算该组的LAG
            GROUP_LAG=$(echo "$GROUP_DETAIL" | awk 'NR>1 && $6 ~ /^[0-9]+$/ {sum+=$6} END {print sum+0}')
            TOTAL_LAG=$((TOTAL_LAG + GROUP_LAG))

            if [ "$GROUP_LAG" -gt 10000 ]; then
                LAG_CRITICAL_GROUPS="${LAG_CRITICAL_GROUPS}\n  ${GROUP}: LAG=${GROUP_LAG}"
            elif [ "$GROUP_LAG" -gt 1000 ]; then
                LAG_WARNING_GROUPS="${LAG_WARNING_GROUPS}\n  ${GROUP}: LAG=${GROUP_LAG}"
            fi
        fi
    done <<< "$CONSUMER_GROUPS"

    print_info "活跃消费者组: ${ACTIVE_GROUPS}"
    print_info "空消费者组(无消费者): ${EMPTY_GROUPS}"
    print_info "总消息堆积量(LAG): ${TOTAL_LAG}"

    # 判断堆积情况
    if [ "$TOTAL_LAG" -gt 100000 ]; then
        print_fail "消息堆积严重！总LAG: ${TOTAL_LAG}"
        echo -e "${LAG_CRITICAL_GROUPS}"
        echo -e "${LAG_WARNING_GROUPS}"
        print_info "建议: 1)增加消费者实例 2)检查消费者处理逻辑 3)排查是否有消费者异常"
        ((FAIL_COUNT++))
    elif [ "$TOTAL_LAG" -gt 10000 ]; then
        print_warn "消息堆积较多，总LAG: ${TOTAL_LAG}"
        echo -e "${LAG_CRITICAL_GROUPS}"
        echo -e "${LAG_WARNING_GROUPS}"
        ((WARN_COUNT++))
    elif [ "$TOTAL_LAG" -gt 0 ]; then
        print_warn "存在少量消息堆积，总LAG: ${TOTAL_LAG}"
        if [ -n "$LAG_WARNING_GROUPS" ]; then
            echo -e "${LAG_WARNING_GROUPS}"
        fi
        ((WARN_COUNT++))
    else
        print_ok "无消息堆积，消费正常"
        ((OK_COUNT++))
    fi

    # 检查空消费者组
    if [ "$EMPTY_GROUPS" -gt 0 ]; then
        print_warn "存在 ${EMPTY_GROUPS} 个空消费者组(无活跃消费者)，可能导致消息无人消费"
        ((WARN_COUNT++))
    else
        print_ok "所有消费者组都有活跃消费者"
        ((OK_COUNT++))
    fi
fi

# ==================== 4. 检查Topic分区副本 ====================
print_info ""
print_info "4. 检查Topic分区与副本..."
print_separator

# 获取Topic详情（检查前10个Topic）
PARTITION_ISSUES=0
if [ -n "$TOPIC_LIST" ]; then
    echo "$TOPIC_LIST" | head -10 | while read -r TOPIC; do
        [ -z "$TOPIC" ] && continue

        TOPIC_DESC=$(run_kafka_cmd kafka-topics.sh --describe --topic "${TOPIC}")
        if [ -n "$TOPIC_DESC" ]; then
            # 检查是否有离线分区
            OFFLINE_PARTITIONS=$(echo "$TOPIC_DESC" | grep -c "Isr: $" 2>/dev/null || echo "0")
            if [ "$OFFLINE_PARTITIONS" -gt 0 ]; then
                print_fail "Topic [${TOPIC}] 存在离线分区！"
                echo "$TOPIC_DESC" | grep "Isr: $"
                PARTITION_ISSUES=$((PARTITION_ISSUES + 1))
            fi

            # 检查副本同步率
            UNDER_REPLICATED=$(echo "$TOPIC_DESC" | awk 'NR>1 {split($0,a,","); for(i in a) if(a[i] ~ /Isr/) {n=split(a[i],b,":"); if(b[2]+0 < b[1]+0) print}}')
            if [ -n "$UNDER_REPLICATED" ]; then
                print_warn "Topic [${TOPIC}] 存在副本不同步的分区"
            fi
        fi
    done
fi

if [ "$PARTITION_ISSUES" -eq 0 ]; then
    print_ok "所有检查的Topic分区和副本状态正常"
    ((OK_COUNT++))
else
    print_fail "发现 ${PARTITION_ISSUES} 个Topic存在分区问题"
    ((FAIL_COUNT++))
fi

# ==================== 5. 检查Broker磁盘使用 ====================
print_info ""
print_info "5. 检查Broker磁盘使用情况..."
print_separator

# Kafka日志目录（默认）
KAFKA_LOG_DIR="${KAFKA_LOG_DIR:-/var/lib/kafka/logs}"

if [ -d "$KAFKA_LOG_DIR" ]; then
    DISK_USAGE=$(df -h "$KAFKA_LOG_DIR" | awk 'NR==2 {print $5}' | tr -d '%')
    DISK_AVAIL=$(df -h "$KAFKA_LOG_DIR" | awk 'NR==2 {print $4}')

    print_info "Kafka日志目录: ${KAFKA_LOG_DIR}"
    print_info "磁盘使用率: ${DISK_USAGE}%"
    print_info "可用空间: ${DISK_AVAIL}"

    if [ "$DISK_USAGE" -ge 90 ]; then
        print_fail "磁盘使用率超过90%！Kafka可能无法写入新消息"
        print_info "建议: 1)清理过期日志 2)增加磁盘 3)调整日志保留策略"
        ((FAIL_COUNT++))
    elif [ "$DISK_USAGE" -ge 75 ]; then
        print_warn "磁盘使用率偏高 (${DISK_USAGE}%)，建议关注"
        ((WARN_COUNT++))
    else
        print_ok "磁盘使用率正常"
        ((OK_COUNT++))
    fi

    # 检查Kafka日志目录大小
    LOG_DIR_SIZE=$(du -sh "$KAFKA_LOG_DIR" 2>/dev/null | awk '{print $1}')
    print_info "Kafka日志目录大小: ${LOG_DIR_SIZE}"
else
    # 如果默认目录不存在，检查系统磁盘
    print_info "Kafka日志目录(${KAFKA_LOG_DIR})不存在，检查系统磁盘..."
    DISK_INFO=$(df -h | grep -E "/$|/data|/kafka" | head -5)
    if [ -n "$DISK_INFO" ]; then
        echo "$DISK_INFO"
    fi

    # 检查根分区
    ROOT_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$ROOT_USAGE" -ge 90 ]; then
        print_fail "根分区磁盘使用率超过90%！"
        ((FAIL_COUNT++))
    else
        print_warn "无法确定Kafka日志目录，请确认KAFKA_LOG_DIR配置"
        ((WARN_COUNT++))
    fi
fi

# ==================== 6. 检查网络连接 ====================
print_info ""
print_info "6. 检查Broker网络连接..."
print_separator

BROKER_HOST=$(echo "$BOOTSTRAP_SERVER" | cut -d: -f1)
BROKER_PORT=$(echo "$BOOTSTRAP_SERVER" | cut -d: -f2)

# 检查与Broker的连接数
BROKER_CONN_COUNT=$(ss -ant 2>/dev/null | grep -c ":${BROKER_PORT}" || netstat -ant 2>/dev/null | grep -c ":${BROKER_PORT}" || echo "0")
print_info "Broker(${BROKER_PORT})当前连接数: ${BROKER_CONN_COUNT}"

if [ "$BROKER_CONN_COUNT" -gt 5000 ]; then
    print_warn "Broker连接数较多 (${BROKER_CONN_COUNT})，建议检查客户端连接池配置"
    ((WARN_COUNT++))
else
    print_ok "Broker连接数正常"
    ((OK_COUNT++))
fi

# 检查TIME_WAIT连接数
TIMEWAIT_COUNT=$(ss -ant 2>/dev/null | grep -c "TIME-WAIT" || netstat -ant 2>/dev/null | grep -c "TIME_WAIT" || echo "0")
if [ "$TIMEWAIT_COUNT" -gt 1000 ]; then
    print_warn "TIME_WAIT连接数过多 (${TIMEWAIT_COUNT})，可能存在频繁的短连接"
    print_info "建议: 启用keep-alive，复用Kafka Producer/Consumer连接"
    ((WARN_COUNT++))
else
    print_ok "TIME_WAIT连接数正常"
    ((OK_COUNT++))
fi

# ==================== 7. 检查JMX/进程状态 ====================
print_info ""
print_info "7. 检查Kafka进程状态..."
print_separator

KAFKA_PID=$(pgrep -f "kafka.Kafka" 2>/dev/null | head -1)

if [ -n "$KAFKA_PID" ]; then
    # 检查进程运行时间
    KAFKA_UPTIME=$(ps -o etime= -p "$KAFKA_PID" 2>/dev/null | tr -d ' ')
    print_ok "Kafka Broker进程运行中 (PID: ${KAFKA_PID}, 运行时间: ${KAFKA_UPTIME})"
    ((OK_COUNT++))

    # 检查进程内存使用
    KAFKA_MEM=$(ps -o rss= -p "$KAFKA_PID" 2>/dev/null)
    if [ -n "$KAFKA_MEM" ]; then
        KAFKA_MEM_MB=$((KAFKA_MEM / 1024))
        print_info "Kafka进程内存使用: ${KAFKA_MEM_MB}MB"

        if [ "$KAFKA_MEM_MB" -gt 8192 ]; then
            print_warn "Kafka进程内存使用较高 (${KAFKA_MEM_MB}MB)，建议检查堆配置"
            ((WARN_COUNT++))
        fi
    fi

    # 检查进程CPU使用
    KAFKA_CPU=$(ps -o %cpu= -p "$KAFKA_PID" 2>/dev/null | tr -d ' ')
    if [ -n "$KAFKA_CPU" ]; then
        print_info "Kafka进程CPU使用率: ${KAFKA_CPU}%"

        CPU_INT=${KAFKA_CPU%.*}
        if [ "$CPU_INT" -gt 80 ]; then
            print_fail "Kafka进程CPU使用率过高 (${KAFKA_CPU}%)，可能影响吞吐量"
            ((FAIL_COUNT++))
        elif [ "$CPU_INT" -gt 50 ]; then
            print_warn "Kafka进程CPU使用率偏高 (${KAFKA_CPU}%)"
            ((WARN_COUNT++))
        else
            print_ok "Kafka进程CPU使用率正常"
            ((OK_COUNT++))
        fi
    fi
else
    print_fail "Kafka Broker进程未运行！"
    ((FAIL_COUNT++))
fi

# ==================== 诊断结论汇总 ====================
echo ""
print_separator
echo ""
echo "==================== Kafka诊断结论汇总 ===================="
echo ""

TOTAL_CHECKS=$((OK_COUNT + WARN_COUNT + FAIL_COUNT))

echo -e "总检查项: ${TOTAL_CHECKS}  |  ${GREEN}正常: ${OK_COUNT}${NC}  |  ${YELLOW}警告: ${WARN_COUNT}${NC}  |  ${RED}异常: ${FAIL_COUNT}${NC}"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
    print_fail "Kafka存在 ${FAIL_COUNT} 个严重问题，需要立即处理！"
    echo ""
    print_info "常见修复方案:"
    echo "  1. 消息堆积 -> 增加消费者实例，检查消费逻辑，排除消费异常"
    echo "  2. 分区离线 -> 检查Broker存活，修复副本同步"
    echo "  3. 磁盘满 -> 清理过期日志，调整retention配置，扩容磁盘"
    echo "  4. CPU过高 -> 优化分区数，调整批处理大小，扩容节点"
elif [ "$WARN_COUNT" -gt 0 ]; then
    print_warn "Kafka存在 ${WARN_COUNT} 个警告项，建议持续关注"
    echo ""
    print_info "建议定期执行本脚本进行健康检查"
else
    print_ok "Kafka各项指标正常，运行健康"
fi

echo ""
print_separator
