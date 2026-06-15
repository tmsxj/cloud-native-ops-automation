#!/bin/bash
# ============================================================
# 模块30-中间件故障排查脚本
# 功能: Nginx 502/504排查
# 用法: ./check-nginx.sh [config-path]
# 示例: ./check-nginx.sh /etc/nginx/nginx.conf
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
NGINX_CONF="${1:-/etc/nginx/nginx.conf}"
ERROR_LOG="/var/log/nginx/error.log"
ACCESS_LOG="/var/log/nginx/access.log"

# ==================== 统计变量 ====================
FAIL_COUNT=0
WARN_COUNT=0
OK_COUNT=0

# ==================== 分隔线 ====================
print_separator() {
    echo "============================================================"
}

# ==================== 1. 检查Nginx进程状态 ====================
print_info "1. 检查Nginx进程状态..."
print_separator

# 检查Nginx进程
NGINX_MASTER_PID=$(pgrep -x "nginx" 2>/dev/null | head -1)
NGINX_WORKER_COUNT=$(pgrep -c "nginx" 2>/dev/null)

if [ -n "$NGINX_MASTER_PID" ]; then
    # 减去master进程
    NGINX_WORKERS=$((NGINX_WORKER_COUNT - 1))
    print_ok "Nginx进程运行中 (Master PID: ${NGINX_MASTER_PID}, Worker数: ${NGINX_WORKERS})"
    ((OK_COUNT++))

    # 检查worker进程数配置
    if [ -f "$NGINX_CONF" ]; then
        WORKER_PROCESSES=$(grep -E "^\s*worker_processes" "$NGINX_CONF" | awk '{print $2}' | tr -d ';')
        print_info "配置的worker_processes: ${WORKER_PROCESSES}"

        CPU_CORES=$(nproc 2>/dev/null || echo "unknown")
        print_info "系统CPU核心数: ${CPU_CORES}"

        if [ "$WORKER_PROCESSES" = "auto" ]; then
            print_ok "worker_processes设置为auto，将自动匹配CPU核心数"
            ((OK_COUNT++))
        elif [ "$WORKER_PROCESSES" != "1" ] && [ -n "$CPU_CORES" ] && [ "$CPU_CORES" != "unknown" ]; then
            if [ "$WORKER_PROCESSES" -lt "$CPU_CORES" ]; then
                print_warn "worker_processes(${WORKER_PROCESSES})小于CPU核心数(${CPU_CORES})，建议调大以充分利用CPU"
                ((WARN_COUNT++))
            else
                print_ok "worker_processes配置合理"
                ((OK_COUNT++))
            fi
        fi
    fi
else
    print_fail "Nginx进程未运行！"
    ((FAIL_COUNT++))
    echo ""
    echo "========== 诊断结论 =========="
    print_fail "Nginx服务未启动，请执行: systemctl start nginx"
    echo "=============================="
    exit 1
fi

# ==================== 2. 检查Nginx配置 ====================
print_info ""
print_info "2. 检查Nginx配置..."
print_separator

# 测试配置语法
NGINX_TEST=$(nginx -t 2>&1)
NGINX_TEST_RC=$?

if [ $NGINX_TEST_RC -eq 0 ]; then
    print_ok "Nginx配置语法检查通过"
    ((OK_COUNT++))
else
    print_fail "Nginx配置语法错误！"
    echo "$NGINX_TEST"
    ((FAIL_COUNT++))
fi

# 检查配置文件是否存在
if [ -f "$NGINX_CONF" ]; then
    print_info "配置文件: ${NGINX_CONF}"

    # 检查worker_connections
    WORKER_CONNS=$(grep -E "^\s*worker_connections" "$NGINX_CONF" | awk '{print $2}' | tr -d ';')
    if [ -n "$WORKER_CONNS" ]; then
        print_info "worker_connections: ${WORKER_CONNS}"

        if [ "$WORKER_CONNS" -lt 1024 ]; then
            print_warn "worker_connections偏小(${WORKER_CONNS})，高并发场景建议设为2048或更高"
            ((WARN_COUNT++))
        else
            print_ok "worker_connections配置合理"
            ((OK_COUNT++))
        fi
    fi

    # 检查keepalive_timeout
    KEEPALIVE=$(grep -E "^\s*keepalive_timeout" "$NGINX_CONF" | awk '{print $2}' | tr -d ';')
    if [ -n "$KEEPALIVE" ]; then
        print_info "keepalive_timeout: ${KEEPALIVE}"
    fi

    # 检查proxy相关超时配置
    PROXY_TIMEOUTS=$(grep -E "proxy_(connect|read|send)_timeout" "$NGINX_CONF" | tr -d ';' | head -5)
    if [ -n "$PROXY_TIMEOUTS" ]; then
        print_info "Proxy超时配置:"
        echo "$PROXY_TIMEOUTS" | while read -r line; do
            print_info "  ${line}"
        done
    fi
else
    print_warn "配置文件不存在: ${NGINX_CONF}"
    ((WARN_COUNT++))
fi

# ==================== 3. 检查错误日志(502/504) ====================
print_info ""
print_info "3. 检查错误日志(502/504)..."
print_separator

if [ -f "$ERROR_LOG" ]; then
    # 获取最近1小时的错误日志
    RECENT_ERRORS=$(find "$ERROR_LOG" -mmin -60 -type f 2>/dev/null)

    # 统计各类错误
    ERROR_502=$(grep -c "502" "$ERROR_LOG" 2>/dev/null || echo "0")
    ERROR_504=$(grep -c "504" "$ERROR_LOG" 2>/dev/null || echo "0")
    ERROR_UPSTREAM=$(grep -c "upstream" "$ERROR_LOG" 2>/dev/null || echo "0")
    ERROR_CONN_REFUSED=$(grep -c "Connection refused" "$ERROR_LOG" 2>/dev/null || echo "0")
    ERROR_TIMEOUT=$(grep -c "timed out" "$ERROR_LOG" 2>/dev/null || echo "0")

    print_info "错误日志文件: ${ERROR_LOG}"
    print_info "502错误数量: ${ERROR_502}"
    print_info "504错误数量: ${ERROR_504}"
    print_info "upstream相关错误: ${ERROR_UPSTREAM}"
    print_info "Connection refused: ${ERROR_CONN_REFUSED}"
    print_info "超时错误: ${ERROR_TIMEOUT}"

    # 判断502/504情况
    if [ "$ERROR_502" -gt 100 ]; then
        print_fail "502错误过多 (${ERROR_502}次)，后端服务频繁不可用！"
        print_info "建议: 1)检查后端服务是否存活 2)检查upstream配置 3)检查后端健康检查"
        ((FAIL_COUNT++))
    elif [ "$ERROR_502" -gt 10 ]; then
        print_warn "存在较多502错误 (${ERROR_502}次)，后端服务偶尔不可用"
        ((WARN_COUNT++))
    else
        print_ok "502错误数量正常"
        ((OK_COUNT++))
    fi

    if [ "$ERROR_504" -gt 100 ]; then
        print_fail "504错误过多 (${ERROR_504}次)，后端服务响应超时！"
        print_info "建议: 1)检查后端服务性能 2)增大proxy_read_timeout 3)优化后端处理逻辑"
        ((FAIL_COUNT++))
    elif [ "$ERROR_504" -gt 10 ]; then
        print_warn "存在较多504错误 (${ERROR_504}次)，后端服务偶尔超时"
        ((WARN_COUNT++))
    else
        print_ok "504错误数量正常"
        ((OK_COUNT++))
    fi

    if [ "$ERROR_CONN_REFUSED" -gt 50 ]; then
        print_fail "Connection refused错误过多 (${ERROR_CONN_REFUSED}次)，后端服务拒绝连接"
        ((FAIL_COUNT++))
    elif [ "$ERROR_CONN_REFUSED" -gt 5 ]; then
        print_warn "存在Connection refused错误 (${ERROR_CONN_REFUSED}次)"
        ((WARN_COUNT++))
    fi

    # 显示最近50条错误日志
    RECENT_ERROR_LINES=$(tail -50 "$ERROR_LOG" 2>/dev/null)
    if [ -n "$RECENT_ERROR_LINES" ]; then
        echo ""
        print_info "最近50条错误日志:"
        echo "$RECENT_ERROR_LINES" | tail -20 | while read -r line; do
            print_info "  ${line}"
        done
    fi
else
    print_warn "错误日志文件不存在: ${ERROR_LOG}"
    print_info "请检查Nginx配置中的error_log路径"
    ((WARN_COUNT++))
fi

# ==================== 4. 检查连接数 ====================
print_info ""
print_info "4. 检查Nginx连接数..."
print_separator

# 检查80端口连接
CONN_80=$(ss -ant 2>/dev/null | grep -c ":80 " || netstat -ant 2>/dev/null | grep -c ":80 " || echo "0")
ESTAB_80=$(ss -ant 2>/dev/null | grep ":80 " | grep -c "ESTAB" || netstat -ant 2>/dev/null | grep ":80 " | grep -c "ESTABLISHED" || echo "0")
TIMEWAIT_80=$(ss -ant 2>/dev/null | grep ":80 " | grep -c "TIME-WAIT" || netstat -ant 2>/dev/null | grep ":80 " | grep -c "TIME_WAIT" || echo "0")
CLOSE_WAIT=$(ss -ant 2>/dev/null | grep -c "CLOSE-WAIT" || netstat -ant 2>/dev/null | grep -c "CLOSE_WAIT" || echo "0")

print_info "80端口总连接数: ${CONN_80}"
print_info "ESTABLISHED连接: ${ESTAB_80}"
print_info "TIME_WAIT连接: ${TIMEWAIT_80}"
print_info "CLOSE_WAIT连接: ${CLOSE_WAIT}"

# 检查443端口（如果存在）
CONN_443=$(ss -ant 2>/dev/null | grep -c ":443 " || netstat -ant 2>/dev/null | grep -c ":443 " || echo "0")
if [ "$CONN_443" -gt 0 ]; then
    print_info "443端口总连接数: ${CONN_443}"
fi

# 判断连接数
if [ "$ESTAB_80" -gt 5000 ]; then
    print_fail "并发连接数过高 (${ESTAB_80})，可能需要优化worker_connections或增加worker"
    ((FAIL_COUNT++))
elif [ "$ESTAB_80" -gt 2000 ]; then
    print_warn "并发连接数偏高 (${ESTAB_80})，建议关注"
    ((WARN_COUNT++))
else
    print_ok "连接数正常"
    ((OK_COUNT++))
fi

if [ "$CLOSE_WAIT" -gt 100 ]; then
    print_fail "CLOSE_WAIT连接过多 (${CLOSE_WAIT})，可能存在连接泄漏"
    print_info "建议: 1)检查后端服务是否正常关闭连接 2)检查keepalive配置 3)重启Nginx"
    ((FAIL_COUNT++))
elif [ "$CLOSE_WAIT" -gt 20 ]; then
    print_warn "CLOSE_WAIT连接偏多 (${CLOSE_WAIT})，建议关注"
    ((WARN_COUNT++))
fi

if [ "$TIMEWAIT_80" -gt 5000 ]; then
    print_warn "TIME_WAIT连接过多 (${TIMEWAIT_80})"
    print_info "建议: 开启keepalive复用连接，或调整tcp_tw_reuse"
    ((WARN_COUNT++))
fi

# ==================== 5. 检查后端健康状态 ====================
print_info ""
print_info "5. 检查后端服务健康状态..."
print_separator

# 从Nginx配置中提取upstream后端地址
if [ -f "$NGINX_CONF" ]; then
    # 提取upstream块中的server地址
    BACKEND_SERVERS=$(grep -A10 "upstream" "$NGINX_CONF" | grep "server" | grep -oP 'server\s+\K[^;]+' | head -10)

    if [ -n "$BACKEND_SERVERS" ]; then
        print_info "检测到以下后端服务器:"
        echo "$BACKEND_SERVERS" | while read -r backend; do
            # 提取host:port
            BACKEND_HOST=$(echo "$backend" | awk -F: '{print $1}' | awk '{print $1}')
            BACKEND_PORT=$(echo "$backend" | awk -F: '{print $2}' | awk '{print $1}')

            # 尝试TCP连接检测
            if timeout 3 bash -c "echo > /dev/tcp/${BACKEND_HOST}/${BACKEND_PORT}" 2>/dev/null; then
                print_ok "后端 ${BACKEND_HOST}:${BACKEND_PORT} 连通性正常"
            else
                print_fail "后端 ${BACKEND_HOST}:${BACKEND_PORT} 无法连接！这可能导致502错误"
                ((FAIL_COUNT++))
            fi
        done
    else
        # 尝试从conf.d目录查找
        if [ -d "/etc/nginx/conf.d" ]; then
            BACKEND_SERVERS=$(grep -rh "proxy_pass" /etc/nginx/conf.d/ 2>/dev/null | grep -oP 'http://\K[^/]+' | sort -u | head -10)
            if [ -n "$BACKEND_SERVERS" ]; then
                print_info "检测到以下后端服务器(通过proxy_pass):"
                echo "$BACKEND_SERVERS" | while read -r backend; do
                    BACKEND_HOST=$(echo "$backend" | awk -F: '{print $1}')
                    BACKEND_PORT=$(echo "$backend" | awk -F: '{print $2}')

                    if timeout 3 bash -c "echo > /dev/tcp/${BACKEND_HOST}/${BACKEND_PORT}" 2>/dev/null; then
                        print_ok "后端 ${BACKEND_HOST}:${BACKEND_PORT} 连通性正常"
                    else
                        print_fail "后端 ${BACKEND_HOST}:${BACKEND_PORT} 无法连接！"
                        ((FAIL_COUNT++))
                    fi
                done
            else
                print_warn "未在配置中找到upstream或proxy_pass后端地址"
                ((WARN_COUNT++))
            fi
        else
            print_warn "未找到后端配置信息"
            ((WARN_COUNT++))
        fi
    fi
else
    print_warn "无法检查后端状态（配置文件不可读）"
    ((WARN_COUNT++))
fi

# ==================== 6. 检查系统限制 ====================
print_info ""
print_info "6. 检查系统资源限制..."
print_separator

# 检查文件描述符限制
NOFILE_LIMIT=$(ulimit -n 2>/dev/null)
NOFILE_CONF=$(grep -E "^\s*worker_rlimit_nofile" "$NGINX_CONF" 2>/dev/null | awk '{print $2}' | tr -d ';')

print_info "当前ulimit -n: ${NOFILE_LIMIT}"
if [ -n "$NOFILE_CONF" ]; then
    print_info "Nginx配置worker_rlimit_nofile: ${NOFILE_CONF}"
fi

# 检查Nginx进程实际打开的文件描述符
if [ -n "$NGINX_MASTER_PID" ]; then
    NGINX_FDS=$(ls /proc/${NGINX_MASTER_PID}/fd 2>/dev/null | wc -l)
    print_info "Nginx Master进程打开的FD数: ${NGINX_FDS}"

    # 检查系统级文件描述符限制
    FS_FILE_MAX=$(cat /proc/sys/fs/file-max 2>/dev/null)
    FS_NR_OPEN=$(cat /proc/sys/fs/nr_open 2>/dev/null)
    print_info "系统fs.file-max: ${FS_FILE_MAX}"
    print_info "系统fs.nr_open: ${FS_NR_OPEN}"

    if [ "$NOFILE_LIMIT" -lt 65535 ]; then
        print_fail "文件描述符限制过低 (${NOFILE_LIMIT})！高并发下可能导致too many open files错误"
        print_info "建议: 在nginx.conf中设置 worker_rlimit_nofile 65535; 并在/etc/security/limits.conf中设置 * soft nofile 65535"
        ((FAIL_COUNT++))
    elif [ "$NOFILE_LIMIT" -lt 100000 ]; then
        print_warn "文件描述符限制偏小 (${NOFILE_LIMIT})，建议设为100000以上"
        ((WARN_COUNT++))
    else
        print_ok "文件描述符限制合理"
        ((OK_COUNT++))
    fi
fi

# 检查连接跟踪表
CONNTRACK_MAX=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)
CONNTRACK_COUNT=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null)

if [ -n "$CONNTRACK_MAX" ] && [ -n "$CONNTRACK_COUNT" ]; then
    CONNTRACK_RATIO=$((CONNTRACK_COUNT * 100 / CONNTRACK_MAX))
    print_info "连接跟踪表使用: ${CONNTRACK_COUNT} / ${CONNTRACK_MAX} (${CONNTRACK_RATIO}%)"

    if [ "$CONNTRACK_RATIO" -ge 90 ]; then
        print_fail "连接跟踪表即将满载！可能导致新连接被丢弃"
        print_info "建议: 增大net.netfilter.nf_conntrack_max或减少连接数"
        ((FAIL_COUNT++))
    elif [ "$CONNTRACK_RATIO" -ge 70 ]; then
        print_warn "连接跟踪表使用率偏高 (${CONNTRACK_RATIO}%)"
        ((WARN_COUNT++))
    else
        print_ok "连接跟踪表使用率正常"
        ((OK_COUNT++))
    fi
fi

# ==================== 7. 检查访问日志统计 ====================
print_info ""
print_info "7. 检查访问日志统计..."
print_separator

if [ -f "$ACCESS_LOG" ]; then
    # 最近1小时请求量
    RECENT_REQUESTS=$(awk -v date="$(date -d '1 hour ago' '+%d/%b/%Y:%H:%M')" '$0 ~ date' "$ACCESS_LOG" 2>/dev/null | wc -l)
    TOTAL_SIZE=$(du -sh "$ACCESS_LOG" 2>/dev/null | awk '{print $1}')

    print_info "访问日志文件大小: ${TOTAL_SIZE}"
    print_info "最近1小时请求量: ${RECENT_REQUESTS}"

    # 统计HTTP状态码分布（最近1000条）
    STATUS_CODES=$(tail -1000 "$ACCESS_LOG" 2>/dev/null | awk '{print $9}' | sort | uniq -c | sort -rn | head -10)
    if [ -n "$STATUS_CODES" ]; then
        print_info "最近1000条请求状态码分布:"
        echo "$STATUS_CODES" | while read -r count code; do
            if [ "$code" = "502" ] || [ "$code" = "504" ]; then
                print_fail "  ${code}: ${count}次"
            elif [ "$code" = "500" ] || [ "$code" = "503" ]; then
                print_warn "  ${code}: ${count}次"
            else
                print_info "  ${code}: ${count}次"
            fi
        done
    fi

    # 统计TOP 10访问IP
    TOP_IPS=$(tail -1000 "$ACCESS_LOG" 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn | head -5)
    if [ -n "$TOP_IPS" ]; then
        print_info "TOP 5访问IP:"
        echo "$TOP_IPS" | while read -r count ip; do
            print_info "  ${ip}: ${count}次"
        done
    fi

    print_ok "访问日志统计完成"
    ((OK_COUNT++))
else
    print_warn "访问日志文件不存在: ${ACCESS_LOG}"
    ((WARN_COUNT++))
fi

# ==================== 8. 检查Nginx性能指标 ====================
print_info ""
print_info "8. 检查Nginx性能指标..."
print_separator

# 检查stub_status（如果配置了）
STATUS_URL=$(grep -r "stub_status" "$NGINX_CONF" /etc/nginx/conf.d/ 2>/dev/null | grep "location" -A2 | grep -oP 'listen\s+\K[0-9]+' | head -1)

if [ -n "$STATUS_URL" ]; then
    STATUS_DATA=$(curl -s "http://127.0.0.1:${STATUS_URL}/nginx_status" 2>/dev/null)
    if [ -n "$STATUS_DATA" ]; then
        ACTIVE_CONN=$(echo "$STATUS_DATA" | grep "Active connections" | awk '{print $3}')
        ACCEPTS=$(echo "$STATUS_DATA" | awk 'NR==3 {print $1}')
        HANDLED=$(echo "$STATUS_DATA" | awk 'NR==3 {print $2}')
        REQUESTS=$(echo "$STATUS_DATA" | awk 'NR==3 {print $3}')
        READING=$(echo "$STATUS_DATA" | awk 'NR==4 {print $2}')
        WRITING=$(echo "$STATUS_DATA" | awk 'NR==4 {print $4}')
        WAITING=$(echo "$STATUS_DATA" | awk 'NR==4 {print $6}')

        print_info "Active connections: ${ACTIVE_CONN}"
        print_info "总接受连接: ${ACCEPTS}"
        print_info "总处理连接: ${HANDLED}"
        print_info "总请求数: ${REQUESTS}"
        print_info "Reading: ${READING} | Writing: ${WRITING} | Waiting: ${WAITING}"

        if [ "$HANDLED" -gt 0 ]; then
            DROP_RATE=$(( (ACCEPTS - HANDLED) * 100 / ACCEPTS ))
            if [ "$DROP_RATE" -gt 1 ]; then
                print_fail "连接丢弃率: ${DROP_RATE}%，Nginx无法处理所有连接请求！"
                ((FAIL_COUNT++))
            else
                print_ok "连接丢弃率正常 (${DROP_RATE}%)"
                ((OK_COUNT++))
            fi
        fi
    fi
else
    print_warn "未配置stub_status，无法获取Nginx性能指标"
    print_info "建议在nginx.conf中添加: location /nginx_status { stub_status; }"
    ((WARN_COUNT++))
fi

# ==================== 诊断结论汇总 ====================
echo ""
print_separator
echo ""
echo "==================== Nginx诊断结论汇总 ===================="
echo ""

TOTAL_CHECKS=$((OK_COUNT + WARN_COUNT + FAIL_COUNT))

echo -e "总检查项: ${TOTAL_CHECKS}  |  ${GREEN}正常: ${OK_COUNT}${NC}  |  ${YELLOW}警告: ${WARN_COUNT}${NC}  |  ${RED}异常: ${FAIL_COUNT}${NC}"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
    print_fail "Nginx存在 ${FAIL_COUNT} 个严重问题，需要立即处理！"
    echo ""
    print_info "常见修复方案:"
    echo "  1. 502错误 -> 检查后端服务是否存活，检查upstream配置"
    echo "  2. 504错误 -> 增大proxy_read_timeout，优化后端处理速度"
    echo "  3. 连接数满 -> 增大worker_connections和worker_rlimit_nofile"
    echo "  4. 文件描述符不足 -> 调整ulimit和系统fs.file-max"
    echo "  5. CLOSE_WAIT多 -> 检查后端服务keepalive配置"
elif [ "$WARN_COUNT" -gt 0 ]; then
    print_warn "Nginx存在 ${WARN_COUNT} 个警告项，建议持续关注"
    echo ""
    print_info "建议定期执行本脚本进行健康检查"
else
    print_ok "Nginx各项指标正常，运行健康"
fi

echo ""
print_separator
