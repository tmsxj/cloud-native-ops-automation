#!/bin/bash
# ============================================================================
# 模块36-日常巡检脚本
# 脚本名称: daily-check.sh
# 功能: 每日巡检，检查磁盘/证书/备份/资源/K8S集群/中间件等关键指标
# 用法: ./daily-check.sh [output-dir]
# 示例: ./daily-check.sh /tmp/daily-reports
# ============================================================================

# ======================== 颜色输出函数定义 ========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_info() { echo -e "[INFO] $1"; }

# ======================== 参数解析 ========================
OUTPUT_DIR="${1:-/tmp/daily-check}"
REPORT_DATE=$(date '+%Y-%m-%d')
REPORT_TIME=$(date '+%Y-%m-%d %H:%M:%S')

# ======================== 统计变量 ========================
FAIL_COUNT=0
WARN_COUNT=0
OK_COUNT=0
TOTAL_CHECKS=0

# ======================== 分隔线 ========================
print_separator() {
    echo "============================================================"
}

# ======================== 输出文件 ========================
REPORT_FILE="${OUTPUT_DIR}/daily-check-${REPORT_DATE}.log"
mkdir -p "$OUTPUT_DIR"

echo "============================================================"
print_info "每日巡检报告"
print_info "巡检日期: ${REPORT_DATE}"
print_info "巡检时间: ${REPORT_TIME}"
print_info "巡检主机: $(hostname)"
print_info "报告输出: ${REPORT_FILE}"
echo "============================================================"

# 重定向到文件和终端
exec > >(tee -a "$REPORT_FILE") 2>&1

# ======================== 1. 系统资源巡检 ========================
print_info ""
print_info ">>> [1/7] 系统资源巡检..."
print_separator

# 1.1 磁盘使用率
print_info "--- 磁盘使用率 ---"
DISK_WARN=80
DISK_CRIT=95

df -h | grep -vE "^Filesystem|tmpfs|cdrom|overlay" | while read -r line; do
    USAGE=$(echo "$line" | awk '{print $5}' | tr -d '%')
    MOUNT=$(echo "$line" | awk '{print $6}')
    TOTAL=$((TOTAL_CHECKS + 1))

    if [ "$USAGE" -ge "$DISK_CRIT" ]; then
        print_fail "磁盘 ${MOUNT} 使用率 ${USAGE}% (>=${DISK_CRIT}%, 严重!)"
    elif [ "$USAGE" -ge "$DISK_WARN" ]; then
        print_warn "磁盘 ${MOUNT} 使用率 ${USAGE}% (>=${DISK_WARN}%, 警告)"
    else
        print_ok "磁盘 ${MOUNT} 使用率 ${USAGE}%"
    fi
done

# 1.2 内存使用率
print_info ""
print_info "--- 内存使用率 ---"
MEM_TOTAL=$(free -m | awk '/Mem:/{print $2}')
MEM_USED=$(free -m | awk '/Mem:/{print $3}')
MEM_PERCENT=$((MEM_USED * 100 / MEM_TOTAL))

print_info "内存: 已用 ${MEM_USED}MB / 总共 ${MEM_TOTAL}MB (使用率: ${MEM_PERCENT}%)"

if [ "$MEM_PERCENT" -ge 90 ]; then
    print_fail "内存使用率过高 (${MEM_PERCENT}%)"
    ((FAIL_COUNT++))
elif [ "$MEM_PERCENT" -ge 80 ]; then
    print_warn "内存使用率偏高 (${MEM_PERCENT}%)"
    ((WARN_COUNT++))
else
    print_ok "内存使用率正常 (${MEM_PERCENT}%)"
    ((OK_COUNT++))
fi

# 1.3 CPU负载
print_info ""
print_info "--- CPU负载 ---"
CPU_CORES=$(nproc)
LOAD_1M=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
LOAD_INT=$(echo "$LOAD_1M" | awk '{printf "%d", $1}')

print_info "CPU核心数: ${CPU_CORES}, 1分钟负载: ${LOAD_1M}"

if [ "$LOAD_INT" -gt $((CPU_CORES * 2)) ]; then
    print_fail "系统负载过高 (${LOAD_1M} > 核心*2)"
    ((FAIL_COUNT++))
elif [ "$LOAD_INT" -gt "$CPU_CORES" ]; then
    print_warn "系统负载偏高 (${LOAD_1M} > 核心数)"
    ((WARN_COUNT++))
else
    print_ok "系统负载正常 (${LOAD_1M})"
    ((OK_COUNT++))
fi

# 1.4 僵尸进程
print_info ""
print_info "--- 僵尸进程 ---"
ZOMBIE_COUNT=$(ps aux | awk '$8 ~ /Z/ {print}' | wc -l)

if [ "$ZOMBIE_COUNT" -gt 0 ]; then
    print_fail "发现 ${ZOMBIE_COUNT} 个僵尸进程"
    ps aux | awk '$8 ~ /Z/ {print}' | while read -r line; do
        print_fail "  $line"
    done
    ((FAIL_COUNT++))
else
    print_ok "无僵尸进程"
    ((OK_COUNT++))
fi

# ======================== 2. 磁盘Inode巡检 ========================
print_info ""
print_info ">>> [2/7] 磁盘Inode巡检..."
print_separator

INODE_WARN=80
df -i | grep -vE "^Filesystem|tmpfs|cdrom|overlay" | while read -r line; do
    INODE_USAGE=$(echo "$line" | awk '{print $5}' | tr -d '%')
    MOUNT=$(echo "$line" | awk '{print $6}')

    if [ "$INODE_USAGE" -ge "$INODE_WARN" ]; then
        print_warn "磁盘 ${MOUNT} Inode使用率 ${INODE_USAGE}%"
    else
        print_ok "磁盘 ${MOUNT} Inode使用率 ${INODE_USAGE}%"
    fi
done

# ======================== 3. SSL证书巡检 ========================
print_info ""
print_info ">>> [3/7] SSL证书有效期巡检..."
print_separator

CERT_WARN_DAYS=30
CERT_CRIT_DAYS=7

# 检查常见证书路径
CERT_PATHS=(
    "/etc/letsencrypt/live"
    "/etc/nginx/ssl"
    "/etc/pki/tls/certs"
    "/opt/certs"
)

CERT_CHECKED=false

for cert_dir in "${CERT_PATHS[@]}"; do
    if [ -d "$cert_dir" ]; then
        # 查找证书文件
        CERTS=$(find "$cert_dir" -name "*.pem" -o -name "*.crt" -o -name "fullchain.pem" 2>/dev/null)
        for cert in $CERTS; do
            CERT_CHECKED=true
            if command -v openssl &>/dev/null; then
                EXPIRY_DATE=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2)
                if [ -n "$EXPIRY_DATE" ]; then
                    EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null)
                    NOW_EPOCH=$(date +%s)
                    DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

                    if [ "$DAYS_LEFT" -lt 0 ]; then
                        print_fail "证书已过期: ${cert} (过期于 ${EXPIRY_DATE})"
                        ((FAIL_COUNT++))
                    elif [ "$DAYS_LEFT" -lt "$CERT_CRIT_DAYS" ]; then
                        print_fail "证书即将过期: ${cert} (剩余 ${DAYS_LEFT} 天, ${EXPIRY_DATE})"
                        ((FAIL_COUNT++))
                    elif [ "$DAYS_LEFT" -lt "$CERT_WARN_DAYS" ]; then
                        print_warn "证书即将过期: ${cert} (剩余 ${DAYS_LEFT} 天, ${EXPIRY_DATE})"
                        ((WARN_COUNT++))
                    else
                        print_ok "证书有效: ${cert} (剩余 ${DAYS_LEFT} 天)"
                        ((OK_COUNT++))
                    fi
                fi
            fi
        done
    fi
done

if [ "$CERT_CHECKED" = false ]; then
    print_info "未找到本地证书文件，跳过证书检查"
    print_info "如需检查远程证书，可传入域名参数"
fi

# ======================== 4. 备份巡检 ========================
print_info ""
print_info ">>> [4/7] 备份文件巡检..."
print_separator

BACKUP_DIRS=(
    "/data/backup"
    "/backup"
    "/var/backup"
    "/opt/backup"
)

BACKUP_CHECKED=false
BACKUP_MAX_AGE_DAYS=2  # 备份文件最大允许天数

for backup_dir in "${BACKUP_DIRS[@]}"; do
    if [ -d "$backup_dir" ]; then
        BACKUP_CHECKED=true
        BACKUP_COUNT=$(find "$backup_dir" -type f -mtime -"$BACKUP_MAX_AGE_DAYS" 2>/dev/null | wc -l)
        LATEST_BACKUP=$(find "$backup_dir" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
        LATEST_TIME=$(find "$backup_dir" -type f -printf '%T+ %p\n' 2>/dev/null | sort -r | head -1 | awk '{print $1}')

        print_info "备份目录: ${backup_dir}"
        print_info "最近${BACKUP_MAX_AGE_DAYS}天备份文件数: ${BACKUP_COUNT}"

        if [ "$BACKUP_COUNT" -eq 0 ]; then
            print_fail "最近${BACKUP_MAX_AGE_DAYS}天无备份文件！"
            ((FAIL_COUNT++))
        elif [ -n "$LATEST_BACKUP" ]; then
            print_ok "最新备份: ${LATEST_BACKUP} (${LATEST_TIME})"
            ((OK_COUNT++))
        else
            print_warn "备份目录存在但无文件"
            ((WARN_COUNT++))
        fi
    fi
done

if [ "$BACKUP_CHECKED" = false ]; then
    print_info "未找到备份目录，跳过备份检查"
fi

# ======================== 5. K8S集群巡检 ========================
print_info ""
print_info ">>> [5/7] K8S集群巡检..."
print_separator

if command -v kubectl &>/dev/null; then
    # 5.1 节点状态
    print_info "--- 节点状态 ---"
    NODE_TOTAL=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    NODE_READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || true)
    NODE_NOT_READY=$((NODE_TOTAL - NODE_READY))

    print_info "节点总数: ${NODE_TOTAL}, 就绪: ${NODE_READY}, 未就绪: ${NODE_NOT_READY}"

    if [ "$NODE_NOT_READY" -gt 0 ]; then
        print_fail "有 ${NODE_NOT_READY} 个节点未就绪"
        kubectl get nodes --no-headers 2>/dev/null | grep -v "Ready" | while read -r line; do
            print_fail "  $line"
        done
        ((FAIL_COUNT++))
    else
        print_ok "所有节点就绪"
        ((OK_COUNT++))
    fi

    # 5.2 异常Pod
    print_info ""
    print_info "--- 异常Pod ---"
    ABNORMAL_PODS=$(kubectl get pods -A --no-headers 2>/dev/null | grep -E "CrashLoop|Error|OOMKilled|Pending|ImagePull|ContainerStatusUnknown" || true)
    if [ -z "$ABNORMAL_PODS" ]; then
        print_ok "无异常Pod"
        ((OK_COUNT++))
    else
        ABNORMAL_COUNT=$(echo "$ABNORMAL_PODS" | wc -l)
        print_fail "发现 ${ABNORMAL_COUNT} 个异常Pod:"
        echo "$ABNORMAL_PODS" | while read -r line; do
            print_fail "  $line"
        done
        ((FAIL_COUNT++))
    fi

    # 5.3 PVC状态
    print_info ""
    print_info "--- PVC状态 ---"
    PVC_PENDING=$(kubectl get pvc -A --no-headers 2>/dev/null | grep -i "Pending\|Lost" || true)
    if [ -z "$PVC_PENDING" ]; then
        print_ok "PVC状态正常"
        ((OK_COUNT++))
    else
        print_fail "存在异常PVC:"
        echo "$PVC_PENDING" | while read -r line; do
            print_fail "  $line"
        done
        ((FAIL_COUNT++))
    fi
else
    print_info "kubectl不可用，跳过K8S巡检"
fi

# ======================== 6. 中间件巡检 ========================
print_info ""
print_info ">>> [6/7] 中间件巡检..."
print_separator

# 6.1 MySQL检查
if pgrep -x "mysqld" > /dev/null 2>&1 || pgrep -x "mariadbd" > /dev/null 2>&1; then
    print_info "--- MySQL ---"
    MYSQL_CONN=$(ss -tan | grep ":3306" | grep -c "ESTAB" || true)
    print_info "MySQL运行中, 当前连接数: ${MYSQL_CONN}"

    if [ "$MYSQL_CONN" -gt 200 ]; then
        print_warn "MySQL连接数偏高 (${MYSQL_CONN})"
        ((WARN_COUNT++))
    else
        print_ok "MySQL连接数正常"
        ((OK_COUNT++))
    fi
else
    print_info "MySQL未运行 (本机)"
fi

# 6.2 Redis检查
if pgrep -x "redis-server" > /dev/null 2>&1; then
    print_info ""
    print_info "--- Redis ---"
    REDIS_CONN=$(ss -tan | grep ":6379" | grep -c "ESTAB" || true)
    print_info "Redis运行中, 当前连接数: ${REDIS_CONN}"

    if [ "$REDIS_CONN" -gt 500 ]; then
        print_warn "Redis连接数偏高 (${REDIS_CONN})"
        ((WARN_COUNT++))
    else
        print_ok "Redis连接数正常"
        ((OK_COUNT++))
    fi
else
    print_info "Redis未运行 (本机)"
fi

# 6.3 Nginx检查
if pgrep -x "nginx" > /dev/null 2>&1; then
    print_info ""
    print_info "--- Nginx ---"
    NGINX_CONN=$(ss -tan | grep ":80\|:443" | grep -c "ESTAB" || true)
    print_info "Nginx运行中, 当前连接数: ${NGINX_CONN}"

    if [ "$NGINX_CONN" -gt 5000 ]; then
        print_warn "Nginx连接数偏高 (${NGINX_CONN})"
        ((WARN_COUNT++))
    else
        print_ok "Nginx连接数正常"
        ((OK_COUNT++))
    fi
else
    print_info "Nginx未运行 (本机)"
fi

# ======================== 7. 安全巡检 ========================
print_info ""
print_info ">>> [7/7] 安全巡检..."
print_separator

# 7.1 SSH配置
SSH_CONFIG="/etc/ssh/sshd_config"
if [ -f "$SSH_CONFIG" ]; then
    ROOT_LOGIN=$(grep -i "^PermitRootLogin" "$SSH_CONFIG" 2>/dev/null | awk '{print $2}')
    PASS_AUTH=$(grep -i "^PasswordAuthentication" "$SSH_CONFIG" 2>/dev/null | awk '{print $2}')

    if [ "$ROOT_LOGIN" = "yes" ]; then
        print_warn "SSH允许Root直接登录 (PermitRootLogin yes)"
        ((WARN_COUNT++))
    else
        print_ok "SSH Root登录已限制"
        ((OK_COUNT++))
    fi

    if [ "$PASS_AUTH" = "yes" ]; then
        print_warn "SSH允许密码认证 (PasswordAuthentication yes)，建议使用密钥认证"
        ((WARN_COUNT++))
    else
        print_ok "SSH密码认证已限制"
        ((OK_COUNT++))
    fi
fi

# 7.2 防火墙状态
if command -v systemctl &>/dev/null; then
    if systemctl is-active --quiet firewalld 2>/dev/null; then
        print_ok "firewalld防火墙运行中"
        ((OK_COUNT++))
    elif systemctl is-active --quiet ufw 2>/dev/null; then
        print_ok "ufw防火墙运行中"
        ((OK_COUNT++))
    elif systemctl is-active --quiet iptables 2>/dev/null; then
        print_info "iptables服务运行中"
        ((OK_COUNT++))
    else
        print_warn "未检测到防火墙服务"
        ((WARN_COUNT++))
    fi
fi

# 7.3 可疑进程
SUSPICIOUS=$(ps aux | grep -iE "miner|crypto|xmrig|kworkerds" | grep -v grep || true)
if [ -n "$SUSPICIOUS" ]; then
    print_fail "发现可疑进程(挖矿/恶意软件):"
    echo "$SUSPICIOUS" | while read -r line; do
        print_fail "  $line"
    done
    ((FAIL_COUNT++))
else
    print_ok "无可疑进程"
    ((OK_COUNT++))
fi

# ======================== 巡检总结 ========================
echo ""
print_separator
echo ""
echo "==================== 每日巡检总结 ===================="
echo ""

TOTAL_CHECKS=$((OK_COUNT + WARN_COUNT + FAIL_COUNT))

echo -e "总检查项: ${TOTAL_CHECKS}  |  ${GREEN}正常: ${OK_COUNT}${NC}  |  ${YELLOW}警告: ${WARN_COUNT}${NC}  |  ${RED}异常: ${FAIL_COUNT}${NC}"
echo ""
print_info "巡检日期: ${REPORT_DATE}"
print_info "巡检主机: $(hostname)"
print_info "报告文件: ${REPORT_FILE}"

if [ "$FAIL_COUNT" -gt 0 ]; then
    print_fail "结论: 巡检发现 ${FAIL_COUNT} 个异常项，需要立即处理！"
    print_info "建议: 1.查看报告详情 2.按优先级处理异常项 3.处理后重新巡检"
elif [ "$WARN_COUNT" -gt 0 ]; then
    print_warn "结论: 巡检发现 ${WARN_COUNT} 个警告项，建议关注处理"
else
    print_ok "结论: 巡检通过，所有检查项正常"
fi

echo ""
print_separator
