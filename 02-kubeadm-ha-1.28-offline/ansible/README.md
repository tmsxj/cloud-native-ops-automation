# ansible - Ansible Playbooks

## 功能说明

本目录包含用于批量配置和部署的 Ansible Playbooks。

## 主机清单

| 组名 | 节点 | IP | SSH别名 | 角色 |
|:-----|:-----|:---|:--------|:-----|
| deploy | tx | 127.0.0.1 | tx | 部署控制节点 |
| us | us | 43.135.167.116 | us | 美国云主机 |
| master | m1 | 192.168.1.51 | m1 | Control Plane |
| master | m2 | 192.168.1.52 | m2 | Control Plane |
| master | m3 | 192.168.1.53 | m3 | Control Plane |
| worker | w1 | 192.168.1.54 | w1 | Worker |
| worker | w2 | 192.168.1.55 | w2 | Worker |
| harbor | hb | 192.168.1.61 | hb | Harbor Registry |
| tt | tt | 192.168.1.71 | tt | 测试节点 |

## 网络架构

```
tx (腾讯云控制节点)
├── us (美国云主机) - 拉取官方镜像
├── m1/m2/m3 (Master节点)
├── w1/w2 (Worker节点)
├── hb (Harbor私有仓库)
└── tt (测试节点)

WireGuard隧道连接本地VMware网络
```

## 带宽情况

| 链路 | 带宽 | 实际速度 |
|:-----|:-----|:---------|
| us → tx | 30M | ~3MB/s |
| tx → hb | 1M | ~300KB/s |
| us → hb | 不稳定 | 30KB-3MB/s |

## 使用方法

### 1. 验证连接

```bash
# 测试所有节点连接
ansible all -i inventory.ini -m ping

# 测试特定组
ansible k8s -i inventory.ini -m ping
ansible vm -i inventory.ini -m ping
```

### 2. 执行Playbook

```bash
# 全节点预配置
ansible-playbook -i inventory.ini prepare-all.yaml

# 安装并配置containerd
ansible-playbook -i inventory.ini install-containerd.yaml

# 安装Harbor
ansible-playbook -i inventory.ini install-harbor.yaml

# Worker节点加入集群
ansible-playbook -i inventory.ini join-nodes.yaml -e "token=<TOKEN> hash=<HASH>"
```

### 3. 批量执行命令

```bash
# 在所有VM上执行命令
ansible vm -i inventory.ini -a "uptime"

# 在K8s节点上执行命令
ansible k8s -i inventory.ini -a "systemctl status containerd"

# 在master节点上查看集群状态
ansible master -i inventory.ini -a "kubectl get nodes"
```

## Playbook说明

| Playbook | 功能说明 | 目标组 |
|:---------|:---------|:-------|
| prepare-all.yaml | 全节点预配置 | vm |
| install-containerd.yaml | 安装并配置containerd | k8s |
| install-harbor.yaml | 安装Harbor | harbor |
| join-nodes.yaml | Worker节点加入集群 | worker |

## 注意事项

1. 需要在 tx 部署控制节点上执行
2. 需要配置 SSH 免密登录到所有节点
3. 需要安装 Ansible：`pip install ansible` 或 `apt install ansible`