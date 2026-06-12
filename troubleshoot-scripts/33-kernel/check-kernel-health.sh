#!/bin/bash
# ============================================================================
# 模块33-计算机基础与内核脚本
# 脚本名称: check-kernel-health.sh
# 功能: 内核健康状态检查
# 用法: ./check-kernel-health.sh
# 说明: 综合检查内核版本、panic/oops记录、硬件错误、内核模块和参数
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
echo "          内核健康状态检查报告"
echo "          检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ======================== 1. 内核版本检查 ========================
print_info ">>> [1/6] 检查内核版本 ..."

KERNEL_VERSION=$(uname -r)
KERNEL_NAME=$(uname -s)
KERNEL_ARCH=$(uname -m)
KERNEL_RELEASE=$(uname -v)

echo "    内核名称: ${KERNEL_NAME}"
echo "    内核版本: ${KERNEL_VERSION}"
echo "    内核架构: ${KERNEL_ARCH}"
echo "    内核发行: ${KERNEL_RELEASE}"

# 检查内核版本是否过旧（以5.4为基准，这是很多发行版的LTS版本）
KERNEL_MAJOR=$(echo "$KERNEL_VERSION" | cut -d. -f1)
KERNEL_MINOR=$(echo "$KERNEL_VERSION" | cut -d. -f2)

if [ "$KERNEL_MAJOR" -lt 4 ]; then
    print_fail "内核版本过旧(${KERNEL_VERSION})，建议升级到5.x或6.x LTS版本"
elif [ "$KERNEL_MAJOR" -eq 4 ] && [ "$KERNEL_MINOR" -lt 14 ]; then
    print_warn "内核版本较旧(${KERNEL_VERSION})，建议升级到4.19+或5.x LTS"
else
    print_ok "内核版本合理(${KERNEL_VERSION})"
fi

# 检查内核是否为RT（实时）版本
if echo "$KERNEL_VERSION" | grep -qi "rt"; then
    print_info "检测到实时(RT)内核"
fi

echo ""

# ======================== 2. 内核Panic检查 ========================
print_info ">>> [2/6] 检查内核Panic记录 ..."

PANIC_LOGS=$(dmesg 2>/dev/null | grep -i "panic" | tail -10)
PANIC_COUNT=$(dmesg 2>/dev/null | grep -ci "panic")

echo "    Panic记录数量: ${PANIC_COUNT}"

if [ "$PANIC_COUNT" -gt 0 ]; then
    print_fail "检测到 ${PANIC_COUNT} 条内核Panic记录!"
    echo ""
    echo "    Panic详情:"
    echo "$PANIC_LOGS" | while read line; do
        echo "    $line"
    done
    print_info "建议: 分析Panic调用栈，检查硬件兼容性和驱动版本"
else
    print_ok "未检测到内核Panic记录"
fi

# 检查上次panic时间戳
if [ -f /proc/sys/kernel/panic_on_oops ]; then
    PANIC_ON_OOPS=$(cat /proc/sys/kernel/panic_on_oops 2>/dev/null)
    echo "    kernel.panic_on_oops = ${PANIC_ON_OOPS}"
    if [ "$PANIC_ON_OOPS" -eq 1 ]; then
        print_info "Oops时将触发Panic重启"
    fi
fi

echo ""

# ======================== 3. 内核Oops检查 ========================
print_info ">>> [3/6] 检查内核Oops记录 ..."

OOPS_LOGS=$(dmesg 2>/dev/null | grep -i "oops" | tail -10)
OOPS_COUNT=$(dmesg 2>/dev/null | grep -ci "oops")

echo "    Oops记录数量: ${OOPS_COUNT}"

if [ "$OOPS_COUNT" -gt 0 ]; then
    print_fail "检测到 ${OOPS_COUNT} 条内核Oops记录!"
    echo ""
    echo "    Oops详情:"
    echo "$OOPS_LOGS" | while read line; do
        echo "    $line"
    done
    print_info "建议: 收集Oops调用栈并提交Bug报告，考虑升级内核"
else
    print_ok "未检测到内核Oops记录"
fi

# 检查内核警告
WARN_LOGS=$(dmesg 2>/dev/null | grep -i "WARNING:" | tail -5)
WARN_COUNT=$(dmesg 2>/dev/null | grep -ci "WARNING:")
if [ "$WARN_COUNT" -gt 0 ]; then
    print_warn "检测到 ${WARN_COUNT} 条内核WARNING"
    echo "$WARN_LOGS" | while read line; do
        echo "    $line"
    done
fi

echo ""

# ======================== 4. 硬件错误检查 ========================
print_info ">>> [4/6] 检查硬件错误 ..."

# Machine Check Exception
MCE_LOGS=$(dmesg 2>/dev/null | grep -i "machine check" | tail -5)
if [ -n "$MCE_LOGS" ]; then
    print_fail "检测到Machine Check Exception!"
    echo "$MCE_LOGS" | while read line; do
        echo "    $line"
    done
    print_info "建议: 运行mcelog --client检查MCE详情，排查内存/CPU硬件问题"
else
    print_ok "未检测到Machine Check Exception"
fi

# MCE日志文件检查
if [ -f /var/log/mcelog ]; then
    MCE_FILE_ERRORS=$(grep -c "hardware error" /var/log/mcelog 2>/dev/null)
    if [ "$MCE_FILE_ERRORS" -gt 0 ]; then
        print_warn "mcelog中记录了${MCE_FILE_ERRORS}个硬件错误"
    fi
fi

# PCIe AER错误
AER_LOGS=$(dmesg 2>/dev/null | grep -iE "aer|pcie.*error" | tail -5)
if [ -n "$AER_LOGS" ]; then
    print_warn "检测到PCIe AER错误:"
    echo "$AER_LOGS" | while read line; do
        echo "    $line"
    done
fi

# USB错误
USB_ERRORS=$(dmesg 2>/dev/null | grep -i "usb.*error\|device descriptor read" | tail -3)
if [ -n "$USB_ERRORS" ]; then
    print_warn "检测到USB相关错误:"
    echo "$USB_ERRORS" | while read line; do
        echo "    $line"
    done
fi

# 内存ECC错误
ECC_ERRORS=$(dmesg 2>/dev/null | grep -iE "ecc|corrected memory" | tail -3)
if [ -n "$ECC_ERRORS" ]; then
    print_warn "检测到内存ECC错误:"
    echo "$ECC_ERRORS" | while read line; do
        echo "    $line"
    done
fi

echo ""

# ======================== 5. 内核模块检查 ========================
print_info ">>> [5/6] 检查内核模块 ..."

MODULE_COUNT=$(lsmod 2>/dev/null | wc -l)
echo "    已加载内核模块数量: ${MODULE_COUNT}"

if [ "$MODULE_COUNT" -gt 0 ]; then
    print_ok "已加载${MODULE_COUNT}个内核模块"

    # 检查是否有模块加载失败
    MODPROBE_ERRORS=$(dmesg 2>/dev/null | grep -i "module.*error\|disagrees\|unknown symbol" | tail -5)
    if [ -n "$MODPROBE_ERRORS" ]; then
        print_warn "检测到内核模块加载错误:"
        echo "$MODPROBE_ERRORS" | while read line; do
            echo "    $line"
        done
    fi

    # 显示关键模块
    echo ""
    echo "    关键内核模块状态:"
    for mod in ext4 xfs nfs bonding bridge ip_tables netfilter; do
        if lsmod 2>/dev/null | grep -q "^${mod}"; then
            SIZE=$(lsmod 2>/dev/null | grep "^${mod}" | awk '{print $2}')
            echo "    ${GREEN}[已加载]${NC} ${mod} (大小: ${SIZE})"
        fi
    done
fi

echo ""

# ======================== 6. 内核参数检查 ========================
print_info ">>> [6/6] 检查关键内核参数 ..."

echo "    ============================================================"
echo "    关键内核参数:"
echo "    ============================================================"

# 系统控制参数
PARAMS=(
    "kernel.panic:kernel/panic:Panic后重启等待秒数"
    "kernel.pid_max:kernel/pid_max:最大PID值"
    "kernel.threads-max:kernel/threads-max:最大线程数"
    "vm.overcommit_memory:vm/overcommit_memory:内存过度提交策略"
    "vm.swappiness:vm/swappiness:Swap使用倾向"
    "vm.dirty_ratio:vm/dirty_ratio:脏页同步写入阈值"
    "vm.dirty_background_ratio:vm/dirty_background_ratio:脏页后台回写阈值"
    "net.core.somaxconn:net/core/somaxconn:监听队列最大长度"
    "net.ipv4.tcp_max_syn_backlog:net/ipv4/tcp_max_syn_backlog:SYN队列长度"
    "net.ipv4.tcp_tw_reuse:net/ipv4/tcp_tw_reuse:TIME_WAIT复用"
    "fs.file-max:fs/file-max:最大文件句柄数"
    "fs.nr_open:fs/nr_open:单进程最大文件句柄数"
)

for param_entry in "${PARAMS[@]}"; do
    PARAM_NAME=$(echo "$param_entry" | cut -d: -f1)
    PROC_PATH=$(echo "$param_entry" | cut -d: -f2)
    DESC=$(echo "$param_entry" | cut -d: -f3)

    VALUE=$(cat "/proc/sys/${PROC_PATH}" 2>/dev/null)
    if [ -n "$VALUE" ]; then
        printf "    %-35s = %-10s # %s\n" "$PARAM_NAME" "$VALUE" "$DESC"
    fi
done

echo "    ============================================================"

# 内核命令行参数
echo ""
echo "    内核启动参数:"
KERNEL_CMDLINE=$(cat /proc/cmdline 2>/dev/null)
echo "    $KERNEL_CMDLINE"

echo ""
echo "============================================================"
echo "                     内核健康报告"
echo "============================================================"

HEALTH_SCORE=100

# 根据检查结果计算健康分数
if [ "$PANIC_COUNT" -gt 0 ]; then
    HEALTH_SCORE=$((HEALTH_SCORE - 30))
    echo -e "  ${RED}[严重]${NC} 存在内核Panic记录 (-30分)"
fi

if [ "$OOPS_COUNT" -gt 0 ]; then
    HEALTH_SCORE=$((HEALTH_SCORE - 20))
    echo -e "  ${RED}[严重]${NC} 存在内核Oops记录 (-20分)"
fi

if [ -n "$MCE_LOGS" ]; then
    HEALTH_SCORE=$((HEALTH_SCORE - 25))
    echo -e "  ${RED}[严重]${NC} 存在硬件Machine Check错误 (-25分)"
fi

if [ "$KERNEL_MAJOR" -lt 4 ]; then
    HEALTH_SCORE=$((HEALTH_SCORE - 10))
    echo -e "  ${YELLOW}[警告]${NC} 内核版本过旧 (-10分)"
fi

if [ "$WARN_COUNT" -gt 0 ]; then
    HEALTH_SCORE=$((HEALTH_SCORE - 5))
    echo -e "  ${YELLOW}[警告]${NC} 存在内核WARNING (-5分)"
fi

if [ "$HEALTH_SCORE" -ge 90 ]; then
    HEALTH_STATUS="${GREEN}健康${NC}"
elif [ "$HEALTH_SCORE" -ge 70 ]; then
    HEALTH_STATUS="${YELLOW}亚健康${NC}"
else
    HEALTH_STATUS="${RED}不健康${NC}"
fi

echo ""
echo -e "  内核健康评分: ${HEALTH_SCORE}/100 ($HEALTH_STATUS)"

if [ "$HEALTH_SCORE" -lt 70 ]; then
    echo ""
    echo "  建议立即采取以下措施:"
    echo "  1. 收集完整的dmesg日志和/var/log/messages"
    echo "  2. 分析Panic/Oops调用栈定位根因"
    echo "  3. 检查硬件诊断(memtest86+, smartctl)"
    echo "  4. 考虑升级内核到最新稳定版本"
fi

echo "============================================================"
