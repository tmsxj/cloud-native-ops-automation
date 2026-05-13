```shell
# ============================================
# Argo CD 部署完整步骤（适用于当前集群）
# ============================================

# 1. 创建命名空间
kubectl create namespace argocd

# 2. 创建 TLS 证书 Secret（使用已有的证书文件）
# 生成一个有效期 365 天的自签名证书和对应的私钥
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout argocd-tls.key \
  -out argocd-tls.crt \
  -subj "/CN=argocd.test"

# 查看生成的文件
ls -l argocd-tls.*

kubectl create secret tls argocd-tls --cert=argocd-tls.crt --key=argocd-tls.key -n argocd

# 3. 部署 Argo CD（使用修改过的清单，镜像指向 Harbor）
kubectl apply -n argocd -f argocd-install.yaml

# 4. 等待所有 Pod 运行
kubectl get pods -n argocd -w

# 5. 获取 admin 初始密码
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

# 6. 修改 argocd-server 启动参数，添加 --insecure 禁用 HTTPS 重定向
kubectl patch deployment argocd-server -n argocd --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/command", "value": ["argocd-server", "--insecure"]}]'

# 7. 创建 Ingress（使用 TLS 版本）
kubectl apply -f argocd-install-ingress-tls.yaml

# 8. 获取 Ingress Controller 的 HTTPS NodePort
HTTPS_PORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
echo $HTTPS_PORT   # 通常为 32475

# 9. 测试 HTTPS 访问（本地需添加 hosts: 192.168.1.51 argocd.test）
curl -k -H "Host: argocd.test" https://192.168.1.51:${HTTPS_PORT}

# 10. 浏览器访问
# 地址: https://argocd.test:32475
# 用户名: admin
# 密码: 步骤5获取的密码

# argocd-server重启电脑后的修复
# 1. 删除现有的 command 和 args
kubectl patch deployment argocd-server -n argocd --type='json' -p='[{"op": "remove", "path": "/spec/template/spec/containers/0/command"}]' 2>/dev/null
kubectl patch deployment argocd-server -n argocd --type='json' -p='[{"op": "remove", "path": "/spec/template/spec/containers/0/args"}]' 2>/dev/null

# 2. 添加正确的 command（直接指定可执行文件和参数）
kubectl patch deployment argocd-server -n argocd --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/command", "value": ["argocd-server", "--insecure"]}]'

# 3. 删除 Pod 触发重建
kubectl delete pods -n argocd -l app.kubernetes.io/name=argocd-server
```

```shell
sudo apt update
sudo apt install -y etcd-client etcd-server

# 1. 设置版本号
ETCD_VER=v3.5.28

# 2. 下载并解压
DOWNLOAD_URL=https://github.com/etcd-io/etcd/releases/download
curl -fsSL ${DOWNLOAD_URL}/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
tar xzf /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz -C /tmp/

# 3. 将二进制文件移至系统路径
sudo mv /tmp/etcd-${ETCD_VER}-linux-amd64/etcd /usr/local/bin/
sudo mv /tmp/etcd-${ETCD_VER}-linux-amd64/etcdctl /usr/local/bin/
sudo mv /tmp/etcd-${ETCD_VER}-linux-amd64/etcdutl /usr/local/bin/

# 4. 验证安装
etcd --version
etcdctl --version

export ETCDCTL_API=3
export ETCDCTL_ENDPOINTS=https://127.0.0.1:2379
export ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt
export ETCDCTL_CERT=/etc/kubernetes/pki/etcd/server.crt
export ETCDCTL_KEY=/etc/kubernetes/pki/etcd/server.key

查看集群健康状态：etcdctl endpoint health
列出所有键：etcdctl get / --prefix --keys-only

cat > /root/backup-k8s.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backup/k8s"
mkdir -p "$BACKUP_DIR"
DATE=$(date +%Y%m%d_%H%M%S)

# 设置 etcdctl 使用 API v3
export ETCDCTL_API=3
export ETCDCTL_ENDPOINTS=https://127.0.0.1:2379
export ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt
export ETCDCTL_CERT=/etc/kubernetes/pki/etcd/server.crt
export ETCDCTL_KEY=/etc/kubernetes/pki/etcd/server.key

echo "开始备份 etcd 快照..."
etcdctl snapshot save "$BACKUP_DIR/etcd-snapshot-$DATE.db"
if [ $? -eq 0 ]; then
    echo "✓ etcd 快照备份成功: $BACKUP_DIR/etcd-snapshot-$DATE.db"
else
    echo "✗ etcd 快照备份失败"
fi

echo "备份 kubeconfig..."
cp /root/.kube/config "$BACKUP_DIR/kube-config-$DATE.yaml" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✓ kubeconfig 备份成功"
else
    echo "✗ kubeconfig 备份失败"
fi
EOF

chmod +x /root/backup-k8s.sh

ls -lh /backup/k8s/etcd-snapshot-*.db
export ETCDCTL_API=3
etcdctl snapshot status /backup/k8s/etcd-snapshot-20260414_152404.db
# 验证输出
22e1f3c2, 28765, 4150, 22 MB

# 同步到控制端
scp m1:/backup/k8s/etcd-snapshot-*.db ./backups/
scp m1:/backup/k8s/kube-config-*.yaml ./backups/

crontab -e
# 添加一行，每天凌晨 2 点执行
0 2 * * * /root/backup-k8s.sh >> /var/log/k8s-backup.log 2>&1

# 1. 停止 kubelet（防止 etcd 被自动重启）
systemctl stop kubelet

# 2. 备份当前损坏的数据目录（可选）
mv /data/etcd/member /data/etcd/member.bak

# 3. 恢复快照
etcdctl snapshot restore /backup/k8s/etcd-snapshot-20260408_162544.db \
  --data-dir /data/etcd \
  --name master1 \
  --initial-cluster master1=https://192.168.1.51:2380 \
  --initial-cluster-token etcd-cluster-1 \
  --initial-advertise-peer-urls https://192.168.1.51:2380

# 4. 修正权限（如果 etcd 用户存在，否则跳过）
chown -R etcd:etcd /data/etcd 2>/dev/null

# 5. 启动 kubelet
systemctl start kubelet

# 6. 等待 etcd 和 apiserver 启动（约 10-20 秒）
sleep 20

# 7. 验证集群状态
# ============================================
# 1. 节点状态
kubectl get nodes -o wide

# 2. 系统核心 Pod
kubectl get pods -n kube-system -o wide

# 3. Argo CD 组件
kubectl get pods -n argocd

# 4. 监控组件 (Prometheus + Grafana)
kubectl get pods -n monitoring

# 5. 日志组件 (ELK)
kubectl get pods -n logging

# 6. Ingress Controller
kubectl get pods -n ingress-nginx

# 7. 本地存储
kubectl get pods -n local-path-storage

# 8. 电商 Demo (default 命名空间)
kubectl get pods -n default

# 9. 所有非 Running/Completed 的 Pod（快速定位异常）
kubectl get pods --all-namespaces | grep -v -E "Running|Completed"

# ============================================
# 10. 查看节点资源使用（需要 metrics-server，若未安装可跳过）
kubectl top nodes

# 11. 查看各命名空间 Pod 资源使用（需要 metrics-server）
kubectl top pods --all-namespaces

# ============================================
# 修复不稳定的 applicationset-controller（非核心组件，可安全关闭）
kubectl scale deployment argocd-applicationset-controller -n argocd --replicas=0
kubectl scale deployment loadgenerator -n default --replicas=0

```
```shell
ansible -i k8s-hosts.ini master,worker -m shell -a "cat >> /var/lib/kubelet/config.yaml <<EOF
shutdownGracePeriod: 30s
shutdownGracePeriodCriticalPods: 10s
EOF"

ansible -i k8s-hosts.ini master,worker -m shell -a "sed -i '/shutdownGracePeriod: 0s/d' /var/lib/kubelet/config.yaml"
ansible -i k8s-hosts.ini master,worker -m shell -a "sed -i '/shutdownGracePeriodCriticalPods: 0s/d' /var/lib/kubelet/config.yaml"

ansible -i k8s-hosts.ini master,worker -m shell -a "grep -i 'shutdownGracePeriod' /var/lib/kubelet/config.yaml"

ansible -i k8s-hosts.ini master,worker -m shell -a "systemctl restart kubelet"

ansible -i k8s-hosts.ini master,worker -m shell -a "systemctl status kubelet --no-pager | grep -E 'Active|shutdownGracePeriod'"

ansible -i k8s-hosts.ini master -m shell -a "mount | grep '/data'"

ansible -i k8s-hosts.ini master -m shell -a "cp /etc/fstab /etc/fstab.bak.$(date +%Y%m%d)"

ansible -i k8s-hosts.ini master -m shell -a "grep '/data' /etc/fstab"

ansible -i k8s-hosts.ini master -m shell -a "sed -i 's|defaults|defaults,barrier=1|' /etc/fstab"

ansible -i k8s-hosts.ini master -m shell -a "grep '/data' /etc/fstab"

ansible -i k8s-hosts.ini master -m shell -a "mount -o remount /data"

ansible -i k8s-hosts.ini master -m shell -a "mount | grep '/data'"

ansible -i k8s-hosts.ini all -m shell -a "systemctl is-active chrony || systemctl is-active ntp"

```
