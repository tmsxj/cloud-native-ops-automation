#!/bin/bash

###############################################################################
# 脚本名称：get_images_from_chart.sh
# 功能说明：从Helm Chart中提取镜像列表
# 适用场景：离线部署前获取Chart所需的所有镜像
# 使用方法：在Chart目录下执行 ./get_images_from_chart.sh
###############################################################################

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo -e "  从Helm Chart提取镜像列表"
echo -e "==========================================${NC}"
echo ""

# 检查当前目录是否包含 Chart.yaml
if [ ! -f Chart.yaml ]; then
    echo -e "${RED}错误：当前目录不是 Helm Chart 根目录（未找到 Chart.yaml）${NC}"
    exit 1
fi

echo -e "${YELLOW}正在渲染 Helm Chart 模板...${NC}"
helm template . > rendered.yaml 2>&1

echo -e "${YELLOW}提取镜像列表...${NC}"
grep -E 'image:' rendered.yaml | awk '{print $2}' | sort -u > images.txt
sed 's/"//g' images.txt > images-clean.txt

rm -f rendered.yaml

echo -e "${GREEN}镜像列表已生成：${NC}"
echo "  原始文件: images.txt"
echo "  清理后文件: images-clean.txt"
echo "  镜像数量: $(wc -l < images-clean.txt)"
echo ""

echo -e "${BLUE}==========================================${NC}"