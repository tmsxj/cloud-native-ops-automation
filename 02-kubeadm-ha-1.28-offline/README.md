# kubeadm HA 1.28 离线部署项目

> 基于 VMware Workstation 16 的 6 节点 Kubernetes v1.28.15 离线部署集群

## 🏗️ 架构图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          网络架构                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌──────────────┐      ┌──────────────┐      ┌──────────────┐              │
│   │   master1    │      │   master2    │      │   master3    │              │
│   │  192.168.1.51│      │  192.168.1.52│      │  192.168.1.53│              │
│   │   Control    │      │   Control    │      │   Control    │              │
│   │    Plane     │      │    Plane     │      │    Plane     │              │
│   └──────┬───────┘      └──────┬───────┘      └──────┬───────┘              │
│          │                     │                     │                      │
│          └─────────────────────┼─────────────────────┘                      │
│                                ▼                                           │
│   ┌──────────────┐      ┌──────────────┐      ┌──────────────┐              │
│   │   worker1    │      │   worker2    │      │   harbor    │              │
│   │  192.168.1.54│      │  192.168.1.55│      │  192.168.1.61│              │
│   │    Worker    │      │    Worker    │      │   Registry  │              │
│   └──────────────┘      └──────────────┘      └──────┬───────┘              │
│                                                       │                     │
│                                                       ▼                     │
│   ┌──────────────────────────────────────────────────────────────────┐       │
│   │                      美国云服务器 (43.135.167.116)                │       │
│   │              镜像源 → 同步到 Harbor → 集群节点拉取                   │       │
│   └──────────────────────────────────────────────────────────────────┘       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 📋 节点规划

| 节点 | IP 地址 | 角色 | 操作系统 | 配置建议 |
|:-----|:--------|:-----|:---------|:---------|
| master1 | 192.168.1.51 | Control Plane | Ubuntu 22.04 LTS | 2核4GB |
| master2 | 192.168.1.52 | Control Plane | Ubuntu 22.04 LTS | 2核4GB |
| master3 | 192.168.1.53 | Control Plane | Ubuntu 22.04 LTS | 2核4GB |
| worker1 | 192.168.1.54 | Worker | Ubuntu 22.04 LTS | 4核8GB |
| worker2 | 192.168.1.55 | Worker | Ubuntu 22.04 LTS | 4核8GB |
| harbor | 192.168.1.61 | Harbor Registry | Ubuntu 22.04 LTS | 4核8GB |

## 🛠️ 技术栈

| 组件 | 版本 | 说明 |
|:-----|:-----|:-----|
| Kubernetes | v1.28.15 | kubeadm 部署 |
| Container Runtime | containerd 1.7.x | 容器运行时 |
| Network Plugin | Calico v3.26 | 网络插件 |
| Registry | Harbor v2.9.0 | 私有镜像仓库 |
| Monitoring | Prometheus + Grafana | 指标监控 |
| Logging | ELK Stack | 日志收集 |
| Tracing | Jaeger | 链路追踪 |
| Demo App | OpenTelemetry Demo | 演示应用 |

## 📁 项目结构

```
02-kubeadm-ha-1.28-offline/
├── README.md                    # 项目说明文档
├── docs/                        # 文档目录
│   └── deployment-guide.md      # 部署指南
├── scripts/                     # 通用脚本
│   ├── sync_to_harbor.sh        # 镜像同步脚本
│   ├── get_images_from_chart.sh # 从Chart提取镜像
│   └── validate_cluster.sh      # 集群验证脚本
├── ansible/                     # Ansible Playbooks
│   ├── inventory.ini            # 主机清单
│   ├── prepare-all.yaml         # 全节点预配置
│   ├── install-containerd.yaml  # 安装containerd
│   └── join-nodes.yaml          # 节点加入
├── configs/                     # 配置文件模板
│   ├── containerd/              # containerd配置
│   ├── kubeadm/                 # kubeadm配置
│   └── harbor/                  # Harbor配置
├── 01-prepare/                  # 阶段1: 环境准备
│   ├── README.md
│   └── prepare.sh
├── 02-harbor/                   # 阶段2: Harbor部署
│   ├── README.md
│   ├── install.sh
│   └── harbor.yml
├── 03-containerd/               # 阶段3: Containerd配置
│   ├── README.md
│   └── configure.sh
├── 04-k8s-init/                 # 阶段4: K8s初始化
│   ├── README.md
│   ├── init-master1.sh
│   └── join-nodes.sh
├── 05-calico/                   # 阶段5: Calico安装
│   ├── README.md
│   └── install-calico.sh
├── 06-monitoring/               # 阶段6: 监控部署
│   ├── README.md
│   ├── install-prometheus.sh
│   └── values/
├── 07-logging/                  # 阶段7: 日志部署
│   ├── README.md
│   ├── install-elk.sh
│   └── manifests/
└── 08-demo/                     # 阶段8: 演示应用
    ├── README.md
    ├── install-demo.sh
    └── manifests/
```

## 🚀 部署流程

```
┌─────────────────┐
│ 1. 环境准备     │  → 所有节点配置hostname、时区、关闭防火墙等
└────────┬────────┘
         ▼
┌─────────────────┐
│ 2. Harbor部署   │  → 在harbor节点安装Harbor私有仓库
└────────┬────────┘
         ▼
┌─────────────────┐
│ 3. 镜像同步     │  → 从美国服务器同步镜像到Harbor
└────────┬────────┘
         ▼
┌─────────────────┐
│ 4. Containerd   │  → 配置所有节点使用Harbor镜像
└────────┬────────┘
         ▼
┌─────────────────┐
│ 5. K8s初始化    │  → kubeadm init + join
└────────┬────────┘
         ▼
┌─────────────────┐
│ 6. Calico安装   │  → 安装网络插件
└────────┬────────┘
         ▼
┌─────────────────┐
│ 7. 监控部署     │  → Prometheus + Grafana
└────────┬────────┘
         ▼
┌─────────────────┐
│ 8. 日志部署     │  → ELK Stack
└────────┬────────┘
         ▼
┌─────────────────┐
│ 9. 演示应用     │  → OpenTelemetry Demo
└─────────────────┘
```

## 🔧 快速开始

### 前置条件

1. 6 台 Ubuntu 22.04 LTS 虚拟机（或物理机）
2. 所有节点已配置好网络，可互相访问
3. 已配置 SSH 免密登录
4. 美国云服务器（43.135.167.116）可访问外网拉取镜像

### 部署步骤

```bash
# 1. 克隆项目
git clone https://github.com/tmsxj/cloud-native-ops-automation.git
cd 02-kubeadm-ha-1.28-offline

# 2. 配置主机清单
vim ansible/inventory.ini

# 3. 执行各阶段部署
cd 01-prepare && ./prepare.sh
cd ../02-harbor && ./install.sh
cd ../03-containerd && ./configure.sh
cd ../04-k8s-init && ./init-master1.sh
cd ../05-calico && ./install-calico.sh
cd ../06-monitoring && ./install-prometheus.sh
cd ../07-logging && ./install-elk.sh
cd ../08-demo && ./install-demo.sh

# 4. 验证集群
../scripts/validate_cluster.sh
```

## 📝 核心配置说明

### kubeadm 配置要点

```yaml
kubernetesVersion: v1.28.0
imageRepository: 192.168.1.61/registry.k8s.io
networking:
  podSubnet: "10.244.0.0/16"
etcd:
  local:
    dataDir: /data/etcd
    extraArgs:
      snapshot-count: "10000"
      auto-compaction-retention: "1"
      quota-backend-bytes: "4294967296"
```

### containerd 配置要点

- 使用 `192.168.1.61/registry.k8s.io/pause:3.9` 作为 sandbox 镜像
- 配置 `/etc/containerd/certs.d/192.168.1.61/hosts.toml` 支持 HTTP 访问 Harbor
- 设置 `SystemdCgroup = true` 与 kubelet cgroup 驱动一致

### Harbor 配置要点

- HTTP 端口：80
- 管理员密码：Harbor12345
- 数据目录：/data
- 漏洞扫描：Trivy

## 📌 关键注意事项

1. **镜像同步**：从美国服务器拉取镜像后，通过 rsync 传输到 Harbor 虚拟机，再 push 到 Harbor
2. **Calico 网络**：默认使用 IPIP 模式，可根据网络环境切换为 VXLAN 或纯 BGP
3. **证书管理**：kubeadm 默认证书有效期一年，需定期续期或配置自动轮换
4. **资源规划**：Worker 节点建议至少 4 核 8GB，运行监控和日志组件需要足够资源

## 📖 目录说明

| 目录 | 作用 | 关键文件 |
|:-----|:-----|:---------|
| scripts/ | 通用脚本 | 镜像同步、验证脚本 |
| ansible/ | Ansible剧本 | 批量配置、安装 |
| configs/ | 配置模板 | containerd、kubeadm、Harbor |
| 01-prepare/ | 环境准备 | 主机名、时区、依赖安装 |
| 02-harbor/ | Harbor部署 | 私有仓库安装配置 |
| 03-containerd/ | 运行时配置 | containerd配置 |
| 04-k8s-init/ | K8s初始化 | kubeadm init/join |
| 05-calico/ | 网络插件 | Calico安装 |
| 06-monitoring/ | 监控系统 | Prometheus/Grafana |
| 07-logging/ | 日志系统 | ELK Stack |
| 08-demo/ | 演示应用 | OpenTelemetry Demo |

## 📞 问题排查

### 常见问题

| 问题 | 原因 | 解决方法 |
|:-----|:-----|:---------|
| Pod 启动失败 | containerd cgroup 驱动不一致 | 设置 `SystemdCgroup = true` |
| 镜像拉取失败 | Harbor 认证问题 | 创建 imagePullSecret |
| 网络不通 | Calico 配置错误 | 检查 podSubnet 配置 |
| 证书过期 | 默认证书有效期一年 | `kubeadm certs renew all` |

### 日志位置

- kubelet: `/var/log/kubelet.log`
- containerd: `/var/log/containerd/`
- Kubernetes: `kubectl logs -n kube-system <pod>`
- Harbor: `/var/log/harbor/`

## 📄 许可证

MIT License