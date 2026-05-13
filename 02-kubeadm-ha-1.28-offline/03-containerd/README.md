# 03-containerd - Containerd配置

## 功能说明

本目录包含 containerd 容器运行时的配置脚本。

## 脚本清单

| 脚本 | 功能说明 |
|:-----|:---------|
| configure.sh | Containerd配置脚本 |

## 使用方法

### 在所有K8s节点上执行

```bash
# 进入目录
cd 03-containerd

# 添加执行权限
chmod +x configure.sh

# 执行脚本（需要root权限）
sudo ./configure.sh
```

## 脚本功能

`configure.sh` 脚本完成以下配置：

1. **修改sandbox_image**：指向 Harbor 的 pause 镜像
2. **设置SystemdCgroup**：设置为 true（与 kubelet 一致）
3. **配置registry路径**：启用 certs.d 机制
4. **创建hosts.toml**：配置 Harbor 仓库 HTTP 访问
5. **重启containerd**：使配置生效

## 配置说明

### 核心配置项

| 配置项 | 值 | 说明 |
|:-------|:---|:-----|
| sandbox_image | 192.168.1.61/registry.k8s.io/pause:3.9 | 基础容器镜像 |
| SystemdCgroup | true | cgroup驱动 |
| config_path | /etc/containerd/certs.d | 仓库配置目录 |

### hosts.toml 配置

```toml
server = "http://192.168.1.61"

[host."http://192.168.1.61"]
  capabilities = ["pull", "resolve"]
```

## 验证配置

```bash
# 查看配置
cat /etc/containerd/config.toml | grep -E "sandbox_image|SystemdCgroup|config_path"

# 查看hosts.toml
cat /etc/containerd/certs.d/192.168.1.61/hosts.toml

# 检查containerd状态
systemctl status containerd
```

## 注意事项

1. 需要在所有 K8s 节点上执行（master1/master2/master3/worker1/worker2）
2. 需要 root 权限
3. 确保 Harbor 已正常运行
4. 修改配置后会重启 containerd

## 下一步

完成 containerd 配置后，进入下一步初始化 Kubernetes 集群。