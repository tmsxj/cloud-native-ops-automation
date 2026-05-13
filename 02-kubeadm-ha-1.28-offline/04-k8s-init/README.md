# 04-k8s-init - Kubernetes初始化

## 功能说明

本目录包含 Kubernetes 集群初始化脚本。

## 脚本清单

| 脚本 | 功能说明 |
|:-----|:---------|
| init-master1.sh | 在 master1 上初始化集群 |
| join-nodes.sh | 其他节点加入集群 |

## 使用方法

### 1. 在 master1（192.168.1.51）上初始化

```bash
# 进入目录
cd 04-k8s-init

# 添加执行权限
chmod +x init-master1.sh

# 执行脚本（需要root权限）
sudo ./init-master1.sh
```

### 2. 在其他节点上加入

**Worker节点（worker1/worker2）:**
```bash
# 获取加入命令（在master1上执行）
kubeadm token create --print-join-command

# 在worker节点上执行类似如下命令
sudo ./join-nodes.sh <token> <hash>
```

**控制平面节点（master2/master3）:**
```bash
# 获取证书密钥（在master1上执行）
kubeadm init phase upload-certs --upload-certs

# 在master2/master3上执行
sudo ./join-nodes.sh <token> <hash> --control-plane <cert-key>
```

## 脚本功能

### init-master1.sh

1. **创建kubeadm配置**：生成 kubeadm-config.yaml
2. **清理旧配置**：重置之前的 k8s 配置
3. **初始化集群**：执行 kubeadm init
4. **配置kubectl**：设置 kubectl 配置
5. **生成加入命令**：显示 token 和 join 命令

### join-nodes.sh

1. **解析参数**：token、hash、是否控制平面
2. **清理旧配置**：重置节点配置
3. **加入集群**：执行 kubeadm join

## kubeadm配置

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

## 验证

```bash
# 查看节点状态
kubectl get nodes

# 查看Pod状态
kubectl get pods -n kube-system

# 查看集群信息
kubectl cluster-info
```

## 注意事项

1. init-master1.sh 只在 master1 上执行
2. join-nodes.sh 在其他节点上执行
3. 需要 root 权限
4. 需要提前配置好 containerd

## 下一步

完成集群初始化后，安装 Calico 网络插件。