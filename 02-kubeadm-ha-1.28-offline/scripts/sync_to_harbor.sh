#!/bin/bash

###############################################################################
# 脚本名称：sync_to_harbor.sh
# 功能说明：镜像同步脚本（美国服务器 -> Harbor）
# 适用场景：离线部署时同步镜像到Harbor私有仓库
# 使用方法：./sync_to_harbor.sh -f <镜像列表文件> [限速 KB/s]
#          ./sync_to_harbor.sh <镜像名> [限速 KB/s]
###############################################################################

set -euo pipefail

# ---------- 配置区 ----------
HARBOR_ADDR="192.168.1.61"
HARBOR_USER="admin"
HARBOR_PASS="Harbor12345"
HARBOR_PROJECT="library"
SSH_US_ALIAS="us"
SSH_HB_ALIAS="hb"
TMP_HB="/tmp/sync2harbor"
TMP_US="/tmp"
# ---------------------------

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    echo "用法: $0 [-f 镜像列表文件] [镜像1] [镜像2] ... [限速 KB/s]"
    echo "选项:"
    echo "  -f <文件>   从文件读取镜像列表（每行一个镜像，支持 # 注释）"
    echo "限速参数为最后一个数字参数，单位 KB/s，0 或不填表示不限速。"
    exit 1
}

check_deps() {
    local deps=("ssh" "rsync" "md5sum" "curl")
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "错误：依赖命令 '$cmd' 未找到，请先安装。"
            exit 1
        fi
    done
}

IMAGES=()
BW_LIMIT=0
FILE_MODE=0

while [[ $# -gt 0 ]]; do
    case $1 in
        -f)
            FILE_MODE=1
            IMAGE_FILE="$2"
            shift 2
            ;;
        -*)
            echo "未知选项: $1"
            usage
            ;;
        *)
            if [[ $1 =~ ^[0-9]+$ ]] && [[ $# -eq 1 ]]; then
                BW_LIMIT=$1
            else
                IMAGES+=("$1")
            fi
            shift
            ;;
    esac
done

if [[ $FILE_MODE -eq 1 ]]; then
    if [[ ! -f "$IMAGE_FILE" ]]; then
        echo "错误：镜像列表文件 '$IMAGE_FILE' 不存在。"
        exit 1
    fi
    while IFS= read -r line; do
        line=$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [[ -n "$line" ]] && IMAGES+=("$line")
    done < "$IMAGE_FILE"
fi

if [[ ${#IMAGES[@]} -eq 0 ]]; then
    echo "错误：未指定任何镜像。"
    usage
fi

echo -e "${BLUE}========== 镜像同步任务开始 ==========${NC}"
echo "需同步的镜像列表 (${#IMAGES[@]} 个):"
printf '  %s\n' "${IMAGES[@]}"
echo "限速: $BW_LIMIT KB/s"

TIMESTAMP=$(date +%Y%m%d%H%M%S)
PACKAGE_NAME="images-${TIMESTAMP}.tar.gz"
US_PACKAGE_PATH="$TMP_US/$PACKAGE_NAME"
HB_PACKAGE_PATH="$TMP_HB/$PACKAGE_NAME"
US_MD5_FILE="$TMP_US/$PACKAGE_NAME.md5"
HB_MD5_FILE="$TMP_HB/$PACKAGE_NAME.md5"

ssh "$SSH_HB_ALIAS" "mkdir -p $TMP_HB"

echo -e "${BLUE}========== 阶段1：美国服务器处理 ==========${NC}"
ssh "$SSH_US_ALIAS" "docker version" > /dev/null || { echo -e "${RED}错误：美国服务器 docker 不可用${NC}"; exit 1; }

IMGS_STR=$(printf "%s " "${IMAGES[@]}")

echo -e "${YELLOW}>> 拉取镜像...${NC}"
for img in "${IMAGES[@]}"; do
    echo "   拉取 $img"
    if ! ssh "$SSH_US_ALIAS" "docker pull $img"; then
        echo -e "${RED}   拉取失败，终止。${NC}"
        exit 1
    fi
done

echo -e "${YELLOW}>> 打包镜像...${NC}"
if ssh "$SSH_US_ALIAS" "docker save $IMGS_STR | gzip > $US_PACKAGE_PATH"; then
    echo "   打包成功：$US_PACKAGE_PATH"
else
    echo -e "${RED}   打包失败。${NC}"
    exit 1
fi

echo -e "${YELLOW}>> 计算 MD5...${NC}"
US_MD5=$(ssh "$SSH_US_ALIAS" "md5sum $US_PACKAGE_PATH | cut -d' ' -f1")
echo "   us MD5: $US_MD5"
ssh "$SSH_US_ALIAS" "echo $US_MD5 > $US_MD5_FILE"

echo -e "${BLUE}========== 阶段2：直传到 Harbor 虚拟机 ==========${NC}"
RSYNC_OPTS="-avzP"
[[ $BW_LIMIT -gt 0 ]] && RSYNC_OPTS="$RSYNC_OPTS --bwlimit=$BW_LIMIT"

echo -e "${YELLOW}>> 在 Harbor 虚拟机上拉取打包文件...${NC}"
if ssh "$SSH_HB_ALIAS" "rsync $RSYNC_OPTS $SSH_US_ALIAS:$US_PACKAGE_PATH $HB_PACKAGE_PATH"; then
    echo "   传输成功"
else
    echo -e "${RED}传输失败${NC}"
    exit 1
fi

echo -e "${YELLOW}>> 传输 MD5 文件...${NC}"
if ssh "$SSH_HB_ALIAS" "rsync -avz $SSH_US_ALIAS:$US_MD5_FILE $HB_MD5_FILE"; then
    echo "   MD5 文件传输成功"
else
    echo -e "${RED}MD5 文件传输失败${NC}"
    exit 1
fi

echo -e "${BLUE}========== 阶段3：Harbor 虚拟机处理 ==========${NC}"
HB_MD5=$(ssh "$SSH_HB_ALIAS" "md5sum $HB_PACKAGE_PATH | cut -d' ' -f1")
US_MD5=$(ssh "$SSH_HB_ALIAS" "cat $HB_MD5_FILE")
if [[ "$HB_MD5" != "$US_MD5" ]]; then
    echo -e "${RED}错误：MD5 校验不一致，文件可能损坏${NC}"
    echo "   us MD5: $US_MD5"
    echo "   hb MD5: $HB_MD5"
    exit 1
else
    echo -e "${GREEN}✅ MD5 校验一致${NC}"
fi

echo -e "${YELLOW}>> 加载镜像...${NC}"
ssh "$SSH_HB_ALIAS" "gunzip -c $HB_PACKAGE_PATH | docker load" || {
    echo -e "${RED}镜像加载失败${NC}"
    exit 1
}
echo -e "${GREEN}✅ 镜像加载成功${NC}"

echo -e "${YELLOW}>> 检测 Harbor 服务...${NC}"
if ! ssh "$SSH_HB_ALIAS" "curl -s -o /dev/null -w '%{http_code}' http://$HARBOR_ADDR/v2/" | grep -q 401; then
    echo -e "${YELLOW}⚠️ Harbor 服务不可达，请检查 Harbor 容器状态${NC}"
    exit 1
fi

echo -e "${YELLOW}>> 登录 Harbor...${NC}"
if ! ssh "$SSH_HB_ALIAS" "echo $HARBOR_PASS | docker login -u $HARBOR_USER --password-stdin $HARBOR_ADDR" 2>/dev/null; then
    echo "登录失败，尝试重新登录..."
    ssh "$SSH_HB_ALIAS" "echo $HARBOR_PASS | docker login -u $HARBOR_USER --password-stdin $HARBOR_ADDR" || {
        echo -e "${RED}登录失败，退出${NC}"
        exit 1
    }
fi
echo -e "${GREEN}✅ 登录成功${NC}"

echo -e "${YELLOW}>> 推送镜像...${NC}"
for img in "${IMAGES[@]}"; do
    if [[ "$img" == *":"* ]]; then
        repo="${img%:*}"
        tag="${img#*:}"
    else
        repo="$img"
        tag="latest"
    fi
    safe_repo=$(echo "$repo" | tr '/' '_')
    harbor_img="$HARBOR_ADDR/$HARBOR_PROJECT/$safe_repo:$tag"
    echo "   推送 $harbor_img"
    ssh "$SSH_HB_ALIAS" "docker tag $img $harbor_img && docker push $harbor_img" || {
        echo -e "${RED}   推送失败: $harbor_img${NC}"
        exit 1
    }
done

echo -e "${BLUE}========== 阶段4：验证镜像 ==========${NC}"
for img in "${IMAGES[@]}"; do
    if [[ "$img" == *":"* ]]; then
        repo="${img%:*}"
        tag="${img#*:}"
    else
        repo="$img"
        tag="latest"
    fi
    safe_repo=$(echo "$repo" | tr '/' '_')
    echo -e "${YELLOW}>> 验证 $HARBOR_PROJECT/$safe_repo:$tag${NC}"
    http_code=$(curl -u "$HARBOR_USER:$HARBOR_PASS" -s -o /dev/null -w "%{http_code}" \
        "http://$HARBOR_ADDR/api/v2.0/projects/$HARBOR_PROJECT/repositories/$safe_repo/tags/$tag")
    if [[ "$http_code" -eq 200 ]]; then
        echo -e "${GREEN}✅ 存在${NC}"
    else
        echo -e "${RED}❌ 不存在 (HTTP $http_code)${NC}"
    fi
done

echo -e "${BLUE}========== 清理临时文件 ==========${NC}"
ssh "$SSH_US_ALIAS" "rm -f $US_PACKAGE_PATH $US_MD5_FILE"
ssh "$SSH_HB_ALIAS" "rm -f $HB_PACKAGE_PATH $HB_MD5_FILE"
echo -e "${GREEN}✅ 清理完成${NC}"

echo -e "${BLUE}========== 任务全部成功！==========${NC}"