#!/bin/bash
# ============================================================================
# 模块31-Linux系统故障排查脚本
# 脚本名称: check-boot.sh
# 功能: 系统启动与内核诊断
# 用法: ./check-boot.sh
# 说明: 检查系统启动时间、内核panic、硬件错误和内核参数
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

echo "============================================================"
echo "          系统启动与内核诊断报告"
echo "          检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ======================== 1. 系统启动时间检查 ========================
print_info ">>> [1/5] 检查系统启动时间 ..."

# 检查系统运行时间
UPTIME_INFO=$(uptime)
UPTIME_DAYS=$(uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}' | grep -oE '[0-9]+')
UPTIME_DAYS=${UPTIME_DAYS:-0}

echo "    系统运行时间: $(uptime -p 2>/dev/null || echo "$UPTIME_INFO")"

# 检查上次重启时间
LAST_REBOOT=$(last reboot -1 2>/dev/null | head -1)
if [ -n "$LAST_REBOOT" ]; then
    echo "    上次重启: $LAST_REBOOT"
fi

# 检查systemd-analyze（如果可用）
if command -v systemd-analyze &>/dev/null; then
    echo ""
    BOOT_TIME=$(systemd-analyze 2>/dev/null)
    echo "    启动总耗时: $(echo "$BOOT_TIME" | head -1)"

    # 检查启动最慢的服务
    SLOW_SERVICES=$(systemd-analyze blame 2>/dev/null | head -5)
    if [ -n "$SLOW_SERVICES" ]; then
        echo ""
        echo "    启动最慢的5个服务:"
        echo "$SLOW_SERVICES" | while read line; do
            echo "    $line"
        done
    fi

    # 检查关键服务启动时间
    CRITICAL_TIME=$(systemd-analyze critical-chain 2>/dev/null | head -10)
    if [ -n "$CRITICAL_TIME" ]; then
        echo ""
        echo "    关键启动链:"
        echo "$CRITICAL_TIME" | while read line; do
            echo "    $line"
        done
    fi

    print_ok "systemd启动分析完成"
else
    print_info "systemd-analyze不可用，跳过详细启动分析"
fi

echo ""

# ======================== 2. 内核Panic检查 ========================
print_info ">>> [2/5] 检查内核Panic记录 ..."

PANIC_LOGS=$(dmesg 2>/dev/null | grep -i "panic" | tail -10)

if [ -z "$PANIC_LOGS" ]; then
    print_ok "未检测到内核Panic记录"
else
    PANIC_COUNT=$(dmesg 2>/dev/null | grep -ci "panic")
    print_fail "检测到 ${PANIC_COUNT} 条内核Panic记录!"
    echo ""
    echo "    Panic记录:"
    echo "$PANIC_LOGS" | while read line; do
        echo "    $line"
    done
    print_info "建议: 检查硬件兼容性、驱动版本和内核日志"
fi

echo ""

# ======================== 3. 内核Oops检查 ========================
print_info ">>> [3/5] 检查内核Oops记录 ..."

OOPS_LOGS=$(dmesg 2>/dev/null | grep -i "oops" | tail -10)

if [ -z "$OOPS_LOGS" ]; then
    print_ok "未检测到内核Oops记录"
else
    OOPS_COUNT=$(dmesg 2>/dev/null | grep -ci "oops")
    print_fail "检测到 ${OOPS_COUNT} 条内核Oops记录!"
    echo ""
    echo "    Oops记录:"
    echo "$OOPS_LOGS" | while read line; do
        echo "    $line"
    done
    print_info "建议: Oops通常由内核Bug或硬件故障引起，建议升级内核"
fi

echo ""

# ======================== 4. 硬件错误检查 ========================
print_info ">>> [4/5] 检查硬件错误 ..."

# 检查Machine Check Exception
MCE_LOGS=$(dmesg 2>/dev/null | grep -i "machine check" | tail -5)

if [ -n "$MCE_LOGS" ]; then
    print_fail "检测到硬件Machine Check错误!"
    echo ""
    echo "    错误记录:"
    echo "$MCE_LOGS" | while read line; do
        echo "    $line"
    done
    print_info "建议: 检查内存ECC、CPU温度和电源稳定性"
else
    print_ok "未检测到Machine Check错误"
fi

# 检查其他硬件相关错误
HW_ERRORS=$(dmesg 2>/dev/null | grep -iE "hardware error|mce|ecc|parity|NMI" | tail -5)
if [ -n "$HW_ERRORS" ]; then
    print_warn "检测到其他硬件相关警告:"
    echo "$HW_ERRORS" | while read line; do
        echo "    $line"
    done
fi

# 检查PCIe错误
PCIE_ERRORS=$(dmesg 2>/dev/null | grep -iE "pcie.*error|aer" | tail -5)
if [ -n "$PCIE_ERRORS" ]; then
    print_warn "检测到PCIe错误:"
    echo "$PCIE_ERRORS" | while read line; do
        echo "    $line"
    done
fi

echo ""

# ======================== 5. 内核参数检查 ========================
print_info ">>> [5/5] 检查内核启动参数 ..."

KERNEL_CMDLINE=$(cat /proc/cmdline 2>/dev/null)
echo "    内核命令行参数:"
echo "    $KERNEL_CMDLINE"

echo ""
echo "    关键内核参数检查:"

# 检查panic参数
PANIC_PARAM=$(cat /proc/sys/kernel/panic 2>/dev/null)
echo "    kernel.panic = ${PANIC_PARAM}"
if [ "$PANIC_PARAM" -eq 0 ]; then
    print_warn "kernel.panic=0，内核panic后不会自动重启"
    print_info "建议: 设置kernel.panic=5或更高，使系统在panic后自动重启"
else
    print_ok "kernel.panic=${PANIC_PARAM}，内核panic后将在${PANIC_PARAM}秒后重启"
fi

# 检查内核版本
KERNEL_VERSION=$(uname -r)
echo "    内核版本: ${KERNEL_VERSION}"

# 检查是否为最新安全版本
print_info "建议定期检查内核安全更新: yum update kernel 或 apt upgrade"

echo ""
echo "============================================================"
echo "                     诊断结论"
echo "============================================================"

ISSUE_COUNT=0

if [ -n "$PANIC_LOGS" ]; then
    echo -e "  ${RED}[严重]${NC} 存在内核Panic记录，系统稳定性受到威胁"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ -n "$OOPS_LOGS" ]; then
    echo -e "  ${RED}[严重]${NC} 存在内核Oops记录，可能由内核Bug或硬件故障引起"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ -n "$MCE_LOGS" ]; then
    echo -e "  ${RED}[严重]${NC} 检测到硬件Machine Check错误"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$PANIC_PARAM" -eq 0 ]; then
    echo -e "  ${YELLOW}[警告]${NC} kernel.panic=0，建议设置为自动重启"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
fi

if [ "$ISSUE_COUNT" -eq 0 ]; then
    echo -e "  ${GREEN}[正常]${NC} 系统启动与内核状态健康"
fi

echo "============================================================"
