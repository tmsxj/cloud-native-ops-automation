#!/bin/bash

###############################################################################
# 脚本名称：health-check.sh
# 功能说明：Linux 系统健康检查脚本
# 适用场景：定期检查系统状态、快速定位问题
# 使用方法：sudo ./health-check.sh
# 输出说明：显示系统各项指标，异常项用红色标注
###############################################################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo -e "  Linux 系统健康检查"
echo -e "==========================================${NC}"
echo ""

#-------------------------------------------------------------------------------
# 1. 系统基本信息
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[1] 系统基本信息 ${NC}"
echo "----------------------------------------------"
echo "主机名: $(hostname)"
echo "操作系统: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "内核版本: $(uname -r)"
echo "架构: $(uname -m)"
echo "运行时间: $(uptime | awk '{print $3,$4}' | cut -d',' -f1)"
echo ""

#-------------------------------------------------------------------------------
# 2. CPU 状态
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[2] CPU 状态 ${NC}"
echo "----------------------------------------------"
CPU_COUNT=$(nproc)
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

echo "CPU 核心数: $CPU_COUNT"
echo "CPU 使用率: ${CPU_USAGE}%"

if (( $(echo "$CPU_USAGE > 90" | bc -l) )); then
    echo -e "${RED}⚠ CPU 使用率过高！${NC}"
elif (( $(echo "$CPU_USAGE > 70" | bc -l) )); then
    echo -e "${YELLOW}⚠ CPU 使用率偏高${NC}"
else
    echo -e "${GREEN}✓ CPU 状态正常${NC}"
fi
echo ""

#-------------------------------------------------------------------------------
# 3. 内存状态
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[3] 内存状态 ${NC}"
echo "----------------------------------------------"
MEM_TOTAL=$(free -h | grep Mem | awk '{print $2}')
MEM_USED=$(free -h | grep Mem | awk '{print $3}')
MEM_FREE=$(free -h | grep Mem | awk '{print $4}')
MEM_USED_PCT=$(free | grep Mem | awk '{print $3/$2*100}')

echo "总内存: $MEM_TOTAL"
echo "已使用: $MEM_USED"
echo "空闲: $MEM_FREE"
echo "使用率: ${MEM_USED_PCT}%"

if (( $(echo "$MEM_USED_PCT > 90" | bc -l) )); then
    echo -e "${RED}⚠ 内存使用率过高！${NC}"
elif (( $(echo "$MEM_USED_PCT > 80" | bc -l) )); then
    echo -e "${YELLOW}⚠ 内存使用率偏高${NC}"
else
    echo -e "${GREEN}✓ 内存状态正常${NC}"
fi
echo ""

#-------------------------------------------------------------------------------
# 4. 磁盘状态
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[4] 磁盘状态 ${NC}"
echo "----------------------------------------------"
echo "分区使用情况:"
echo ""

df -h | grep -v "tmpfs\|devtmpfs\|loop" | tail -n +2 | while read line; do
    mount=$(echo "$line" | awk '{print $6}')
    size=$(echo "$line" | awk '{print $2}')
    used=$(echo "$line" | awk '{print $3}')
    avail=$(echo "$line" | awk '{print $4}')
    pct=$(echo "$line" | awk '{print $5}')
    
    echo "$mount ($size): 已用 $used, 可用 $avail ($pct)"
    
    pct_num=$(echo "$pct" | tr -d '%')
    if [ "$pct_num" -gt 90 ]; then
        echo -e "  ${RED}⚠ 磁盘空间不足！${NC}"
    elif [ "$pct_num" -gt 80 ]; then
        echo -e "  ${YELLOW}⚠ 磁盘空间偏高${NC}"
    else
        echo -e "  ${GREEN}✓ 正常${NC}"
    fi
    echo ""
done

#-------------------------------------------------------------------------------
# 5. 网络状态
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[5] 网络状态 ${NC}"
echo "----------------------------------------------"
echo "IP 地址:"
ip addr show | grep -E "inet.*brd" | awk '{print "  " $2 " (" $NF ")"}'

echo ""
echo "网关: $(ip route | grep default | awk '{print $3}')"

echo ""
echo "DNS 配置:"
cat /etc/resolv.conf 2>/dev/null | grep nameserver | awk '{print "  " $2}'
echo ""

#-------------------------------------------------------------------------------
# 6. 服务状态
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[6] 关键服务状态 ${NC}"
echo "----------------------------------------------"

SERVICES=("sshd" "systemd-journald" "chronyd" "crond" "rsyslog")

for service in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$service"; then
        echo -e "  ${GREEN}✓ $service${NC}"
    else
        echo -e "  ${RED}✗ $service${NC}"
    fi
done
echo ""

#-------------------------------------------------------------------------------
# 7. 安全状态
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[7] 安全状态 ${NC}"
echo "----------------------------------------------"

echo "SSH 密码登录: $(grep -E "^PasswordAuthentication" /etc/ssh/sshd_config | awk '{print $2}')"

echo ""
echo "最近登录用户:"
last -n 5 | head -5
echo ""

#-------------------------------------------------------------------------------
# 8. 进程状态
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[8] 进程状态 ${NC}"
echo "----------------------------------------------"

echo "总进程数: $(ps aux | wc -l)"
echo "僵尸进程: $(ps aux | grep -E '^Z|defunct' | wc -l)"

ZOMBIE_COUNT=$(ps aux | grep -E '^Z|defunct' | wc -l)
if [ "$ZOMBIE_COUNT" -gt 0 ]; then
    echo -e "${RED}⚠ 发现 $ZOMBIE_COUNT 个僵尸进程！${NC}"
else
    echo -e "${GREEN}✓ 无僵尸进程${NC}"
fi
echo ""

#-------------------------------------------------------------------------------
# 9. 系统更新
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[9] 系统更新状态 ${NC}"
echo "----------------------------------------------"

if command -v apt &> /dev/null; then
    UPDATES=$(apt list --upgradable 2>/dev/null | grep -v "Listing..." | wc -l)
    echo "可更新包数量: $UPDATES"
elif command -v yum &> /dev/null; then
    UPDATES=$(yum check-update 2>/dev/null | grep -v "^$" | grep -v "Updated Packages" | wc -l)
    echo "可更新包数量: $UPDATES"
fi

if [ "$UPDATES" -gt 0 ]; then
    echo -e "${YELLOW}⚠ 有 $UPDATES 个包需要更新${NC}"
else
    echo -e "${GREEN}✓ 系统已更新到最新${NC}"
fi
echo ""

#-------------------------------------------------------------------------------
# 健康评分
#-------------------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo -e "  健康评分"
echo -e "==========================================${NC}"
echo ""

SCORE=100

# CPU 评分
if (( $(echo "$CPU_USAGE > 90" | bc -l) )); then
    SCORE=$((SCORE - 30))
elif (( $(echo "$CPU_USAGE > 70" | bc -l) )); then
    SCORE=$((SCORE - 10))
fi

# 内存评分
if (( $(echo "$MEM_USED_PCT > 90" | bc -l) )); then
    SCORE=$((SCORE - 30))
elif (( $(echo "$MEM_USED_PCT > 80" | bc -l) )); then
    SCORE=$((SCORE - 10))
fi

# 磁盘评分
DF_OUTPUT=$(df -h | grep -v "tmpfs\|devtmpfs\|loop" | tail -n +2)
while read line; do
    pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
    if [ "$pct" -gt 90 ]; then
        SCORE=$((SCORE - 20))
    elif [ "$pct" -gt 80 ]; then
        SCORE=$((SCORE - 5))
    fi
done <<< "$DF_OUTPUT"

# 僵尸进程评分
if [ "$ZOMBIE_COUNT" -gt 0 ]; then
    SCORE=$((SCORE - 20))
fi

echo "系统健康评分: $SCORE/100"

if [ "$SCORE" -ge 90 ]; then
    echo -e "${GREEN}✓ 系统状态良好${NC}"
elif [ "$SCORE" -ge 70 ]; then
    echo -e "${YELLOW}⚠ 系统状态一般，建议关注${NC}"
else
    echo -e "${RED}✗ 系统状态较差，请尽快检查${NC}"
fi
echo ""

echo -e "${BLUE}=========================================="
echo -e "  健康检查完成"
echo -e "==========================================${NC}"