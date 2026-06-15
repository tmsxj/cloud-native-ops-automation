#!/bin/bash
# ============================================================================
# 模块35-告警处理脚本
# 脚本名称: alert-wechat-notify.sh
# 功能: 企业微信机器人告警推送，支持Markdown格式，可被其他脚本调用
# 用法: ./alert-wechat-notify.sh <webhook-url> <title> <content> [level] [mentioned]
# 示例: ./alert-wechat-notify.sh "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx" \
#        "MySQL连接数告警" "当前连接数: 350/400 (87%)" warning "@all"
#
# 环境变量: WECHAT_WEBHOOK_URL  (设置后可省略第一个参数)
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
TITLE="${2:-告警通知}"
CONTENT="${3:-无内容}"
LEVEL="${4:-info}"        # info / warning / critical
MENTIONED="${5:-}"         # @all 或 @具体人

if [ -z "$WEBHOOK_URL" ]; then
    print_fail "用法: $0 <webhook-url> <title> <content> [level] [mentioned]"
    print_info "环境变量: WECHAT_WEBHOOK_URL (设置后可省略第一个参数)"
    print_info ""
    print_info "示例:"
    print_info "  $0 'https://qyapi.weixin.qq.com/...' 'MySQL告警' '连接数87%' warning '@all'"
    print_info "  WECHAT_WEBHOOK_URL='https://...' $0 'MySQL告警' '连接数87%' warning"
    exit 1
fi

# ======================== 告警级别配色 ========================
case "$LEVEL" in
    critical)
        COLOR_TAG="<font color=\"warning\">紧急</font>"
        LEVEL_TEXT="P0-紧急"
        ;;
    warning)
        COLOR_TAG="<font color=\"info\">警告</font>"
        LEVEL_TEXT="P1-警告"
        ;;
    info)
        COLOR_TAG="<font color=\"comment\">信息</font>"
        LEVEL_TEXT="P2-信息"
        ;;
    *)
        COLOR_TAG="信息"
        LEVEL_TEXT="P2-信息"
        ;;
esac

# ======================== 构建企业微信Markdown消息 ========================
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
HOSTNAME=$(hostname)

# mentioned_user字段
if [ -n "$MENTIONED" ]; then
    MENTIONED_JSON=", \"mentioned_list\": [\"${MENTIONED}\"]"
else
    MENTIONED_JSON=", \"mentioned_list\": []"
fi

# 构建JSON payload
read -r -d '' JSON_PAYLOAD <<EOF
{
    "msgtype": "markdown",
    "markdown": {
        "content": "## ${COLOR_TAG} ${TITLE}\n\n> **级别**: ${LEVEL_TEXT}\n> **时间**: ${TIMESTAMP}\n> **主机**: ${HOSTNAME}\n\n${CONTENT}\n\n---\n> 由运维告警系统自动发送"
    }
    ${MENTIONED_JSON}
}
EOF

# ======================== 发送告警 ========================
print_info "发送企业微信告警..."
print_info "  标题: ${TITLE}"
print_info "  级别: ${LEVEL_TEXT}"
print_info "  内容: ${CONTENT}"

RESPONSE=$(curl -s -X POST "$WEBHOOK_URL" \
    -H 'Content-Type: application/json' \
    -d "$JSON_PAYLOAD" 2>/dev/null)

# 解析响应
if echo "$RESPONSE" | grep -q '"errcode":0'; then
    print_ok "企业微信告警发送成功"
    exit 0
else
    print_fail "企业微信告警发送失败"
    print_info "响应: ${RESPONSE}"
    exit 1
fi
