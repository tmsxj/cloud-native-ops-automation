# ansible - Ansible Playbooks

## 功能说明

本目录包含用于批量配置和部署的 Ansible Playbooks。

## Playbook 清单

| Playbook | 功能说明 |
|:---------|:---------|
| inventory.ini | 主机清单配置 |
| prepare-all.yaml | 全节点预配置 |
| install-containerd.yaml | 安装并配置 containerd |
| install-harbor.yaml | 安装 Harbor |
| join-nodes.yaml | Worker 节点加入集群 |

## 使用方法

### 1. 配置 SSH 免密登录

```bash
# 生成密钥对
ssh-keygen -t rsa -b 4096 -N ''

# 复制密钥到所有节点
ansible-playbook -i inventory.ini -m copy -a "src=~/.ssh/id_rsa.pub dest=~/.ssh/authorized_keys" all
```

### 2. 执行预配置 Playbook

```bash
ansible-playbook -i inventory.ini prepare-all.yaml
```

### 3. 安装 containerd

```bash
ansible-playbook -i inventory.ini install-containerd.yaml
```

### 4. 安装 Harbor

```bash
ansible-playbook -i inventory.ini install-harbor.yaml
```

### 5. Worker 节点加入集群

```bash
# 在 master1 上获取 token 和 hash
export KUBEADM_TOKEN=$(kubeadm token list | grep -v TOKEN | awk '{print $1}')
export KUBEADM_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')

# 执行加入
ansible-playbook -i inventory.ini join-nodes.yaml -e "token=$KUBEADM_TOKEN hash=$KUBEADM_HASH"
```

## 主机清单说明

| 组名 | 节点 | IP | 角色 |
|:-----|:-----|:---|:-----|
| master | master1 | 192.168.1.51 | Control Plane |
| master | master2 | 192.168.1.52 | Control Plane |
| master | master3 | 192.168.1.53 | Control Plane |
| worker | worker1 | 192.168.1.54 | Worker |
| worker | worker2 | 192.168.1.55 | Worker |
| harbor | harbor | 192.168.1.61 | Harbor Registry |

## Playbook 功能说明

### prepare-all.yaml

- 更新系统软件包
- 安装依赖工具
- 关闭防火墙
- 配置内核参数
- 禁用 swap
- 设置时区
- 安装 containerd
- 配置主机名和 hosts

### install-containerd.yaml

- 配置 sandbox_image 指向 Harbor
- 设置 SystemdCgroup = true
- 配置 registry 路径
- 创建 Harbor certs 配置

### install-harbor.yaml

- 安装 Docker
- 下载并解压 Harbor
- 配置 Harbor
- 执行安装

### join-nodes.yaml

- 重置 kubeadm 配置
- 清理残留文件
- 执行 kubeadm join

## 注意事项

1. 需要安装 Ansible：`pip install ansible`
2. 需要配置 SSH 免密登录到所有节点
3. 建议在控制节点上执行 Playbooks