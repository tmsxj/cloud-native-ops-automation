# ansible - Ansible Playbooks

## 功能说明

本目录包含用于批量配置和部署的 Ansible Playbooks。

## 主机清单

### 文件：inventory.ini

```ini
[master]
m1 ansible_host=192.168.1.51 ansible_user=root
m2 ansible_host=192.168.1.52 ansible_user=root
m3 ansible_host=192.168.1.53 ansible_user=root

[worker]
w1 ansible_host=192.168.1.54 ansible_user=root
w2 ansible_host=192.168.1.55 ansible_user=root

[harbor]
hb ansible_host=192.168.1.61 ansible_user=root

[us]
us ansible_host=43.135.167.116 ansible_user=root

[test]
tt ansible_host=192.168.1.71 ansible_user=root

[all:children]
master
worker
harbor
us
test
```

## 节点列表

| 组名 | 节点 | IP | 角色 |
|:-----|:-----|:---|:-----|
| master | m1 | 192.168.1.51 | Control Plane |
| master | m2 | 192.168.1.52 | Control Plane |
| master | m3 | 192.168.1.53 | Control Plane |
| worker | w1 | 192.168.1.54 | Worker |
| worker | w2 | 192.168.1.55 | Worker |
| harbor | hb | 192.168.1.61 | Harbor私有仓库 |
| us | us | 43.135.167.116 | 美国云主机（镜像源） |
| test | tt | 192.168.1.71 | 测试节点 |

## 网络架构

```
┌─────────────────────────────────────────────────────────────┐
│                    腾讯云控制节点 (tx)                       │
│              SSH控制 / WireGuard / Ansible                  │
│                                                             │
│  SSH别名: tx(本机) → m1,m2,m3,w1,w2,hb,tt(VMware)       │
│                      ↕                                    │
│                 WireGuard隧道                               │
│                      ↕                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              本地 VMware 网络                        │   │
│  │  m1(1.51) m2(1.52) m3(1.53)  ← Master节点        │   │
│  │  w1(1.54) w2(1.55)           ← Worker节点          │   │
│  │  hb(1.61)                    ← Harbor               │   │
│  │  tt(1.71)                    ← 测试节点              │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              ↕
                        WireGuard
                              ↕
┌─────────────────────────────────────────────────────────────┐
│                  美国云主机 (us)                            │
│           43.135.167.116 / 30M带宽                        │
│           功能：拉取官方镜像（gcr.io, docker.io等）        │
└─────────────────────────────────────────────────────────────┘
```

## 带宽情况

| 链路 | 带宽 | 实际速度 | 用途 |
|:-----|:-----|:---------|:-----|
| us → tx | 30M | ~3MB/s | us到腾讯云 |
| tx → hb | 1M | ~300KB/s | tx到VMware |
| us → hb | 不稳定 | 30KB-3MB/s | us直连VMware |

## 镜像同步策略

### 推荐：us → tx → hb（中转）

```bash
# 在tx上执行
./scripts/sync_via_tx.sh -f images.txt
```

**优势**：us→tx稳定3MB/s，tx作为缓冲

### 备选：us → hb（直传）

```bash
# 仅闲时或小镜像使用
./scripts/sync_direct.sh -f images.txt
```

## 使用方法

### 1. 验证连接

```bash
# 测试所有节点
ansible all -i inventory.ini -m ping

# 测试特定组
ansible master -i inventory.ini -m ping
ansible worker -i inventory.ini -m ping
ansible harbor -i inventory.ini -m ping
```

### 2. 批量执行命令

```bash
# 查看所有节点运行时间
ansible all -i inventory.ini -a "uptime"

# 在K8s节点上检查containerd
ansible k8s -i inventory.ini -a "systemctl status containerd"

# 查看K8s集群状态
ansible master -i inventory.ini -a "kubectl get nodes"
```

### 3. 执行Playbook

```bash
# 全节点预配置
ansible-playbook -i inventory.ini prepare-all.yaml

# 安装并配置containerd
ansible-playbook -i inventory.ini install-containerd.yaml

# 安装Harbor
ansible-playbook -i inventory.ini install-harbor.yaml

# Worker节点加入集群
ansible-playbook -i inventory.ini join-nodes.yaml \
  -e "token=<TOKEN> hash=<HASH>"
```

## Playbook说明

| Playbook | 功能 | 目标组 |
|:---------|:-----|:-------|
| prepare-all.yaml | 全节点预配置 | master, worker |
| install-containerd.yaml | 安装配置containerd | master, worker |
| install-harbor.yaml | 安装Harbor | harbor |
| join-nodes.yaml | Worker节点加入集群 | worker |

## 注意事项

1. **执行位置**：在 tx 腾讯云控制节点上执行
2. **SSH免密**：需配置 SSH 免密登录到所有节点
3. **SSH别名**：在 `~/.ssh/config` 中配置 m1,m2,m3,w1,w2,hb,tt,us 等别名
4. **Ansible安装**：`apt install ansible` 或 `pip install ansible`