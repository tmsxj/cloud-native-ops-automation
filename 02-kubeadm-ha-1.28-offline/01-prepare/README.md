# 01-prepare - 环境准备

## 功能说明

本目录包含 Kubernetes 集群部署前的环境准备脚本，用于配置所有节点的基础环境。

## 脚本清单

| 脚本 | 功能说明 |
|:-----|:---------|
| prepare.sh | 所有节点环境准备脚本 |

## 使用方法

### 在所有节点上执行

```bash
# 进入目录
cd 01-prepare

# 添加执行权限
chmod +x prepare.sh

# 执行脚本（需要root权限）
sudo ./prepare.sh
```

## 脚本功能

`prepare.sh` 脚本完成以下配置：

1. **系统更新**：更新系统软件包
2. **依赖安装**：安装必要的工具和依赖
3. **防火墙关闭**：关闭 ufw/firewalld 和 SELinux
4. **内核参数**：配置 k8s 所需的内核参数
5. **swap禁用**：禁用 swap（k8s 要求）
6. **时区配置**：设置为 Asia/Shanghai
7. **containerd依赖**：安装 containerd.io

## 注意事项

1. 脚本需要 root 权限执行
2. 需要在所有节点上执行
3. 执行完成后需要配置主机名
4. 需要手动配置 SSH 免密登录

## 主机名配置（手动执行）

在各节点上执行：

```bash
# master1
hostnamectl set-hostname master1
echo "192.168.1.51 master1" >> /etc/hosts

# master2
hostnamectl set-hostname master2
echo "192.168.1.52 master2" >> /etc/hosts

# master3
hostnamectl set-hostname master3
echo "192.168.1.53 master3" >> /etc/hosts

# worker1
hostnamectl set-hostname worker1
echo "192.168.1.54 worker1" >> /etc/hosts

# worker2
hostnamectl set-hostname worker2
echo "192.168.1.55 worker2" >> /etc/hosts

# harbor
hostnamectl set-hostname harbor
echo "192.168.1.61 harbor" >> /etc/hosts
```

## 下一步

完成环境准备后，进入下一步部署 Harbor 私有仓库。