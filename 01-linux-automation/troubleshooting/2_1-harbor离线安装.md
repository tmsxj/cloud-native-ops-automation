### 1.离线安装
```shell
# 更新软件包索引
sudo apt update

# 安装依赖包，允许 apt 通过 HTTPS 使用仓库
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common

# 添加 Docker 官方 GPG 密钥
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# 添加 Docker 稳定版仓库
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 再次更新索引并安装 Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# 启动 Docker 并设置开机自启
sudo systemctl start docker
sudo systemctl enable docker

# 将当前用户加入 docker 组（可选，避免每次 sudo）
sudo usermod -aG docker $USER
# 退出重新登录使组生效，或执行 newgrp docker 临时切换
mkdir /data/harbor
wget -c --progress=bar https://github.com/goharbor/harbor/releases/download/v2.9.0/harbor-offline-installer-v2.9.0.tgz
-C 断点续传
--progress=bar 显示实时进度条
tar xzvf harbor-offline-installer-v2.9.0.tgz -C /data/harbor --strip-components=1
说明：
xzvf：解压、显示详细信息。
-C /data/harbor：解压到指定目录。
--strip-components=1：去掉压缩包顶层目录，直接释放文件到当前目录。
sed -e 's/#.*//' -e '/^[[:space:]]*$/d' harbor.yml.tmpl
查看去注释去空行的配置文件
sed -e 's/#.*//' -e '/^[[:space:]]*$/d' harbor.yml.tmpl > harbor.yml
写入到文件
echo "alias clean='sed -e \"s/#.*//\" -e \"/^[[:space:]]*$/d\"'" >> ~/.bashrc
存为别名
source ~/.bashrc
clean harbor.yml.tmpl > harbor.yml
```
### 2.配置文件
```shell
root@harbor:/data/harbor# cat harbor.yml
# Harbor 配置文件（已过滤注释和空行，并添加中文说明）

# 访问地址，可以是 IP 或域名（这里设为 Harbor 虚拟机的内网 IP）
hostname: 192.168.1.61

# HTTP 协议配置（使用 80 端口）
http:
  port: 80

# 管理员初始密码（登录后请立即修改）
harbor_admin_password: Harbor12345

# 数据库连接密码（Harbor 内部使用，保持默认即可）
database:
  password: root123
  # 数据库连接池最大空闲连接数
  max_idle_conns: 100
  # 数据库最大打开连接数
  max_open_conns: 900
  # 连接最长生命周期
  conn_max_lifetime: 5m
  # 连接最大空闲时间
  conn_max_idle_time: 0

# 镜像存储的数据卷路径（所有镜像数据存放于此）
data_volume: /data

# Trivy 漏洞扫描器配置
trivy:
  # 是否只扫描未修复的漏洞
  ignore_unfixed: false
  # 是否跳过更新漏洞数据库
  skip_update: false
  # 是否使用离线扫描（不更新数据库）
  offline_scan: false
  # 扫描的安全检查类型（vuln 表示漏洞）
  security_check: vuln
  # 是否允许不安全连接（设为 true 可跳过 TLS 验证）
  insecure: false

# 任务服务配置（用于复制、扫描等后台任务）
jobservice:
  # 最大并发任务数
  max_job_workers: 10
  # 任务日志输出方式（STD_OUTPUT 控制台，FILE 文件）
  job_loggers:
    - STD_OUTPUT
    - FILE
  # 日志清理间隔（单位：天）
  logger_sweeper_duration: 1

# 通知配置（如 Webhook）
notification:
  # Webhook 任务最大重试次数
  webhook_job_max_retry: 3
  # Webhook HTTP 客户端超时时间（秒）
  webhook_job_http_client_timeout: 3

# 日志配置
log:
  # 日志级别（info、debug、warning、error 等）
  level: info
  # 本地日志文件配置
  local:
    # 日志文件保留数量
    rotate_count: 50
    # 单个日志文件最大大小
    rotate_size: 200M
    # 日志文件存放目录
    location: /var/log/harbor

# 配置文件版本（应与安装包版本一致）
_version: 2.9.0

# 代理配置（用于访问外部资源，如漏洞数据库）
proxy:
  # HTTP 代理地址（留空表示不使用）
  http_proxy:
  # HTTPS 代理地址（留空表示不使用）
  https_proxy:
  # 不走代理的地址列表（留空表示无）
  no_proxy:
  # 需要使用代理的组件列表
  components:
    - core
    - jobservice
    - trivy

# 上传文件清理策略（用于清理不再被引用的 Blob）
upload_purging:
  # 是否启用自动清理
  enabled: true
  # 清理的 Blob 最小年龄（超过此时间未引用的 Blob 将被清理）
  age: 168h
  # 清理任务执行间隔
  interval: 24h
  # 是否为试运行模式（true 只记录不实际删除）
  dryrun: false

# 缓存配置（用于加速 API 响应）
cache:
  # 是否启用缓存
  enabled: false
  # 缓存过期时间（小时）
  expire_hours: 24
root@harbor:/data/harbor#
```
### 3.启动方式
```shell
# 初始化安装
./install.sh
# 查看容器状态
docker compose ps
# 本地访问测试
curl http://127.0.0.1:80
# 浏览器访问
# http://192.168.1.61
cd /data/harbor
docker compose up -d      # 启动
docker compose down       # 停止并删除容器（数据卷保留）
docker compose restart    # 重启所有容器
docker compose stop       # 停止容器（保留容器）
# 修改配置文件后
docker compose down
./prepare
docker compose up -d
# 登录
root@harbor:/data/harbor# docker login 192.168.1.61 -u admin -p Harbor12345
WARNING! Using --password via the CLI is insecure. Use --password-stdin.
Login Succeeded
sudo apt install jq -y

```