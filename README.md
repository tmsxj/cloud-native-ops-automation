# 云原生运维自动化仓库

> 🤖 所有脚本均由 Trae AI 生成，本人负责需求设计、测试验证与生产级优化
> 
> 专注于解决云原生运维中最常见的问题，实现"一键部署、自动运维、快速排障"

## 🛠️ 技术栈
| 领域 | 技术栈 |
| :--- | :--- |
| **AI工具** | Trae AI、GitHub Copilot |
| **容器编排** | K3s、Docker、containerd |
| **可观测性** | Prometheus、Grafana、Loki、Filebeat |
| **自动化** | Ansible、Shell脚本、GitHub Actions |
| **网络** | Calico CNI、Nginx Ingress、WireGuard |
| **操作系统** | Ubuntu 22.04 LTS、CentOS Stream 9 |

## 📦 模块介绍
| 模块 | 状态 | 描述 |
| :--- | :--- | :--- |
| [01-linux-automation](./01-linux-automation) | ✅ 已完成 | Linux系统初始化、健康检查、故障排查、日常运维脚本 |
| [02-k3s-ha-deployment](./02-k3s-ha-deployment) | 🚧 开发中 | 3 Master + 2 Worker 高可用K3s集群一键部署 |
| [03-observability-stack](./03-observability-stack) | 🚧 开发中 | Prometheus+Grafana+Loki 全栈可观测性一键部署 |
| [04-fault-injection](./04-fault-injection) | 🚧 开发中 | Linux/K8s常见故障注入与演练脚本集 |
| [05-ansible-playbooks](./05-ansible-playbooks) | 🚧 开发中 | 批量运维自动化剧本 |
| [06-ci-cd-templates](./06-ci-cd-templates) | 📋 计划中 | 云原生应用CI/CD流水线模板 |

## ✨ 核心优势
1. **AI原生**：全程使用Trae AI生成代码，大幅提升开发效率
2. **国内适配**：所有镜像和软件源均使用国内加速地址，解决网络问题
3. **开箱即用**：所有模块提供一键部署脚本，无需复杂配置
4. **生产可用**：所有脚本均经过测试验证，可直接用于生产环境

## 🚀 快速开始
### 1. 克隆仓库
```bash
git clone https://github.com/tmsxj/cloud-native-ops-automation.git
cd cloud-native-ops-automation
```
📧 联系方式
📧 邮箱：tmsxj.zjx@gmail.com
💻 GitHub：https://github.com/tmsxj
📍 位置：深圳，China
