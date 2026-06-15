#!/bin/bash
# ============================================================================
# 模块35-告警处理脚本
# 脚本名称: alert-ack.sh
# 功能: 确认告警并通知团队，支持多渠道通知(钉钉/企业微信/邮件)
# 用法: ./alert-ack.sh <alert-id> <alert-level> <alert-message> [notify-channel]
# 示例: ./alert-ack.sh 20260616150000 P0 "MySQL主库宕机" dingtalk
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
ALERT_ID="${1:-$(date '+%Y%m%d%H%M%S')}"
ALERT_LEVEL="${2:-P2}"
ALERT_MESSAGE="${3:-}"
NOTIFY_CHANNEL="${4:-console}"

if [ -z "$ALERT_MESSAGE" ]; then
    print_fail "用法: $0 <alert-id> <alert-level> <alert-message> [notify-channel]"
    print_info "  alert-id:       告警ID (默认: 当前时间戳)"
    print_info "  alert-level:    P0/P1/P2"
    print_info "  alert-message:  告警内容"
    print_info "  notify-channel: dingtalk/wechat/email/console (默认: console)"
    print_info ""
    print_info "示例: $0 20260616150000 P0 \"MySQL主库宕机\" dingtalk"
    exit 1
fi

# 级别校验
ALERT_LEVEL=$(echo "$ALERT_LEVEL" | tr '[:lower:]' '[:upper:]')
if ! [[ "$ALERT_LEVEL" =~ ^P[0-2]$ ]]; then
    print_warn "告警级别无效(${ALERT_LEVEL})，默认使用P2"
    ALERT_LEVEL="P2"
fi

# ======================== 统计变量 ========================
FAIL_COUNT=0
WARN_COUNT=0
OK_COUNT=0

# ======================== 分隔线 ========================
print_separator() {
    echo "============================================================"
}

echo "============================================================"
print_info "告警确认与通知"
print_info "告警ID: ${ALERT_ID}"
print_info "告警级别: ${ALERT_LEVEL}"
print_info "告警内容: ${ALERT_MESSAGE}"
print_info "通知渠道: ${NOTIFY_CHANNEL}"
print_info "操作人: $(whoami)"
print_info "操作时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

# ======================== 1. 告警确认 ========================
print_info ""
print_info ">>> [步骤1] 确认告警信息..."
print_separator

# 判断是否为真告警
print_info "请确认告警是否为真实告警:"
print_info "  1. 检查监控面板数据是否异常"
print_info "  2. 检查是否有近期变更(发布/配置修改)"
print_info "  3. 检查是否为周期性波动(如业务高峰)"
print_info ""
print_info "初步判断:"

# 自动判断告警可信度
if echo "$ALERT_MESSAGE" | grep -qiE "down|宕机|不可用|unreachable"; then
    print_warn "  告警内容涉及服务不可用，可信度高，建议立即确认"
    ((WARN_COUNT++))
elif echo "$ALERT_MESSAGE" | grep -qiE "超过|超过阈值|high|warning"; then
    print_info "  告警内容为阈值告警，需确认是否为误报(如业务高峰)"
    ((OK_COUNT++))
else
    print_info "  一般性告警，请根据实际情况判断"
    ((OK_COUNT++))
fi

# ======================== 2. 影响评估 ========================
print_info ""
print_info ">>> [步骤2] 影响评估..."
print_separator

print_info "评估维度:"
print_info "  - 影响范围: 全站/部分模块/单服务"
print_info "  - 用户影响: 全部用户/部分用户/内部用户"
print_info "  - 业务影响: 核心流程/辅助功能/无直接影响"

case "$ALERT_LEVEL" in
    P0)
        print_fail "  P0告警 - 影响范围广，需立即止血"
        print_info "  建议止血方案:"
        print_info "    1. 服务降级: 关闭非核心功能"
        print_info "    2. 流量切换: 切换到备用服务/机房"
        print_info "    3. 快速回滚: 回滚到上一稳定版本"
        print_info "    4. 紧急扩容: 增加实例应对流量"
        ((FAIL_COUNT++))
        ;;
    P1)
        print_warn "  P1告警 - 存在影响，需尽快处理"
        print_info "  建议处理方案:"
        print_info "    1. 确认根因: 查看日志和监控"
        print_info "    2. 临时缓解: 调整参数/重启服务"
        print_info "    3. 通知相关: 告知业务方影响"
        ((WARN_COUNT++))
        ;;
    P2)
        print_info "  P2告警 - 影响有限，可计划处理"
        print_info "  建议处理方案:"
        print_info "    1. 记录问题: 纳入待处理列表"
        print_info "    2. 排查根因: 空闲时排查"
        print_info "    3. 优化预防: 调整告警阈值"
        ((OK_COUNT++))
        ;;
esac

# ======================== 3. 发送通知 ========================
print_info ""
print_info ">>> [步骤3] 发送通知..."
print_separator

# 构建通知内容
NOTIFY_CONTENT="【告警通知】
告警ID: ${ALERT_ID}
告警级别: ${ALERT_LEVEL}
告警内容: ${ALERT_MESSAGE}
确认人: $(whoami)
确认时间: $(date '+%Y-%m-%d %H:%M:%S')
状态: 已确认，处理中"

case "$NOTIFY_CHANNEL" in
    dingtalk)
        print_info "发送钉钉通知..."
        # 钉钉Webhook地址(需配置)
        DINGTALK_WEBHOOK="${DINGTALK_WEBHOOK_URL:-}"
        if [ -z "$DINGTALK_WEBHOOK" ]; then
            print_warn "钉钉Webhook未配置 (环境变量: DINGTALK_WEBHOOK_URL)"
            print_info "通知内容预览:"
            echo "$NOTIFY_CONTENT"
            ((WARN_COUNT++))
        else
            RESPONSE=$(curl -s -X POST "$DINGTALK_WEBHOOK" \
                -H 'Content-Type: application/json' \
                -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$NOTIFY_CONTENT\"}}" 2>/dev/null)
            if echo "$RESPONSE" | grep -q "ok"; then
                print_ok "钉钉通知发送成功"
                ((OK_COUNT++))
            else
                print_fail "钉钉通知发送失败: ${RESPONSE}"
                ((FAIL_COUNT++))
            fi
        fi
        ;;
    wechat)
        print_info "发送企业微信通知..."
        WECHAT_WEBHOOK="${WECHAT_WEBHOOK_URL:-}"
        if [ -z "$WECHAT_WEBHOOK" ]; then
            print_warn "企业微信Webhook未配置 (环境变量: WECHAT_WEBHOOK_URL)"
            print_info "通知内容预览:"
            echo "$NOTIFY_CONTENT"
            ((WARN_COUNT++))
        else
            RESPONSE=$(curl -s -X POST "$WECHAT_WEBHOOK" \
                -H 'Content-Type: application/json' \
                -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$NOTIFY_CONTENT\"}}" 2>/dev/null)
            if echo "$RESPONSE" | grep -q "ok"; then
                print_ok "企业微信通知发送成功"
                ((OK_COUNT++))
            else
                print_fail "企业微信通知发送失败: ${RESPONSE}"
                ((FAIL_COUNT++))
            fi
        fi
        ;;
    email)
        print_info "发送邮件通知..."
        MAIL_TO="${ALERT_MAIL_TO:-admin@example.com}"
        echo "$NOTIFY_CONTENT" | mail -s "[${ALERT_LEVEL}告警] ${ALERT_MESSAGE}" "$MAIL_TO" 2>/dev/null
        if [ $? -eq 0 ]; then
            print_ok "邮件通知已发送至: ${MAIL_TO}"
            ((OK_COUNT++))
        else
            print_warn "邮件发送失败，请检查mail配置"
            print_info "通知内容预览:"
            echo "$NOTIFY_CONTENT"
            ((WARN_COUNT++))
        fi
        ;;
    console)
        print_info "控制台通知模式:"
        echo "$NOTIFY_CONTENT"
        ((OK_COUNT++))
        ;;
    *)
        print_warn "未知通知渠道: ${NOTIFY_CHANNEL}"
        print_info "通知内容预览:"
        echo "$NOTIFY_CONTENT"
        ((WARN_COUNT++))
        ;;
esac

# ======================== 4. 记录告警确认 ========================
print_info ""
print_info ">>> [步骤4] 记录告警确认..."
print_separator

ALERT_LOG="/tmp/alert-ack-${ALERT_ID}.log"

cat > "$ALERT_LOG" <<EOF
告警ID: ${ALERT_ID}
告警级别: ${ALERT_LEVEL}
告警内容: ${ALERT_MESSAGE}
确认人: $(whoami)
确认时间: $(date '+%Y-%m-%d %H:%M:%S')
通知渠道: ${NOTIFY_CHANNEL}
处理状态: 已确认
通知内容:
${NOTIFY_CONTENT}
EOF

if [ -f "$ALERT_LOG" ]; then
    print_ok "告警确认记录已保存: ${ALERT_LOG}"
    ((OK_COUNT++))
else
    print_warn "告警记录保存失败"
    ((WARN_COUNT++))
fi

# ======================== 5. 下一步操作提示 ========================
print_info ""
print_info ">>> [步骤5] 下一步操作..."
print_separator

print_info "告警已确认，请按以下流程继续处理:"
print_info "  1. 止血操作: 根据告警级别执行对应止血方案"
print_info "  2. 根因排查: 使用对应排查脚本定位问题"
print_info "  3. 修复处理: 实施修复方案"
print_info "  4. 恢复确认: 确认服务恢复正常"
print_info "  5. 事后复盘: P0/P1告警需完成复盘报告"
print_info ""
print_info "相关脚本:"
print_info "  自动止血: ./35-alert/alert-auto-fix.sh"
print_info "  复盘报告: ./35-alert/alert-postmortem.sh"

# ======================== 处理总结 ========================
echo ""
print_separator
echo ""
echo "==================== 告警确认总结 ===================="
echo ""

TOTAL_CHECKS=$((OK_COUNT + WARN_COUNT + FAIL_COUNT))

echo -e "总检查项: ${TOTAL_CHECKS}  |  ${GREEN}正常: ${OK_COUNT}${NC}  |  ${YELLOW}警告: ${WARN_COUNT}${NC}  |  ${RED}异常: ${FAIL_COUNT}${NC}"
echo ""
print_info "告警ID: ${ALERT_ID}"
print_info "告警级别: ${ALERT_LEVEL}"
print_info "通知渠道: ${NOTIFY_CHANNEL}"
print_info "告警记录: ${ALERT_LOG}"

if [ "$FAIL_COUNT" -gt 0 ]; then
    print_fail "结论: 告警已确认，但通知发送存在异常"
elif [ "$WARN_COUNT" -gt 0 ]; then
    print_warn "结论: 告警已确认，部分功能需配置后使用"
else
    print_ok "结论: 告警已确认并通知，请继续处理"
fi

echo ""
print_separator
