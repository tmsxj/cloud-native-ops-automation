#!/bin/bash
# ============================================================================
# 模块36-日常巡检脚本
# 脚本名称: daily-check-auto.sh
# 功能: 自动化巡检 + 企业微信推送报告，支持cron定时执行
# 用法: ./daily-check-auto.sh [webhook-url] [output-dir]
# 示例: ./daily-check-auto.sh "https://qyapi.weixin.qq.com/..." /tmp/daily-reports
#
# 环境变量:
#   WECHAT_WEBHOOK_URL  企业微信机器人Webhook地址（设置后可省略第一个参数）
#   DAILY_CHECK_DIR     巡检报告输出目录（默认 /tmp/daily-check）
#
# Cron配置示例（每天09:00执行）:
#   0 9 * * * /path/to/daily-check-auto.sh "https://qyapi.weixin.qq.com/..." /data/daily-reports >> /var/log/daily-check.log 2>&1
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
WEBHOOK_URL="${1:-${WECHAT_WEBHOOK_URL:-}}"
OUTPUT_DIR="${2:-${DAILY_CHECK_DIR:-/tmp/daily-check}}"
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

# 用于拼接企业微信消息的缓冲区
WX_MSG="## 卡儿酷每日巡检报告\n\n> 日期: ${REPORT_DATE}\n> 主机: $(hostname)\n\n"

echo "============================================================"
print_info "每日自动化巡检"
print_info "巡检日期: ${REPORT_DATE}"
print_info "巡检时间: ${REPORT_TIME}"
print_info "报告输出: ${REPORT_FILE}"
echo "============================================================"

# 重定向到文件和终端
exec > >(tee -a "$REPORT_FILE") 2>&1

# ======================== 1. 系统资源巡检 ========================
print_info ""
print_info ">>> [1/7] 系统资源巡检..."
print_separator

WX_MSG="${WX_MSG}### 1. 系统资源\n"

# 1.1 磁盘使用率
DISK_WARN=80
DISK_CRIT=95
DISK_ISSUES=""

while read -r line; do
    USAGE=$(echo "$line" | awk '{print $5}' | tr -d '%')
    MOUNT=$(echo "$line" | awk '{print $6}')
    [ -z "$USAGE" ] && continue
    [ "$USAGE" -eq "$USAGE" ] 2>/dev/null || continue

    if [ "$USAGE" -ge "$DISK_CRIT" ]; then
        print_fail "磁盘 ${MOUNT} 使用率 ${USAGE}% (>=${DISK_CRIT}%, 严重!)"
        DISK_ISSUES="${DISK_ISSUES}- ❌ **${MOUNT}**: ${USAGE}% (严重)\n"
        ((FAIL_COUNT++))
    elif [ "$USAGE" -ge "$DISK_WARN" ]; then
        print_warn "磁盘 ${MOUNT} 使用率 ${USAGE}% (>=${DISK_WARN}%, 警告)"
        DISK_ISSUES="${DISK_ISSUES}- ⚠️ **${MOUNT}**: ${USAGE}% (警告)\n"
        ((WARN_COUNT++))
    else
        print_ok "磁盘 ${MOUNT} 使用率 ${USAGE}%"
        ((OK_COUNT++))
    fi
done < <(df -h | grep -vE "^Filesystem|tmpfs|cdrom|overlay")

if [ -z "$DISK_ISSUES" ]; then
    WX_MSG="${WX_MSG}✅ 磁盘使用率正常\n\n"
else
    WX_MSG="${WX_MSG}${DISK_ISSUES}\n"
fi

# 1.2 内存使用率
MEM_TOTAL=$(free -m | awk '/Mem:/{print $2}')
MEM_USED=$(free -m | awk '/Mem:/{print $3}')
MEM_PERCENT=$((MEM_USED * 100 / MEM_TOTAL))

print_info ""
print_info "内存: 已用 ${MEM_USED}MB / 总共 ${MEM_TOTAL}MB (使用率: ${MEM_PERCENT}%)"

if [ "$MEM_PERCENT" -ge 90 ]; then
    print_fail "内存使用率过高 (${MEM_PERCENT}%)"
    WX_MSG="${WX_MSG}❌ **内存**: ${MEM_PERCENT}% (过高)\n"
    ((FAIL_COUNT++))
elif [ "$MEM_PERCENT" -ge 80 ]; then
    print_warn "内存使用率偏高 (${MEM_PERCENT}%)"
    WX_MSG="${WX_MSG}⚠️ **内存**: ${MEM_PERCENT}% (偏高)\n"
    ((WARN_COUNT++))
else
    print_ok "内存使用率正常 (${MEM_PERCENT}%)"
    WX_MSG="${WX_MSG}✅ **内存**: ${MEM_PERCENT}% (正常)\n"
fi

# 1.3 CPU负载
CPU_CORES=$(nproc)
LOAD_1M=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
LOAD_INT=$(echo "$LOAD_1M" | awk '{printf "%d", $1}')

print_info ""
print_info "CPU核心数: ${CPU_CORES}, 1分钟负载: ${LOAD_1M}"

if [ "$LOAD_INT" -gt $((CPU_CORES * 2)) ]; then
    print_fail "系统负载过高 (${LOAD_1M})"
    WX_MSG="${WX_MSG}❌ **CPU负载**: ${LOAD_1M} (过高)\n"
    ((FAIL_COUNT++))
elif [ "$LOAD_INT" -gt "$CPU_CORES" ]; then
    print_warn "系统负载偏高 (${LOAD_1M})"
    WX_MSG="${WX_MSG}⚠️ **CPU负载**: ${LOAD_1M} (偏高)\n"
    ((WARN_COUNT++))
else
    print_ok "系统负载正常 (${LOAD_1M})"
    WX_MSG="${WX_MSG}✅ **CPU负载**: ${LOAD_1M} (正常)\n"
fi

WX_MSG="${WX_MSG}\n"

# ======================== 2. SSL证书巡检 ========================
print_info ""
print_info ">>> [2/7] SSL证书有效期巡检..."
print_separator

WX_MSG="${WX_MSG}### 2. SSL证书\n"

CERT_WARN_DAYS=30
CERT_CRIT_DAYS=7
CERT_ISSUES=""

for cert_dir in /etc/letsencrypt/live /etc/nginx/ssl /etc/pki/tls/certs /opt/certs; do
    [ -d "$cert_dir" ] || continue
    for cert in $(find "$cert_dir" -name "*.pem" -o -name "*.crt" -o -name "fullchain.pem" 2>/dev/null); do
        [ -f "$cert" ] || continue
        EXPIRY_DATE=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2)
        [ -z "$EXPIRY_DATE" ] && continue

        EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null)
        NOW_EPOCH=$(date +%s)
        DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

        if [ "$DAYS_LEFT" -lt 0 ]; then
            print_fail "证书已过期: ${cert}"
            CERT_ISSUES="${CERT_ISSUES}- ❌ **${cert}**: 已过期\n"
            ((FAIL_COUNT++))
        elif [ "$DAYS_LEFT" -lt "$CERT_CRIT_DAYS" ]; then
            print_fail "证书即将过期: ${cert} (剩余 ${DAYS_LEFT} 天)"
            CERT_ISSUES="${CERT_ISSUES}- ❌ **${cert}**: 剩余${DAYS_LEFT}天\n"
            ((FAIL_COUNT++))
        elif [ "$DAYS_LEFT" -lt "$CERT_WARN_DAYS" ]; then
            print_warn "证书即将过期: ${cert} (剩余 ${DAYS_LEFT} 天)"
            CERT_ISSUES="${CERT_ISSUES}- ⚠️ **${cert}**: 剩余${DAYS_LEFT}天\n"
            ((WARN_COUNT++))
        else
            print_ok "证书有效: ${cert} (剩余 ${DAYS_LEFT} 天)"
            ((OK_COUNT++))
        fi
    done
done

if [ -z "$CERT_ISSUES" ]; then
    WX_MSG="${WX_MSG}✅ 证书有效期正常\n\n"
else
    WX_MSG="${WX_MSG}${CERT_ISSUES}\n"
fi

# ======================== 3. 备份巡检 ========================
print_info ""
print_info ">>> [3/7] 备份文件巡检..."
print_separator

WX_MSG="${WX_MSG}### 3. 备份检查\n"

BACKUP_ISSUES=""

for backup_dir in /data/backup /backup /var/backup /opt/backup; do
    [ -d "$backup_dir" ] || continue
    BACKUP_COUNT=$(find "$backup_dir" -type f -mtime -2 2>/dev/null | wc -l)
    LATEST_BACKUP=$(find "$backup_dir" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
    LATEST_TIME=$(find "$backup_dir" -type f -printf '%T+ %p\n' 2>/dev/null | sort -r | head -1 | awk '{print $1}')

    if [ "$BACKUP_COUNT" -eq 0 ]; then
        print_fail "备份目录 ${backup_dir} 最近2天无备份文件!"
        BACKUP_ISSUES="${BACKUP_ISSUES}- ❌ **${backup_dir}**: 无近期备份\n"
        ((FAIL_COUNT++))
    else
        print_ok "备份目录 ${backup_dir}: ${BACKUP_COUNT}个文件, 最新: ${LATEST_TIME}"
        ((OK_COUNT++))
    fi
done

if [ -z "$BACKUP_ISSUES" ]; then
    WX_MSG="${WX_MSG}✅ 备份文件正常\n\n"
else
    WX_MSG="${WX_MSG}${BACKUP_ISSUES}\n"
fi

# ======================== 4. K8S集群巡检 ========================
print_info ""
print_info ">>> [4/7] K8S集群巡检..."
print_separator

WX_MSG="${WX_MSG}### 4. K8S集群\n"

if command -v kubectl &>/dev/null; then
    # 节点状态
    NODE_TOTAL=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    NODE_READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || true)
    NODE_NOT_READY=$((NODE_TOTAL - NODE_READY))

    print_info "节点: 总数${NODE_TOTAL}, 就绪${NODE_READY}, 未就绪${NODE_NOT_READY}"

    if [ "$NODE_NOT_READY" -gt 0 ]; then
        print_fail "有 ${NODE_NOT_READY} 个节点未就绪"
        WX_MSG="${WX_MSG}❌ **节点**: ${NODE_NOT_READY}个未就绪\n"
        ((FAIL_COUNT++))
    else
        print_ok "所有节点就绪"
        WX_MSG="${WX_MSG}✅ **节点**: 全部就绪 (${NODE_TOTAL}个)\n"
        ((OK_COUNT++))
    fi

    # 异常Pod
    ABNORMAL_PODS=$(kubectl get pods -A --no-headers 2>/dev/null | grep -E "CrashLoop|Error|OOMKilled|Pending|ImagePull" || true)
    if [ -z "$ABNORMAL_PODS" ]; then
        print_ok "无异常Pod"
        WX_MSG="${WX_MSG}✅ **Pod**: 无异常\n"
        ((OK_COUNT++))
    else
        ABNORMAL_COUNT=$(echo "$ABNORMAL_PODS" | wc -l)
        print_fail "发现 ${ABNORMAL_COUNT} 个异常Pod"
        # 取前5个显示
        echo "$ABNORMAL_PODS" | head -5 | while read -r line; do
            print_fail "  $line"
        done
        WX_MSG="${WX_MSG}❌ **Pod**: ${ABNORMAL_COUNT}个异常\n"
        ((FAIL_COUNT++))
    fi

    # PVC状态
    PVC_PENDING=$(kubectl get pvc -A --no-headers 2>/dev/null | grep -iE "Pending|Lost" || true)
    if [ -z "$PVC_PENDING" ]; then
        print_ok "PVC状态正常"
        ((OK_COUNT++))
    else
        print_fail "存在异常PVC"
        WX_MSG="${WX_MSG}❌ **PVC**: 存在Pending/Lost\n"
        ((FAIL_COUNT++))
    fi
else
    print_info "kubectl不可用，跳过K8S巡检"
    WX_MSG="${WX_MSG}⚠️ kubectl不可用，跳过\n"
fi

WX_MSG="${WX_MSG}\n"

# ======================== 5. 中间件巡检 ========================
print_info ""
print_info ">>> [5/7] 中间件巡检..."
print_separator

WX_MSG="${WX_MSG}### 5. 中间件\n"

# MySQL
if pgrep -x "mysqld" > /dev/null 2>&1 || pgrep -x "mariadbd" > /dev/null 2>&1; then
    MYSQL_CONN=$(ss -tan | grep ":3306" | grep -c "ESTAB" || true)
    print_info "MySQL运行中, 连接数: ${MYSQL_CONN}"
    if [ "$MYSQL_CONN" -gt 200 ]; then
        print_warn "MySQL连接数偏高 (${MYSQL_CONN})"
        WX_MSG="${WX_MSG}⚠️ **MySQL**: 连接数${MYSQL_CONN}\n"
        ((WARN_COUNT++))
    else
        print_ok "MySQL连接数正常"
        WX_MSG="${WX_MSG}✅ **MySQL**: 正常 (连接数${MYSQL_CONN})\n"
        ((OK_COUNT++))
    fi
else
    print_info "MySQL未运行 (本机)"
    WX_MSG="${WX_MSG}ℹ️ **MySQL**: 未运行\n"
fi

# Redis
if pgrep -x "redis-server" > /dev/null 2>&1; then
    REDIS_CONN=$(ss -tan | grep ":6379" | grep -c "ESTAB" || true)
    print_info "Redis运行中, 连接数: ${REDIS_CONN}"
    if [ "$REDIS_CONN" -gt 500 ]; then
        print_warn "Redis连接数偏高 (${REDIS_CONN})"
        WX_MSG="${WX_MSG}⚠️ **Redis**: 连接数${REDIS_CONN}\n"
        ((WARN_COUNT++))
    else
        print_ok "Redis连接数正常"
        WX_MSG="${WX_MSG}✅ **Redis**: 正常 (连接数${REDIS_CONN})\n"
        ((OK_COUNT++))
    fi
else
    print_info "Redis未运行 (本机)"
    WX_MSG="${WX_MSG}ℹ️ **Redis**: 未运行\n"
fi

# EMQX (MQTT Broker)
if pgrep -f "emqx" > /dev/null 2>&1; then
    EMQX_CONN=$(ss -tan | grep ":1883\|:8083\|:8883" | grep -c "ESTAB" || true)
    print_info "EMQX运行中, MQTT连接数: ${EMQX_CONN}"
    if [ "$EMQX_CONN" -lt 10 ]; then
        print_warn "EMQX连接数过低 (${EMQX_CONN})，可能BMS设备离线"
        WX_MSG="${WX_MSG}⚠️ **EMQX**: 连接数${EMQX_CONN} (偏低，可能设备离线)\n"
        ((WARN_COUNT++))
    else
        print_ok "EMQX连接数正常"
        WX_MSG="${WX_MSG}✅ **EMQX**: 正常 (连接数${EMQX_CONN})\n"
        ((OK_COUNT++))
    fi
else
    print_info "EMQX未运行 (本机)"
    WX_MSG="${WX_MSG}ℹ️ **EMQX**: 未运行\n"
fi

WX_MSG="${WX_MSG}\n"

# ======================== 6. 安全巡检 ========================
print_info ""
print_info ">>> [6/7] 安全巡检..."
print_separator

WX_MSG="${WX_MSG}### 6. 安全\n"

SECURITY_ISSUES=""

# SSH配置
SSH_CONFIG="/etc/ssh/sshd_config"
if [ -f "$SSH_CONFIG" ]; then
    ROOT_LOGIN=$(grep -iE "^PermitRootLogin" "$SSH_CONFIG" 2>/dev/null | awk '{print $2}')
    if [ "$ROOT_LOGIN" = "yes" ]; then
        print_warn "SSH允许Root直接登录"
        SECURITY_ISSUES="${SECURITY_ISSUES}- ⚠️ SSH允许Root登录\n"
        ((WARN_COUNT++))
    else
        print_ok "SSH Root登录已限制"
        ((OK_COUNT++))
    fi
fi

# 可疑进程
SUSPICIOUS=$(ps aux | grep -iE "miner|crypto|xmrig|kworkerds" | grep -v grep || true)
if [ -n "$SUSPICIOUS" ]; then
    print_fail "发现可疑进程!"
    SECURITY_ISSUES="${SECURITY_ISSUES}- ❌ 发现可疑进程\n"
    ((FAIL_COUNT++))
else
    print_ok "无可疑进程"
    ((OK_COUNT++))
fi

if [ -z "$SECURITY_ISSUES" ]; then
    WX_MSG="${WX_MSG}✅ 安全检查正常\n\n"
else
    WX_MSG="${WX_MSG}${SECURITY_ISSUES}\n"
fi

# ======================== 7. 运行时长与僵尸进程 ========================
print_info ""
print_info ">>> [7/7] 系统健康检查..."
print_separator

WX_MSG="${WX_MSG}### 7. 系统健康\n"

# 运行时长
UPTIME_DAYS=$(uptime -p | grep -oP 'up \K[^,]+' || uptime | awk '{print $3,$4}')
print_info "系统运行时长: ${UPTIME_DAYS}"
WX_MSG="${WX_MSG}ℹ️ 运行时长: ${UPTIME_DAYS}\n"

# 僵尸进程
ZOMBIE_COUNT=$(ps aux | awk '$8 ~ /Z/ {print}' | wc -l)
if [ "$ZOMBIE_COUNT" -gt 0 ]; then
    print_fail "发现 ${ZOMBIE_COUNT} 个僵尸进程"
    WX_MSG="${WX_MSG}❌ 僵尸进程: ${ZOMBIE_COUNT}个\n"
    ((FAIL_COUNT++))
else
    print_ok "无僵尸进程"
    WX_MSG="${WX_MSG}✅ 无僵尸进程\n"
    ((OK_COUNT++))
fi

WX_MSG="${WX_MSG}\n"

# ======================== 巡检总结 ========================
echo ""
print_separator
echo ""
echo "==================== 每日巡检总结 ===================="
echo ""

TOTAL_CHECKS=$((OK_COUNT + WARN_COUNT + FAIL_COUNT))

echo -e "总检查项: ${TOTAL_CHECKS}  |  ${GREEN}正常: ${OK_COUNT}${NC}  |  ${YELLOW}警告: ${WARN_COUNT}${NC}  |  ${RED}异常: ${FAIL_COUNT}${NC}"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
    print_fail "结论: 巡检发现 ${FAIL_COUNT} 个异常项，需要立即处理！"
elif [ "$WARN_COUNT" -gt 0 ]; then
    print_warn "结论: 巡检发现 ${WARN_COUNT} 个警告项，建议关注"
else
    print_ok "结论: 巡检通过，所有检查项正常"
fi

print_separator

# ======================== 推送企业微信 ========================
WX_MSG="${WX_MSG}---\n"
WX_MSG="${WX_MSG}**巡检结果**: "
if [ "$FAIL_COUNT" -gt 0 ]; then
    WX_MSG="${WX_MSG}<font color=\"warning\">${FAIL_COUNT}个异常，需立即处理</font>"
elif [ "$WARN_COUNT" -gt 0 ]; then
    WX_MSG="${WX_MSG}<font color=\"info\">${WARN_COUNT}个警告，建议关注</font>"
else
    WX_MSG="${WX_MSG}<font color=\"info\">全部正常</font>"
fi
WX_MSG="${WX_MSG}\n"
WX_MSG="${WX_MSG}> 正常: ${OK_COUNT} | 警告: ${WARN_COUNT} | 异常: ${FAIL_COUNT}\n"
WX_MSG="${WX_MSG}> 报告详情: \`${REPORT_FILE}\`"

if [ -n "$WEBHOOK_URL" ]; then
    print_info ""
    print_info "推送企业微信巡检报告..."

    # 构建JSON
    WX_JSON=$(cat <<EOJSON
{"msgtype": "markdown", "markdown": {"content": "${WX_MSG}"}}
EOJSON
    )

    # 发送
    RESPONSE=$(curl -s -X POST "$WEBHOOK_URL" \
        -H 'Content-Type: application/json' \
        -d "$WX_JSON" 2>/dev/null)

    if echo "$RESPONSE" | grep -q '"errcode":0'; then
        print_ok "企业微信巡检报告推送成功"
    else
        print_fail "企业微信推送失败: ${RESPONSE}"
    fi
else
    print_info ""
    print_info "未配置企业微信Webhook，跳过推送"
    print_info "设置环境变量 WECHAT_WEBHOOK_URL 或传入参数即可启用"
    print_info ""
    print_info "报告内容预览:"
    echo "---"
    echo -e "$WX_MSG"
    echo "---"
fi
