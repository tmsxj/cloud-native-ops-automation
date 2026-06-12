#!/bin/bash
# ============================================================
# 模块30-中间件故障排查脚本
# 功能: MySQL连接超时与慢查询排查
# 用法: ./check-mysql.sh [host] [port] [user] [password]
# 示例: ./check-mysql.sh 127.0.0.1 3306 root mypassword
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
MYSQL_HOST="${1:-127.0.0.1}"
MYSQL_PORT="${2:-3306}"
MYSQL_USER="${3:-root}"
MYSQL_PASS="${4:-}"

MYSQL_CMD="mysql -h${MYSQL_HOST} -P${MYSQL_PORT} -u${MYSQL_USER}"
# 如果提供了密码，则追加密码参数
if [ -n "$MYSQL_PASS" ]; then
    MYSQL_CMD="${MYSQL_CMD} -p${MYSQL_PASS}"
fi

# ==================== 统计变量 ====================
FAIL_COUNT=0
WARN_COUNT=0
OK_COUNT=0

# ==================== 分隔线 ====================
print_separator() {
    echo "============================================================"
}

# ==================== 1. 检查MySQL进程状态 ====================
print_info "1. 检查MySQL进程状态..."
print_separator

# 尝试通过systemctl检查
if systemctl is-active --quiet mysqld 2>/dev/null; then
    print_ok "mysqld 服务正在运行"
    ((OK_COUNT++))
elif systemctl is-active --quiet mysql 2>/dev/null; then
    print_ok "mysql 服务正在运行"
    ((OK_COUNT++))
else
    # 如果systemctl不可用，尝试通过ps检查
    if pgrep -x "mysqld" > /dev/null 2>&1 || pgrep -x "mariadbd" > /dev/null 2>&1; then
        print_ok "MySQL进程存在 (通过ps检测)"
        ((OK_COUNT++))
    else
        print_fail "MySQL进程未运行！请检查mysqld服务状态"
        ((FAIL_COUNT++))
        echo ""
        echo "========== 诊断结论 =========="
        print_fail "MySQL服务未启动，请执行: systemctl start mysqld"
        echo "=============================="
        exit 1
    fi
fi

# ==================== 2. 检查MySQL连接 ====================
print_info ""
print_info "2. 检查MySQL连接..."
print_separator

if $MYSQL_CMD -e "SELECT 1" &>/dev/null; then
    print_ok "MySQL连接成功 (host=${MYSQL_HOST}, port=${MYSQL_PORT})"
    ((OK_COUNT++))
else
    print_fail "MySQL连接失败！请检查: 1)服务是否启动 2)端口是否正确 3)用户名密码是否正确"
    ((FAIL_COUNT++))
    echo ""
    echo "========== 诊断结论 =========="
    print_fail "无法连接MySQL，请先确保服务正常运行且网络可达"
    echo "=============================="
    exit 1
fi

# ==================== 3. 检查当前连接数 ====================
print_info ""
print_info "3. 检查当前连接数..."
print_separator

THREADS_CONNECTED=$($MYSQL_CMD -N -e "SHOW STATUS LIKE 'Threads_connected'" 2>/dev/null | awk '{print $2}')
MAX_CONNECTIONS=$($MYSQL_CMD -N -e "SHOW VARIABLES LIKE 'max_connections'" 2>/dev/null | awk '{print $2}')

if [ -z "$THREADS_CONNECTED" ]; then
    print_warn "无法获取连接数信息"
    ((WARN_COUNT++))
elif [ -z "$MAX_CONNECTIONS" ]; then
    MAX_CONNECTIONS=151
    print_info "使用默认max_connections值: ${MAX_CONNECTIONS}"
fi

if [ -n "$THREADS_CONNECTED" ] && [ -n "$MAX_CONNECTIONS" ]; then
    CONN_RATIO=$((THREADS_CONNECTED * 100 / MAX_CONNECTIONS))
    print_info "当前连接数: ${THREADS_CONNECTED} / 最大连接数: ${MAX_CONNECTIONS} (使用率: ${CONN_RATIO}%)"

    if [ "$CONN_RATIO" -ge 90 ]; then
        print_fail "连接数使用率超过90%！即将耗尽连接，可能导致应用连接超时"
        print_info "建议: 1)检查是否有连接泄漏 2)适当增大max_connections 3)优化连接池配置"
        ((FAIL_COUNT++))
    elif [ "$CONN_RATIO" -ge 70 ]; then
        print_warn "连接数使用率超过70%，需要关注"
        ((WARN_COUNT++))
    else
        print_ok "连接数使用率正常"
        ((OK_COUNT++))
    fi
fi

# ==================== 4. 检查慢查询配置 ====================
print_info ""
print_info "4. 检查慢查询配置..."
print_separator

SLOW_QUERY_LOG=$($MYSQL_CMD -N -e "SHOW VARIABLES LIKE 'slow_query_log'" 2>/dev/null | awk '{print $2}')
LONG_QUERY_TIME=$($MYSQL_CMD -N -e "SHOW VARIABLES LIKE 'long_query_time'" 2>/dev/null | awk '{print $2}')
SLOW_QUERY_LOG_FILE=$($MYSQL_CMD -N -e "SHOW VARIABLES LIKE 'slow_query_log_file'" 2>/dev/null | awk '{print $2}')

if [ "$SLOW_QUERY_LOG" = "ON" ]; then
    print_ok "慢查询日志已开启"
    ((OK_COUNT++))
else
    print_warn "慢查询日志未开启，建议在生产环境中开启以便排查性能问题"
    ((WARN_COUNT++))
fi

print_info "慢查询阈值: ${LONG_QUERY_TIME}秒"
print_info "慢查询日志文件: ${SLOW_QUERY_LOG_FILE}"

# 统计最近24小时慢查询数量
if [ -n "$SLOW_QUERY_LOG_FILE" ] && [ -f "$SLOW_QUERY_LOG_FILE" ]; then
    SLOW_COUNT=$(grep -c "Query_time" "$SLOW_QUERY_LOG_FILE" 2>/dev/null || echo "0")
    if [ "$SLOW_COUNT" -gt 100 ]; then
        print_fail "慢查询数量过多 (${SLOW_COUNT}条)，需要优化SQL或调整索引"
        ((FAIL_COUNT++))
    elif [ "$SLOW_COUNT" -gt 10 ]; then
        print_warn "存在${SLOW_COUNT}条慢查询，建议排查TOP慢查询SQL"
        ((WARN_COUNT++))
    else
        print_ok "慢查询数量正常 (${SLOW_COUNT}条)"
        ((OK_COUNT++))
    fi
else
    print_warn "无法读取慢查询日志文件"
    ((WARN_COUNT++))
fi

# ==================== 5. 检查InnoDB锁等待 ====================
print_info ""
print_info "5. 检查InnoDB锁等待..."
print_separator

# 检查当前锁等待数量
LOCK_WAITS=$($MYSQL_CMD -N -e "SHOW STATUS LIKE 'Innodb_row_lock_waits'" 2>/dev/null | awk '{print $2}')
LOCK_TIME_AVG=$($MYSQL_CMD -N -e "SHOW STATUS LIKE 'Innodb_row_lock_time_avg'" 2>/dev/null | awk '{print $2}')
LOCK_TIMEOUTS=$($MYSQL_CMD -N -e "SHOW STATUS LIKE 'Innodb_row_lock_timeouts'" 2>/dev/null | awk '{print $2}')

if [ -n "$LOCK_WAITS" ]; then
    print_info "累计行锁等待次数: ${LOCK_WAITS}"
    print_info "平均行锁等待时间: ${LOCK_TIME_AVG} 毫秒"
    print_info "行锁超时次数: ${LOCK_TIMEOUTS}"

    # 将毫秒转换为整数进行比较
    LOCK_TIME_AVG_INT=${LOCK_TIME_AVG%.*}
    if [ "$LOCK_TIME_AVG_INT" -gt 1000 ]; then
        print_fail "平均锁等待时间过长 (${LOCK_TIME_AVG}ms > 1000ms)，存在严重锁竞争"
        print_info "建议: 1)检查长事务 2)优化事务粒度 3)检查死锁日志"
        ((FAIL_COUNT++))
    elif [ "$LOCK_TIME_AVG_INT" -gt 200 ]; then
        print_warn "平均锁等待时间偏高 (${LOCK_TIME_AVG}ms)，建议关注"
        ((WARN_COUNT++))
    else
        print_ok "锁等待情况正常"
        ((OK_COUNT++))
    fi
else
    print_warn "无法获取InnoDB锁等待信息"
    ((WARN_COUNT++))
fi

# 检查当前正在等待锁的事务
CURRENT_LOCKS=$($MYSQL_CMD -N -e "
    SELECT COUNT(*) FROM information_schema.INNODB_LOCK_WAITS
" 2>/dev/null)
if [ -n "$CURRENT_LOCKS" ] && [ "$CURRENT_LOCKS" -gt 0 ]; then
    print_fail "当前存在 ${CURRENT_LOCKS} 个锁等待事务！"
    ((FAIL_COUNT++))
else
    print_ok "当前无活跃的锁等待事务"
    ((OK_COUNT++))
fi

# ==================== 6. 检查连接超时配置 ====================
print_info ""
print_info "6. 检查连接超时配置..."
print_separator

WAIT_TIMEOUT=$($MYSQL_CMD -N -e "SHOW VARIABLES LIKE 'wait_timeout'" 2>/dev/null | awk '{print $2}')
INTERACTIVE_TIMEOUT=$($MYSQL_CMD -N -e "SHOW VARIABLES LIKE 'interactive_timeout'" 2>/dev/null | awk '{print $2}')
CONNECT_TIMEOUT=$($MYSQL_CMD -N -e "SHOW VARIABLES LIKE 'connect_timeout'" 2>/dev/null | awk '{print $2}')

print_info "wait_timeout: ${WAIT_TIMEOUT}秒"
print_info "interactive_timeout: ${INTERACTIVE_TIMEOUT}秒"
print_info "connect_timeout: ${CONNECT_TIMEOUT}秒"

if [ "$WAIT_TIMEOUT" -lt 600 ]; then
    print_warn "wait_timeout值较小 (${WAIT_TIMEOUT}s)，可能导致空闲连接被过早断开"
    ((WARN_COUNT++))
else
    print_ok "超时配置合理"
    ((OK_COUNT++))
fi

# ==================== 7. 检查Aborted连接 ====================
print_info ""
print_info "7. 检查异常中断连接..."
print_separator

ABORTED_CONNECT=$($MYSQL_CMD -N -e "SHOW STATUS LIKE 'Aborted_connects'" 2>/dev/null | awk '{print $2}')
ABORTED_CLIENTS=$($MYSQL_CMD -N -e "SHOW STATUS LIKE 'Aborted_clients'" 2>/dev/null | awk '{print $2}')

print_info "Aborted_connects (认证失败): ${ABORTED_CONNECT}"
print_info "Aborted_clients (连接中断): ${ABORTED_CLIENTS}"

if [ "$ABORTED_CLIENTS" -gt 1000 ]; then
    print_fail "Aborted_clients过高 (${ABORTED_CLIENTS})，可能存在网络不稳定或max_allowed_packet过小"
    ((FAIL_COUNT++))
elif [ "$ABORTED_CLIENTS" -gt 100 ]; then
    print_warn "Aborted_clients偏高 (${ABORTED_CLIENTS})，建议排查网络和客户端配置"
    ((WARN_COUNT++))
else
    print_ok "异常连接数正常"
    ((OK_COUNT++))
fi

# ==================== 8. 检查临时表和排序 ====================
print_info ""
print_info "8. 检查临时表与磁盘排序..."
print_separator

TMP_TABLES=$($MYSQL_CMD -N -e "SHOW STATUS LIKE 'Created_tmp_tables'" 2>/dev/null | awk '{print $2}')
TMP_DISK_TABLES=$($MYSQL_CMD -N -e "SHOW STATUS LIKE 'Created_tmp_disk_tables'" 2>/dev/null | awk '{print $2}')
SORT_MERGE_PASSES=$($MYSQL_CMD -N -e "SHOW STATUS LIKE 'Sort_merge_passes'" 2>/dev/null | awk '{print $2}')

print_info "创建临时表总数: ${TMP_TABLES}"
print_info "创建磁盘临时表数: ${TMP_DISK_TABLES}"
print_info "排序合并传递次数: ${SORT_MERGE_PASSES}"

if [ -n "$TMP_TABLES" ] && [ "$TMP_TABLES" -gt 0 ]; then
    DISK_RATIO=$((TMP_DISK_TABLES * 100 / TMP_TABLES))
    print_info "磁盘临时表比例: ${DISK_RATIO}%"

    if [ "$DISK_RATIO" -gt 30 ]; then
        print_fail "磁盘临时表比例过高 (${DISK_RATIO}%)，建议增大tmp_table_size和max_heap_table_size"
        ((FAIL_COUNT++))
    elif [ "$DISK_RATIO" -gt 10 ]; then
        print_warn "磁盘临时表比例偏高 (${DISK_RATIO}%)，部分查询可能需要优化"
        ((WARN_COUNT++))
    else
        print_ok "临时表使用情况正常"
        ((OK_COUNT++))
    fi
fi

# ==================== 诊断结论汇总 ====================
echo ""
print_separator
echo ""
echo "==================== MySQL诊断结论汇总 ===================="
echo ""

TOTAL_CHECKS=$((OK_COUNT + WARN_COUNT + FAIL_COUNT))

echo -e "总检查项: ${TOTAL_CHECKS}  |  ${GREEN}正常: ${OK_COUNT}${NC}  |  ${YELLOW}警告: ${WARN_COUNT}${NC}  |  ${RED}异常: ${FAIL_COUNT}${NC}"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
    print_fail "MySQL存在 ${FAIL_COUNT} 个严重问题，需要立即处理！"
    echo ""
    print_info "常见修复方案:"
    echo "  1. 连接数耗尽 -> 增大max_connections, 检查连接池配置"
    echo "  2. 慢查询过多 -> 优化SQL索引, 调整long_query_time"
    echo "  3. 锁等待过长 -> 检查长事务, 优化事务粒度"
    echo "  4. 连接中断多 -> 检查网络稳定性, 调整max_allowed_packet"
elif [ "$WARN_COUNT" -gt 0 ]; then
    print_warn "MySQL存在 ${WARN_COUNT} 个警告项，建议持续关注"
    echo ""
    print_info "建议定期执行本脚本进行健康检查"
else
    print_ok "MySQL各项指标正常，运行健康"
fi

echo ""
print_separator
