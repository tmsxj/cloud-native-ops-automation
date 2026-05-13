### 1.安装helm
```shell
# 配置控制端管理集群
scp root@m1:/etc/kubernetes/admin.conf /root/.kube/config
chmod 600 ~/.kube/config
# 下载最新稳定版 kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
# 赋予执行权限
chmod +x kubectl
# 移动到系统 PATH
sudo mv kubectl /usr/local/bin/
# 验证安装
kubectl version --client
kubectl get nodes
# 下载 Helm v3.14.4（当前主流稳定版）
wget https://get.helm.sh/helm-v3.14.4-linux-amd64.tar.gz
# 解压
tar -zxvf helm-v3.14.4-linux-amd64.tar.gz
# 将 helm 二进制移动到系统路径
sudo mv linux-amd64/helm /usr/local/bin/helm
# 验证安装
helm version
# 验证 Helm 是否能与集群通信
root@showdoc:~# helm list -n kube-system
NAME    NAMESPACE       REVISION        UPDATED STATUS  CHART   APP VERSION
```
### 2.安装监控
```shell
# 添加 Prometheus 社区 Helm 仓库
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
# 查看可用的 Chart 版本，选择一个稳定的
helm search repo prometheus-community/kube-prometheus-stack --versions
helm pull prometheus-community/kube-prometheus-stack --version 45.28.1

root@showdoc:~# scp us:/root/kube-prometheus-stack-45.28.1.tgz ./
kube-prometheus-stack-45.28.1.tgz                              100%  423KB 511.1KB/s   00:00    
root@showdoc:~# ls
ansible-playbooks                image-lists                        linux-amd64
backups                          k8s-hosts.ini                      scripts
helm-v3.14.4-linux-amd64.tar.gz  kube-prometheus-stack-45.28.1.tgz  snap
root@showdoc:~# tar -xzf kube-prometheus-stack-45.28.1.tgz
root@showdoc:~# cd kube-prometheus-stack
root@showdoc:~/kube-prometheus-stack# ls
Chart.lock  charts  Chart.yaml  CONTRIBUTING.md  crds  README.md  templates  values.yaml
```
### 3.存储
K8s 的“云原生”存储方案
针对你的本地集群，我筛选了三个具有代表性的替代品，它们的共同特点是 声明式部署、与 Kubernetes 深度集成，且完全开源免费。
方案	核心特点	优点	缺点	适用场景
Rancher Local Path Provisioner	极简本地存储。在每个节点上自动分配 hostPath 目录作为 PV 。	部署最简单，无需额外存储服务器，真正“零配置”。完全符合你的需求。	无跨节点数据共享，Pod 漂移后数据不跟随。容量无法硬限制。	监控数据 (Prometheus)、临时缓存、单副本测试应用。
OpenEBS	Kubernetes 原生容器附加存储。提供 Local PV (本地) 和 cStor/Mayastor (分布式) 等多种引擎 。	功能丰富，支持快照、克隆、备份。可作为分布式存储（需额外节点）。社区活跃，CNCF 项目。	分布式模式部署稍复杂，需理解其架构。	有状态应用（数据库）、生产级监控、需要数据保护功能的场景。
Longhorn	Kubernetes 内置的分布式块存储。由 Rancher 开发，现为 CNCF 项目 。	企业级功能：内置备份、恢复、增量快照、灾备。提供直观的图形化管理界面。	对系统资源有一定要求（需部署 CSI 驱动和控制器组件）。	生产环境核心数据库、需要企业级数据服务的中大型应用。
```shell
# 在 showdoc 上执行
ssh us "wget -q -O /tmp/local-path-storage.yaml https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.35/deploy/local-path-storage.yaml" && scp us:/tmp/local-path-storage.yaml ./
# 查看文件中的镜像地址
grep image: local-path-storage.yaml | head -1
在 美国服务器 us 上执行以下命令（通过 ssh us 登录）：

# 配置免密登录
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519

参数说明：
-t ed25519：指定密钥类型为 Ed25519（比 RSA 更安全、更短）。
-N ""：设置空密码，实现免密登录。
-f ~/.ssh/id_ed25519：指定密钥保存路径（默认即可）。
执行后会在 ~/.ssh/ 下生成两个文件：
id_ed25519：私钥（必须保管好，不要泄露）
id_ed25519.pub：公钥（需要复制到目标主机）

# 拉取镜像
root@showdoc:~# grep -E '^\s*image:' /root/local-path-storage.yaml
          image: rancher/local-path-provisioner:v0.0.35
        image: busybox

chmod +x ~/scripts/sync_to_harbor_simple.sh
./sync_to_harbor_simple.sh rancher/local-path-provisioner:v0.0.35 3000
# 使用简化脚本同步 busybox
~/scripts/sync_to_harbor_simple.sh busybox:latest 3000
curl -u admin:Harbor12345 -s "http://192.168.1.61/api/v2.0/projects/library/repositories?page_size=100" | jq '.[].name' | grep busybox
root@showdoc:~# cp -p local-path-storage.yaml local-path-storage.yaml.bak

# 替换 provisioner 镜像
sed -i 's|image: rancher/local-path-provisioner:v0.0.35|image: 192.168.1.61/library/rancher_local-path-provisioner:v0.0.35|g' /root/local-path-storage.yaml

# 替换 busybox 镜像（假设使用 latest 标签，可根据实际情况调整）
sed -i 's|image: busybox|image: 192.168.1.61/library/busybox:latest|g' /root/local-path-storage.yaml
```
```shell
root@showdoc:~# kubectl get nodes
NAME      STATUS   ROLES           AGE   VERSION
master1   Ready    control-plane   19d   v1.28.15
master2   Ready    control-plane   19d   v1.28.15
master3   Ready    control-plane   19d   v1.28.15
worker1   Ready    <none>          19d   v1.28.15
worker2   Ready    <none>          19d   v1.28.15
root@showdoc:~# kubectl apply -f /root/local-path-storage.yaml
namespace/local-path-storage created
serviceaccount/local-path-provisioner-service-account created
role.rbac.authorization.k8s.io/local-path-provisioner-role created
clusterrole.rbac.authorization.k8s.io/local-path-provisioner-role created
rolebinding.rbac.authorization.k8s.io/local-path-provisioner-bind created
clusterrolebinding.rbac.authorization.k8s.io/local-path-provisioner-bind created
deployment.apps/local-path-provisioner created
storageclass.storage.k8s.io/local-path created
configmap/local-path-config created
root@showdoc:~# echo $?
0
root@showdoc:~# kubectl -n local-path-storage get pods
NAME                                      READY   STATUS    RESTARTS   AGE
local-path-provisioner-7f4546775c-k6vsr   1/1     Running   0          19s
root@showdoc:~# kubectl get sc
NAME         PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  28s
# 查看当前 ConfigMap
kubectl -n local-path-storage get configmap local-path-config -o yaml
# 将 paths 中的 /opt/local-path-provisioner 改为 /data/local-path-provisioner。修改后保存退出。
kubectl -n local-path-storage edit configmap local-path-config
# 重启 Provisioner 使配置生效
kubectl -n local-path-storage rollout restart deployment local-path-provisioner
# 验证 Pod 是否重新创建
kubectl -n local-path-storage get pods -w
```
### 4.扩容跟分区
```shell
cat > ~/expand-root-lvm.yml <<'EOF'
---
- name: 扩展所有节点的根分区和文件系统（LVM）
  hosts: "master:worker:harbor"
  become: yes
  tasks:
    - name: 安装 growpart 工具（如果未安装）
      apt:
        name: cloud-guest-utils
        state: present
        update_cache: yes
      when: ansible_os_family == "Debian"

    - name: 扩展分区 /dev/sda3
      command: growpart /dev/sda 3
      register: growpart_result
      changed_when: "'CHANGED' in growpart_result.stdout"
      failed_when: growpart_result.rc != 0 and 'NOCHANGE' not in growpart_result.stdout

    - name: 扩展物理卷
      command: pvresize /dev/sda3
      changed_when: false

    - name: 将全部剩余空间分配给根逻辑卷
      command: lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
      changed_when: false

    - name: 扩展文件系统（假设 ext4）
      command: resize2fs /dev/ubuntu-vg/ubuntu-lv
      changed_when: false

    - name: 验证根分区大小
      command: df -h /
      register: df_result
    - debug: var=df_result.stdout_lines
EOF
chmod +x ~/expand-root-lvm.yml
# 1. 检查所有节点的 /dev/sda3 分区是否存在（确认磁盘分区号统一）
ansible master:worker:harbor -i ~/k8s-hosts.ini -m shell -a "lsblk | grep sda3"

# 2. 检查所有节点的 LVM 逻辑卷路径是否一致（应为 /dev/ubuntu-vg/ubuntu-lv）
ansible master:worker:harbor -i ~/k8s-hosts.ini -m shell -a "lvdisplay | grep 'LV Path' | grep ubuntu-lv"

# 3. 检查所有节点的根文件系统类型是否一致（应为 ext4 或 xfs）
ansible master:worker:harbor -i ~/k8s-hosts.ini -m shell -a "df -T / | tail -1 | awk '{print \$2}'"
# 执行剧本
ansible-playbook -i ~/k8s-hosts.ini ~/expand-root-lvm.yml
```
