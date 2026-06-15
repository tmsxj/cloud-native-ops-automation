#!/bin/bash
# ============================================================================
# 模块35-告警处理脚本
# 脚本名称: alert-postmortem.sh
# 功能: 生成告警复盘报告模板，自动收集故障时间线与影响数据
# 用法: ./alert-postmortem.sh <alert-id> <alert-level> <alert-message> [output-dir]
# 示例: ./alert-postmortem.sh 20260616150000 P0 "MySQL主库宕机" /tmp/reports
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
ALERT_LEVEL="${2:-P1}"
ALERT_MESSAGE="${3:-}"
OUTPUT_DIR="${4:-/tmp/postmortem}"

if [ -z "$ALERT_MESSAGE" ]; then
    print_fail "用法: $0 <alert-id> <alert-level> <alert-message> [output-dir]"
    print_info "示例: $0 20260616150000 P0 \"MySQL主库宕机\" /tmp/reports"
    exit 1
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
print_info "告警复盘报告生成"
print_info "告警ID: ${ALERT_ID}"
print_info "告警级别: ${ALERT_LEVEL}"
print_info "告警内容: ${ALERT_MESSAGE}"
print_info "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

# ======================== 1. 创建报告目录 ========================
print_info ""
print_info ">>> [步骤1] 创建报告目录..."
print_separator

REPORT_DIR="${OUTPUT_DIR}/postmortem-${ALERT_ID}"
mkdir -p "$REPORT_DIR"

if [ -d "$REPORT_DIR" ]; then
    print_ok "报告目录已创建: ${REPORT_DIR}"
    ((OK_COUNT++))
else
    print_fail "报告目录创建失败: ${REPORT_DIR}"
    exit 1
fi

REPORT_FILE="${REPORT_DIR}/postmortem-${ALERT_ID}.md"

# ======================== 2. 收集系统快照 ========================
print_info ""
print_info ">>> [步骤2] 收集系统快照..."
print_separator

# 系统基本信息
SNAPSHOT_FILE="${REPORT_DIR}/system-snapshot.txt"
{
    echo "=== 系统快照 - $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo ""
    echo "--- 主机信息 ---"
    hostname 2>/dev/null
    uname -a 2>/dev/null
    echo ""
    echo "--- CPU信息 ---"
    nproc 2>/dev/null
    top -bn1 | head -5 2>/dev/null
    echo ""
    echo "--- 内存信息 ---"
    free -h 2>/dev/null
    echo ""
    echo "--- 磁盘信息 ---"
    df -h 2>/dev/null
    echo ""
    echo "--- 负载信息 ---"
    uptime 2>/dev/null
    echo ""
    echo "--- TOP 10 进程(CPU) ---"
    ps aux --sort=-%cpu | head -11 2>/dev/null
    echo ""
    echo "--- TOP 10 进程(内存) ---"
    ps aux --sort=-%mem | head -11 2>/dev/null
} > "$SNAPSHOT_FILE" 2>/dev/null

if [ -f "$SNAPSHOT_FILE" ]; then
    print_ok "系统快照已保存: ${SNAPSHOT_FILE}"
    ((OK_COUNT++))
else
    print_warn "系统快照收集失败"
    ((WARN_COUNT++))
fi

# ======================== 3. 收集K8S集群状态 ========================
print_info ""
print_info ">>> [步骤3] 收集K8S集群状态..."
print_separator

K8S_FILE="${REPORT_DIR}/k8s-snapshot.txt"

if command -v kubectl &>/dev/null; then
    {
        echo "=== K8S集群快照 - $(date '+%Y-%m-%d %H:%M:%S') ==="
        echo ""
        echo "--- 节点状态 ---"
        kubectl get nodes -o wide 2>/dev/null
        echo ""
        echo "--- 异常Pod ---"
        kubectl get pods -A --no-headers 2>/dev/null | grep -E "CrashLoop|Error|OOMKilled|Pending|ImagePull" || echo "无异常Pod"
        echo ""
        echo "--- 最近事件 ---"
        kubectl get events -A --sort-by=.lastTimestamp 2>/dev/null | tail -20
        echo ""
        echo "--- 资源使用TOP5 ---"
        kubectl top nodes 2>/dev/null || echo "metrics-server不可用"
        echo ""
        kubectl top pods -A --sort-by=cpu 2>/dev/null | head -6 || echo "metrics-server不可用"
    } > "$K8S_FILE" 2>/dev/null

    if [ -f "$K8S_FILE" ]; then
        print_ok "K8S快照已保存: ${K8S_FILE}"
        ((OK_COUNT++))
    fi
else
    print_info "kubectl不可用，跳过K8S快照收集"
    echo "kubectl不可用，未收集K8S快照" > "$K8S_FILE"
    ((WARN_COUNT++))
fi

# ======================== 4. 生成复盘报告 ========================
print_info ""
print_info ">>> [步骤4] 生成复盘报告模板..."
print_separator

# 计算故障持续时间占位
MTTD_PLACEHOLDER="待填写(从告警触发到确认的时间)"
MTTR_PLACEHOLDER="待填写(从确认到恢复的时间)"

cat > "$REPORT_FILE" <<EOF
# 故障复盘报告

## 基本信息

| 项目 | 内容 |
|------|------|
| 告警ID | ${ALERT_ID} |
| 告警级别 | ${ALERT_LEVEL} |
| 告警内容 | ${ALERT_MESSAGE} |
| 发现时间 | 待填写 |
| 确认时间 | 待填写 |
| 恢复时间 | 待填写 |
| 处理人 | $(whoami) |
| 报告生成时间 | $(date '+%Y-%m-%d %H:%M:%S') |

---

## 故障时间线

| 时间 | 事件 | 操作人 |
|------|------|--------|
| HH:MM | 告警触发 | 监控系统 |
| HH:MM | 告警确认 | 待填写 |
| HH:MM | 止血操作 | 待填写 |
| HH:MM | 根因定位 | 待填写 |
| HH:MM | 修复实施 | 待填写 |
| HH:MM | 恢复确认 | 待填写 |

---

## 影响范围

- **影响服务**: 待填写
- **影响用户**: 待填写(全部/部分/内部)
- **影响时长**: 待填写
- **业务损失**: 待填写(如有)

---

## 根因分析

### 直接原因
待填写(如: MySQL连接数耗尽导致新请求无法建立连接)

### 根本原因
待填写(如: 慢查询未优化导致连接池被占满，缺少连接数监控告警)

### 5-Whys分析
1. Why? 待填写
2. Why? 待填写
3. Why? 待填写
4. Why? 待填写
5. Why? 待填写

---

## 处理过程

### 止血措施
待填写(如: 重启Pod / 扩容 / 回滚 / 限流)

### 修复措施
待填写(如: 优化SQL / 调整参数 / 修复代码)

---

## 改进措施

| 改进项 | 类型 | 负责人 | 截止时间 | 状态 |
|--------|------|--------|---------|------|
| 待填写 | 预防 | 待填写 | 待填写 | 待处理 |
| 待填写 | 监控 | 待填写 | 待填写 | 待处理 |
| 待填写 | 流程 | 待填写 | 待填写 | 待处理 |

---

## 经验教训

1. 待填写(如: 应该提前设置连接数告警阈值)
2. 待填写(如: 需要完善故障应急预案)

---

## 附件

- 系统快照: \`system-snapshot.txt\`
- K8S快照: \`k8s-snapshot.txt\`
- 告警截图: 待补充

---

## 指标统计

| 指标 | 数值 |
|------|------|
| MTTD (发现到确认) | ${MTTD_PLACEHOLDER} |
| MTTR (确认到恢复) | ${MTTR_PLACEHOLDER} |
| 影响用户数 | 待填写 |
| 影响时长 | 待填写 |

---

*报告生成工具: alert-postmortem.sh*
EOF

if [ -f "$REPORT_FILE" ]; then
    print_ok "复盘报告已生成: ${REPORT_FILE}"
    ((OK_COUNT++))
else
    print_fail "复盘报告生成失败"
    ((FAIL_COUNT++))
fi

# ======================== 5. 生成待办清单 ========================
print_info ""
print_info ">>> [步骤5] 生成待办清单..."
print_separator

TODO_FILE="${REPORT_DIR}/todo-list.txt"

cat > "$TODO_FILE" <<EOF
=== 复盘待办清单 - ${ALERT_ID} ===
生成时间: $(date '+%Y-%m-%d %H:%M:%S')

[ ] 1. 补充故障时间线(具体时间和操作人)
[ ] 2. 填写影响范围和业务损失
[ ] 3. 完成根因分析(5-Whys)
[ ] 4. 整理止血和修复措施
[ ] 5. 制定改进措施并分配负责人
[ ] 6. 补充告警截图和日志截图
[ ] 7. 团队内部分享复盘结论
EOF

if [ -f "$TODO_FILE" ]; then
    print_ok "待办清单已生成: ${TODO_FILE}"
    ((OK_COUNT++))
else
    print_warn "待办清单生成失败"
    ((WARN_COUNT++))
fi

# ======================== 生成总结 ========================
echo ""
print_separator
echo ""
echo "==================== 复盘报告生成总结 ===================="
echo ""

TOTAL_CHECKS=$((OK_COUNT + WARN_COUNT + FAIL_COUNT))

echo -e "总检查项: ${TOTAL_CHECKS}  |  ${GREEN}正常: ${OK_COUNT}${NC}  |  ${YELLOW}警告: ${WARN_COUNT}${NC}  |  ${RED}异常: ${FAIL_COUNT}${NC}"
echo ""
print_info "报告目录: ${REPORT_DIR}"
print_info "复盘报告: ${REPORT_FILE}"
print_info "系统快照: ${SNAPSHOT_FILE}"
print_info "K8S快照: ${K8S_FILE}"
print_info "待办清单: ${TODO_FILE}"

if [ "$FAIL_COUNT" -gt 0 ]; then
    print_fail "结论: 报告生成存在异常，请检查"
elif [ "$WARN_COUNT" -gt 0 ]; then
    print_warn "结论: 报告已生成，部分数据收集失败"
else
    print_ok "结论: 复盘报告已生成，请补充待填写内容"
fi

echo ""
print_info "下一步: 编辑 ${REPORT_FILE} 补充故障详情和分析"
print_separator
