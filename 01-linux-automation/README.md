# 01-linux-automation

> Linux 系统初始化、健康检查、故障排查、日常运维脚本集

## 目录结构

```
01-linux-automation/
├── README.md                    # 本文件
├── init.sh                      # 系统初始化脚本
├── health-check.sh              # 系统健康检查
├── disk-clean.sh                # 磁盘清理脚本
├── network-troubleshoot.sh      # 网络故障排查
└── troubleshooting/             # 故障排查脚本集
    ├── README.md                 # 故障排查脚本说明
    ├── network-bandwidth-check.sh
    ├── network-packet-loss-check.sh
    ├── network-connection-check.sh
    ├── disk-full-check.sh
    ├── disk-io-check.sh
    ├── disk-log-cleanup.sh
    └── system-resource-check.sh
```

---

## 快速开始

```bash
# 进入目录
cd 01-linux-automation

# 添加执行权限
chmod +x *.sh

# 运行脚本
sudo ./init.sh                  # 系统初始化
sudo ./health-check.sh          # 健康检查
sudo ./disk-clean.sh            # 磁盘清理
sudo ./network-troubleshoot.sh  # 网络排查
```

---

## 脚本说明

### 1. init.sh - 系统初始化脚本

**功能**：新服务器部署后进行基础配置

**主要功能**：
- 配置主机名
- 配置时区
- 更新系统软件
- 安装常用工具
- 配置 SSH（禁用密码登录、修改端口）
- 配置防火墙
- 创建普通用户
- 优化内核参数
- 配置时间同步

**使用方法**：
```bash
sudo ./init.sh
```

---

### 2. health-check.sh - 系统健康检查脚本

**功能**：定期检查系统状态、快速定位问题

**检查内容**：
- 系统基本信息（主机名、OS、内核版本）
- CPU 状态（核心数、使用率）
- 内存状态（总量、使用、空闲）
- 磁盘状态（各分区使用情况）
- 网络状态（IP、网关、DNS）
- 服务状态（关键服务运行情况）
- 安全状态（SSH 配置、最近登录）
- 进程状态（总进程数、僵尸进程）
- 系统更新状态

**使用方法**：
```bash
sudo ./health-check.sh
```

---

### 3. disk-clean.sh - 磁盘空间清理脚本

**功能**：磁盘空间不足时进行快速清理

**清理内容**：
- 系统日志（保留最近30天）
- 包管理器缓存（apt/yum/dnf）
- 临时文件（超过7天）
- 用户缓存
- 已删除但仍被占用的文件
- Docker 资源（如安装）
- 旧内核

**使用方法**：
```bash
sudo ./disk-clean.sh
```

---

### 4. network-troubleshoot.sh - 网络故障排查脚本

**功能**：网络连接问题、无法访问服务、延迟高等问题排查

**检查内容**：
- 网络接口状态
- 路由表
- DNS 配置
- 网络连接状态
- 网络连通性测试
- 防火墙规则
- 网络服务状态
- 网络性能测试
- 网络错误日志

**使用方法**：
```bash
sudo ./network-troubleshoot.sh
```

---

## 故障排查脚本集

[troubleshooting/](troubleshooting/) 目录包含 7 个专业故障排查脚本：

| 脚本名称 | 功能说明 |
|:---------|:---------|
| network-bandwidth-check.sh | 带宽打满排查 |
| network-packet-loss-check.sh | 丢包/TCP重传排查 |
| network-connection-check.sh | 连接数耗尽排查 |
| disk-full-check.sh | 磁盘空间被写满排查 |
| disk-io-check.sh | 磁盘I/O高排查 |
| disk-log-cleanup.sh | 日志快速增长处理 |
| system-resource-check.sh | CPU高/内存高/僵尸进程综合排查 |

详细说明请参考 [troubleshooting/README.md](troubleshooting/README.md)

---

## 许可证

MIT License