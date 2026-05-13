# scripts - 通用脚本

## 功能说明

本目录包含部署过程中使用的通用脚本。

## 脚本清单

| 脚本 | 功能说明 |
|:-----|:---------|
| sync_to_harbor.sh | 镜像同步脚本（美国服务器 -> Harbor） |
| get_images_from_chart.sh | 从Helm Chart提取镜像列表 |
| validate_cluster.sh | Kubernetes集群验证脚本 |

## 使用方法

### 1. sync_to_harbor.sh - 镜像同步

```bash
# 从文件读取镜像列表
./sync_to_harbor.sh -f images.txt 3000

# 同步单个镜像
./sync_to_harbor.sh nginx:latest 5000

# 参数说明
# -f <文件>   从文件读取镜像列表
# 限速参数（最后一个数字）单位 KB/s，0表示不限速
```

### 2. get_images_from_chart.sh - 提取镜像

```bash
# 在Helm Chart目录下执行
cd /path/to/chart
./get_images_from_chart.sh

# 生成文件
# images.txt - 原始镜像列表（带引号）
# images-clean.txt - 清理后的镜像列表
```

### 3. validate_cluster.sh - 集群验证

```bash
# 在master1上执行
./validate_cluster.sh

# 验证内容
# - kubectl安装
# - 集群连接状态
# - 节点状态
# - Pod状态
# - 网络插件
# - DNS服务
# - etcd状态
```

## 镜像同步流程

```
美国服务器 (43.135.167.116)
        ↓ docker pull
        ↓ docker save + gzip
        ↓ rsync
Harbor虚拟机 (192.168.1.61)
        ↓ docker load
        ↓ docker tag
        ↓ docker push
Harbor私有仓库
        ↓ 集群节点拉取
Kubernetes集群
```

## SSH配置要求

镜像同步脚本需要配置 SSH 别名：

```bash
# ~/.ssh/config
Host us
  HostName 43.135.167.116
  User root
  IdentityFile ~/.ssh/id_rsa

Host hb
  HostName 192.168.1.61
  User root
  IdentityFile ~/.ssh/id_rsa
```

## 注意事项

1. sync_to_harbor.sh 需要配置 SSH 免密登录
2. get_images_from_chart.sh 需要 Helm 3
3. validate_cluster.sh 需要在 master1 上执行

## 配置说明

### sync_to_harbor.sh 配置项

| 配置项 | 值 | 说明 |
|:-------|:---|:-----|
| HARBOR_ADDR | 192.168.1.61 | Harbor地址 |
| HARBOR_USER | admin | Harbor用户名 |
| HARBOR_PASS | Harbor12345 | Harbor密码 |
| SSH_US_ALIAS | us | 美国服务器SSH别名 |
| SSH_HB_ALIAS | hb | Harbor虚拟机SSH别名 |