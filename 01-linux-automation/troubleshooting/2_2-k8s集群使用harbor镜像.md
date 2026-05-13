### 1.containerd配置文件修改
```shell
root@master1:/etc/containerd# diff -uw /etc/containerd/config.toml default-config.toml 
--- /etc/containerd/config.toml 2026-02-28 15:56:54.167371329 +0000
+++ default-config.toml 2026-03-19 02:09:08.855032374 +0000
@@ -64,7 +64,7 @@
     max_container_log_line_size = 16384
     netns_mounts_under_state_dir = false
     restrict_oom_score_adj = false
-    sandbox_image = "192.168.1.61/registry.k8s.io/pause:3.9"
+    sandbox_image = "registry.k8s.io/pause:3.8"
     selinux_category_range = 1024
     stats_collect_period = 10
     stream_idle_timeout = "4h0m0s"
@@ -136,7 +136,7 @@
             NoPivotRoot = false
             Root = ""
             ShimCgroup = ""
-            SystemdCgroup = true
+            SystemdCgroup = false
 
       [plugins."io.containerd.grpc.v1.cri".containerd.untrusted_workload_runtime]
         base_runtime_spec = ""
@@ -159,7 +159,7 @@
       key_model = "node"
 
     [plugins."io.containerd.grpc.v1.cri".registry]
-      config_path = "/etc/containerd/certs.d"
+      config_path = ""
 
       [plugins."io.containerd.grpc.v1.cri".registry.auths]
 
@@ -251,7 +251,7 @@
   [plugins."io.containerd.tracing.processor.v1.otlp"]
 
   [plugins."io.containerd.transfer.v1.local"]
-      config_path = "/etc/containerd/certs.d"
+    config_path = ""
     max_concurrent_downloads = 3
     max_concurrent_uploaded_layers = 3
 
root@master1:/etc/containerd# ls -la /etc/containerd/certs.d/
total 12
drwxr-xr-x 3 root root 4096 Feb 27 20:55 .
drwxr-xr-x 3 root root 4096 Mar 19 02:09 ..
drwxr-xr-x 2 root root 4096 Feb 27 19:08 192.168.1.61
root@master1:/etc/containerd# cat /etc/containerd/certs.d/192.168.1.61/hosts.toml 
server = "http://192.168.1.61"

[host."http://192.168.1.61"]
  capabilities = ["pull", "resolve"]
root@master1:/etc/containerd# 
```
### 2.关键修改配置解析
```shell
# （1）/etc/containerd/config.toml 修改部分
containerd config default > /tmp/default-config.toml
diff -uw /etc/containerd/config.toml default-config.toml
# 基础容器镜像（pause）设置
sandbox_image = "192.168.1.61/registry.k8s.io/pause:3.9"   # 使用本地 Harbor 中的 pause 镜像，避免从外网拉取；版本从 3.8 升级到 3.9，兼容 Kubernetes 1.28

# runc 运行时选项
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = true   # 与 kubelet 的 cgroup 驱动（systemd）保持一致，确保容器能正常启动和运行（默认 false 会导致 Pod 启动失败）

# 镜像仓库配置
[plugins."io.containerd.grpc.v1.cri".registry]
    config_path = "/etc/containerd/certs.d"   # 启用 hosts.toml 机制，让 containerd 从该目录读取每个仓库的镜像代理配置（如 HTTP 访问、跳过 TLS 验证）

# 传输层配置
[plugins."io.containerd.transfer.v1.local"]
    config_path = "/etc/containerd/certs.d"   # 保持与 registry 段的 config_path 一致，确保传输层也使用相同的镜像配置（默认值为空）
# （2）/etc/containerd/certs.d/192.168.1.61/hosts.toml
sudo mkdir -p /etc/containerd/certs.d/192.168.1.61
touch /etc/containerd/certs.d/192.168.1.61/hosts.toml
server = "http://192.168.1.61"          # 指定 Harbor 仓库的访问地址（使用 HTTP 协议）

[host."http://192.168.1.61"]
  capabilities = ["pull", "resolve"]    # 允许通过 HTTP 拉取和解析镜像，无需 TLS 验证（skip_verify 已隐含，但未显式写出）
```
### 3.配置k8s集群使用镜像仓库
```shell
# 1. 在目标命名空间创建 secret（名称可以相同，但命名空间不同）
kubectl create secret docker-registry harbor-auth \
  --docker-server=192.168.1.61 \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --namespace=dev

# 2. 将该命名空间的 default ServiceAccount 绑定 secret
kubectl patch serviceaccount default -n dev -p '{"imagePullSecrets": [{"name": "harbor-auth"}]}'
# 3.secret复用到其他命名空间
kubectl get secret harbor-auth -n default -o yaml \
  | sed '/namespace:/s/default/dev/; /creationTimestamp:/d; /resourceVersion:/d; /uid:/d; /annotations:/d' \
  | kubectl apply -n dev -f -
这条命令会：
导出 default 中的 Secret 定义
替换 namespace: default 为 namespace: dev
删除自动生成的字段
直接应用到 dev 命名空间
root@master1:~# kubectl get secret harbor-auth -n dev
NAME          TYPE                             DATA   AGE
harbor-auth   kubernetes.io/dockerconfigjson   1      14s
# 循环应用
for ns in dev test staging; do
  kubectl get secret harbor-auth -n default -o yaml \
    | sed "/namespace:/s/default/$ns/; /creationTimestamp:/d; /resourceVersion:/d; /uid:/d; /annotations:/d" \
    | kubectl apply -n $ns -f -
  kubectl patch serviceaccount default -n $ns -p '{"imagePullSecrets": [{"name": "harbor-auth"}]}'
done
# 删除指定命名空间下的secret
root@master1:~# kubectl get secret harbor-auth -n dev
```
### 4.镜像传输脚本
```shell
cat > ~/scripts/sync_to_harbor_simple.sh <<'EOF'
#!/bin/bash
# ============================================================================
# 简化版镜像同步脚本（美国服务器 -> Harbor 虚拟机直传）
# 修复：增加 Harbor 连通性检测和登录重试，修正语法错误
# ============================================================================

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

echo "========== 简化直传任务开始 =========="
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

echo "========== 阶段1：美国服务器处理 =========="
ssh "$SSH_US_ALIAS" "docker version" > /dev/null || { echo "错误：美国服务器 docker 不可用"; exit 1; }

IMGS_STR=$(printf "%s " "${IMAGES[@]}")

echo ">> 拉取镜像..."
for img in "${IMAGES[@]}"; do
    echo "   拉取 $img"
    if ! ssh "$SSH_US_ALIAS" "docker pull $img"; then
        echo "   拉取失败，终止。"
        exit 1
    fi
done

echo ">> 打包镜像..."
if ssh "$SSH_US_ALIAS" "docker save $IMGS_STR | gzip > $US_PACKAGE_PATH"; then
    echo "   打包成功：$US_PACKAGE_PATH"
else
    echo "   打包失败。"
    exit 1
fi

echo ">> 计算 MD5..."
US_MD5=$(ssh "$SSH_US_ALIAS" "md5sum $US_PACKAGE_PATH | cut -d' ' -f1")
echo "   us MD5: $US_MD5"
ssh "$SSH_US_ALIAS" "echo $US_MD5 > $US_MD5_FILE"

echo "========== 阶段2：直传到 Harbor 虚拟机 =========="
RSYNC_OPTS="-avzP"
[[ $BW_LIMIT -gt 0 ]] && RSYNC_OPTS="$RSYNC_OPTS --bwlimit=$BW_LIMIT"

echo ">> 在 Harbor 虚拟机上拉取打包文件..."
if ssh "$SSH_HB_ALIAS" "rsync $RSYNC_OPTS $SSH_US_ALIAS:$US_PACKAGE_PATH $HB_PACKAGE_PATH"; then
    echo "   传输成功"
else
    echo "传输失败"
    exit 1
fi

echo ">> 传输 MD5 文件..."
if ssh "$SSH_HB_ALIAS" "rsync -avz $SSH_US_ALIAS:$US_MD5_FILE $HB_MD5_FILE"; then
    echo "   MD5 文件传输成功"
else
    echo "MD5 文件传输失败"
    exit 1
fi

echo "========== 阶段3：Harbor 虚拟机处理 =========="
HB_MD5=$(ssh "$SSH_HB_ALIAS" "md5sum $HB_PACKAGE_PATH | cut -d' ' -f1")
US_MD5=$(ssh "$SSH_HB_ALIAS" "cat $HB_MD5_FILE")
if [[ "$HB_MD5" != "$US_MD5" ]]; then
    echo "错误：MD5 校验不一致，文件可能损坏"
    echo "   us MD5: $US_MD5"
    echo "   hb MD5: $HB_MD5"
    exit 1
else
    echo "✅ MD5 校验一致"
fi

echo ">> 加载镜像..."
ssh "$SSH_HB_ALIAS" "gunzip -c $HB_PACKAGE_PATH | docker load" || {
    echo "镜像加载失败"
    exit 1
}
echo "✅ 镜像加载成功"

# 检测 Harbor 是否可访问
echo ">> 检测 Harbor 服务..."
if ! ssh "$SSH_HB_ALIAS" "curl -s -o /dev/null -w '%{http_code}' http://$HARBOR_ADDR/v2/" | grep -q 401; then
    echo "⚠️ Harbor 服务不可达，请检查 Harbor 容器状态"
    exit 1
fi

# 登录 Harbor（使用 --password-stdin）
echo ">> 登录 Harbor..."
if ! ssh "$SSH_HB_ALIAS" "echo $HARBOR_PASS | docker login -u $HARBOR_USER --password-stdin $HARBOR_ADDR" 2>/dev/null; then
    echo "登录失败，可能是密码错误或 Harbor 未响应，尝试重新登录..."
    # 重试一次
    ssh "$SSH_HB_ALIAS" "echo $HARBOR_PASS | docker login -u $HARBOR_USER --password-stdin $HARBOR_ADDR" || {
        echo "登录失败，退出"
        exit 1
    }
fi
echo "✅ 登录成功"

echo ">> 推送镜像..."
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
        echo "   推送失败: $harbor_img"
        exit 1
    }
done

echo "========== 阶段4：验证镜像 =========="
for img in "${IMAGES[@]}"; do
    if [[ "$img" == *":"* ]]; then
        repo="${img%:*}"
        tag="${img#*:}"
    else
        repo="$img"
        tag="latest"
    fi
    safe_repo=$(echo "$repo" | tr '/' '_')
    echo ">> 验证 $HARBOR_PROJECT/$safe_repo:$tag"
    http_code=$(curl -u "$HARBOR_USER:$HARBOR_PASS" -s -o /dev/null -w "%{http_code}" \
        "http://$HARBOR_ADDR/api/v2.0/projects/$HARBOR_PROJECT/repositories/$safe_repo/tags/$tag")
    if [[ "$http_code" -eq 200 ]]; then
        echo "✅ 存在"
    else
        echo "❌ 不存在 (HTTP $http_code)"
    fi
done

echo "========== 清理临时文件 =========="
ssh "$SSH_US_ALIAS" "rm -f $US_PACKAGE_PATH $US_MD5_FILE"
ssh "$SSH_HB_ALIAS" "rm -f $HB_PACKAGE_PATH $HB_MD5_FILE"
echo "✅ 清理完成"

echo "========== 任务全部成功！=========="
EOF

chmod +x ~/scripts/sync_to_harbor_simple.sh
./sync_to_harbor_simple.sh rancher/local-path-provisioner:v0.0.35 3000
```