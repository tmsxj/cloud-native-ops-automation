# 05-calico - Calico网络插件

## 功能说明

本目录包含 Calico 网络插件的安装脚本。

## 脚本清单

| 脚本 | 功能说明 |
|:-----|:---------|
| install-calico.sh | Calico安装脚本 |

## 使用方法

### 在master1上执行

```bash
# 进入目录
cd 05-calico

# 添加执行权限
chmod +x install-calico.sh

# 执行脚本
./install-calico.sh
```

## 脚本功能

`install-calico.sh` 脚本完成以下步骤：

1. **下载配置文件**：从 GitHub 下载 calico.yaml
2. **修改配置**：修改 Pod 网络 CIDR
3. **应用配置**：kubectl apply -f calico.yaml
4. **等待部署**：等待 Calico Pod 启动
5. **验证状态**：检查网络状态

## 网络配置

| 配置项 | 值 | 说明 |
|:-------|:---|:-----|
| Pod网络CIDR | 10.244.0.0/16 | 与 kubeadm 配置一致 |
| 默认模式 | IPIP | 三层网络隧道 |

## 网络模式切换

### 切换到 VXLAN

```bash
kubectl patch ippool default-ipv4-ippool -p '{"spec":{"ipipMode":"Never","vxlanMode":"Always"}}'
```

### 切换到纯 BGP

```bash
kubectl patch ippool default-ipv4-ippool -p '{"spec":{"ipipMode":"Never","vxlanMode":"Never"}}'
```

### 模式对比

| 模式 | 封装 | 性能 | 网络要求 |
|:-----|:-----|:-----|:---------|
| 纯BGP | 无 | 最高 | 二层可达或支持BGP |
| IPIP | IP-in-IP | 中等 | 三层可达（默认） |
| VXLAN | UDP | 较低 | 任意（UDP 4500） |

## 验证

```bash
# 查看Calico Pod状态
kubectl get pods -n kube-system | grep calico

# 查看IP池配置
kubectl get ippools.crd.projectcalico.org -o yaml

# 查看节点状态（应为Ready）
kubectl get nodes
```

## 注意事项

1. 只在 master1 上执行即可
2. 需要等待一段时间让网络配置生效
3. Pod网络CIDR必须与kubeadm配置一致

## 下一步

完成 Calico 安装后，部署监控系统。