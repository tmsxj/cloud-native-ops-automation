#!/bin/bash

###############################################################################
# 脚本名称：sync_via_tx.sh
# 功能说明：镜像同步脚本（us → tx → hb 中转方式）
# 适用场景：推荐使用，通过腾讯云中转传输镜像
# 使用方法：./sync_via_tx.sh -f <镜像列表文件> [限速 KB/s]
#          ./sync_via_tx.sh <镜像名> [限速 KB/s]
#
# 传输路径：us(拉取) → tx(中转) → hb(加载推送)
# 带宽情况：us→tx: 3MB/s, tx→hb: 300KB/s
###############################################################################

set -euo pipefail

# ---------- 配置区 ----------
HARBOR_ADDR="192.168.1.61"
HARBOR_USER="admin"
HARBOR_PASS="Harbor12345"
HARBOR_PROJECT="library"
SSH_US="us"
SSH_TX="tx"
SSH_HB="hb"
TMP_TX="/tmp/sync_images"
TMP_HB="/tmp/sync_images"
# ---------------------------

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    echo "用法: $0 [-f 镜像列表文件] [镜像1] [镜像2] ... [限速 KB/s]"
    echo ""
    echo "传输路径: us → tx → hb"
    echo "带宽情况: us→tx: ~3MB/s, tx→hb: ~300KB/s"
    echo ""
    echo "选项:"
    echo "  -f <文件>   从文件读取镜像列表（每行一个镜像，支持 # 注释）"
    echo "  限速参数为最后一个数字参数，单位 KB/s，0 或不填表示不限速"
    exit 1
}

check_deps() {
    local deps=("ssh" "rsync" "md5sum")
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}错误：依赖命令 '$cmd' 未找到${NC}"
            exit 1
        fi
    done
}

check_connectivity() {
    echo -e "${YELLOW}[连接检查]${NC}"
    
    # 检查us连接
    echo -n "  us (43.135.167.116): "
    if ssh -o ConnectTimeout=5 $SSH_US "echo OK" &>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}失败${NC}"
        echo -e "${RED}错误：无法连接到美国服务器${NC}"
        exit 1
    fi
    
    # 检查hb连接
    echo -n "  hb (192.168.1.61): "
    if ssh -o ConnectTimeout=5 $SSH_HB "echo OK" &>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}失败${NC}"
        echo -e "${RED}错误：无法连接到Harbor节点${NC}"
        exit 1
    fi
    
    echo ""
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
            echo -e "${RED}未知选项: $1${NC}"
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
        echo -e "${RED}错误：镜像列表文件 '$IMAGE_FILE' 不存在${NC}"
        exit 1
    fi
    while IFS= read -r line; do
        line=$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [[ -n "$line" ]] && IMAGES+=("$line")
    done < "$IMAGE_FILE"
fi

if [[ ${#IMAGES[@]} -eq 0 ]]; then
    echo -e "${RED}错误：未指定任何镜像${NC}"
    usage
fi

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  镜像同步 - 中转模式 (us → tx → hb)${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e "镜像数量: ${#IMAGES[@]} 个"
echo -e "传输路径: us → tx → hb"
echo -e "限速: ${BW_LIMIT} KB/s (tx→hb)"
echo ""
echo "镜像列表:"
printf '  - %s\n' "${IMAGES[@]}"
echo ""

# 检查连接
check_connectivity

TIMESTAMP=$(date +%Y%m%d%H%M%S)
PACKAGE_NAME="images-${TIMESTAMP}.tar.gz"
TX_PACKAGE="${TMP_TX}/${PACKAGE_NAME}"
HB_PACKAGE="${TMP_HB}/${PACKAGE_NAME}"
TX_MD5="${TMP_TX}/${PACKAGE_NAME}.md5"
HB_MD5="${TMP_HB}/${PACKAGE_NAME}.md5"

# 在tx和hb上创建临时目录
ssh $SSH_TX "mkdir -p $TMP_TX"
ssh $SSH_HB "mkdir -p $TMP_HB"

# ========== 阶段1: us拉取镜像 ==========
echo -e "${BLUE}[阶段1] 美国服务器拉取镜像${NC}"
echo "----------------------------------------------"

for img in "${IMAGES[@]}"; do
    echo -e "${YELLOW}>> 拉取 $img${NC}"
    if ! ssh $SSH_US "docker pull $img"; then
        echo -e "${RED}   拉取失败: $img${NC}"
        exit 1
    fi
done
echo -e "${GREEN}✓ 镜像拉取完成${NC}"
echo ""

# ========== 阶段2: us → tx 传输 ==========
echo -e "${BLUE}[阶段2] us → tx 传输 (~3MB/s)${NC}"
echo "----------------------------------------------"

# 打包镜像
echo -e "${YELLOW}>> 打包镜像${NC}"
IMGS_STR=$(printf "%s " "${IMAGES[@]}")
ssh $SSH_US "docker save $IMGS_STR | gzip > ${TMP_TX}/${PACKAGE_NAME}"

# 计算MD5
US_MD5=$(ssh $SSH_US "md5sum ${TMP_TX}/${PACKAGE_NAME} | cut -d' ' -f1")
echo -e "MD5: $US_MD5"

echo -e "${GREEN}✓ us → tx 传输完成${NC}"
echo ""

# ========== 阶段3: tx → hb 传输 ==========
echo -e "${BLUE}[阶段3] tx → hb 传输 (~300KB/s)${NC}"
echo "----------------------------------------------"

RSYNC_OPTS="-avzP"
if [[ $BW_LIMIT -gt 0 ]]; then
    RSYNC_OPTS="$RSYNC_OPTS --bwlimit=$BW_LIMIT"
    echo -e "限速: ${BW_LIMIT} KB/s"
fi

echo -e "${YELLOW}>> 传输文件到hb${NC}"
ssh $SSH_HB "rsync $RSYNC_OPTS ${SSH_TX}:${TMP_TX}/${PACKAGE_NAME} ${HB_PACKAGE}"

# 传输MD5
ssh $SSH_HB "rsync $RSYNC_OPTS ${SSH_TX}:${TMP_TX}/${PACKAGE_NAME}.md5 ${HB_MD5}"

# 校验MD5
HB_MD5=$(ssh $SSH_HB "md5sum ${HB_PACKAGE} | cut -d' ' -f1")
if [[ "$HB_MD5" != "$US_MD5" ]]; then
    echo -e "${RED}错误：MD5校验失败！${NC}"
    echo "  预期: $US_MD5"
    echo "  实际: $HB_MD5"
    exit 1
fi
echo -e "${GREEN}✓ tx → hb 传输完成 (MD5校验通过)${NC}"
echo ""

# ========== 阶段4: hb加载并推送镜像 ==========
echo -e "${BLUE}[阶段4] Harbor节点加载并推送镜像${NC}"
echo "----------------------------------------------"

# 登录Harbor
echo -e "${YELLOW}>> 登录Harbor${NC}"
ssh $SSH_HB "echo $HARBOR_PASS | docker login -u $HARBOR_USER --password-stdin $HARBOR_ADDR" || {
    echo -e "${RED}登录Harbor失败${NC}"
    exit 1
}

# 加载镜像
echo -e "${YELLOW}>> 加载镜像到Docker${NC}"
ssh $SSH_HB "gunzip -c ${HB_PACKAGE} | docker load"

# 推送镜像
echo -e "${YELLOW}>> 推送镜像到Harbor${NC}"
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
    
    echo -e "  $img → $harbor_img"
    ssh $SSH_HB "docker tag $img $harbor_img && docker push $harbor_img" || {
        echo -e "${RED}   推送失败: $harbor_img${NC}"
        exit 1
    }
done
echo -e "${GREEN}✓ 镜像推送完成${NC}"
echo ""

# ========== 阶段5: 清理临时文件 ==========
echo -e "${BLUE}[阶段5] 清理临时文件${NC}"
echo "----------------------------------------------"

ssh $SSH_US "rm -rf ${TMP_TX}/${PACKAGE_NAME}*"
ssh $SSH_TX "rm -rf ${TMP_TX}/${PACKAGE_NAME}*"
ssh $SSH_HB "rm -rf ${TMP_HB}/${PACKAGE_NAME}*"

echo -e "${GREEN}✓ 清理完成${NC}"
echo ""

# ========== 完成 ==========
echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}  镜像同步完成！${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e "总镜像数: ${#IMAGES[@]}"
echo -e "Harbor地址: $HARBOR_ADDR"
echo ""