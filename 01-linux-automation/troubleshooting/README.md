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
└── troubleshooting/             # 故障排查脚本集 (新增)
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

## 故障排查脚本集

> 针对 Linux 常见故障场景的自动化排查工具，基于实际运维经验总结

### 📋 脚本清单

| 脚本名称 | 对应案例 | 功能说明 |
|:---------|:---------|:---------|
| [network-bandwidth-check.sh](./troubleshooting/network-bandwidth-check.sh) | 网络-案例1 | 排查带宽被打满导致的网络故障 |
| [network-packet-loss-check.sh](./troubleshooting/network-packet-loss-check.sh) | 网络-案例2 | 排查丢包和 TCP 重传问题 |
| [network-connection-check.sh](./troubleshooting/network-connection-check.sh) | 网络-案例3 | 排查连接数耗尽问题 |
| [disk-full-check.sh](./troubleshooting/disk-full-check.sh) | 磁盘-案例1 | 排查磁盘空间被写满 |
| [disk-io-check.sh](./troubleshooting/disk-io-check.sh) | 磁盘-案例2 | 排查磁盘 I/O 性能问题 |
| [disk-log-cleanup.sh](./troubleshooting/disk-log-cleanup.sh) | 磁盘-案例3 | 处理日志文件快速增长 |
| [system-resource-check.sh](./troubleshooting/system-resource-check.sh) | CPU/内存 | 综合排查 CPU 高、内存高、僵尸进程 |

---

### 一、网络故障排查脚本

#### 1. network-bandwidth-check.sh - 带宽打满排查

**功能说明**
自动检测服务器网络带宽是否被占满，定位占用带宽的进程和来源 IP。

**适用场景**
- 服务器访问变慢
- SSH 连接困难
- 网络服务响应延迟
- 带宽使用率接近上限

**使用方法**
```bash
# 添加执行权限
chmod +x network-bandwidth-check.sh

# 运行脚本（需要 root 权限）
sudo ./network-bandwidth-check.sh
```

**排查内容**
| 检查项 | 命令 | 说明 |
|:-------|:-----|:-----|
| 网卡流量 | ifstat / sar -n DEV | 实时监控带宽使用 |
| 进程带宽 | nethogs | 按进程显示网络流量 |
| 连接状态 | ss -s | 统计各状态连接数 |
| 流量来源 | iftop / netstat | 定位占用带宽的 IP |
| SYN Flood | netstat -an | 检查半开连接数 |
| 网卡协商 | ethtool eth0 | 检查网卡速率和双工模式 |

**输出示例**
```
[1] 网卡流量实时监控 (观察5秒)
eth0:  RX: 45.2MB/s    TX: 12.8MB/s

[2] 按进程查看网络流量
  PID   USER     PROGRAM           DEV    SENT      RECEIVED
 1234   nginx    nginx: worker     eth0   15.6MB    0.0KB
```

---

#### 2. network-packet-loss-check.sh - 丢包/TCP重传排查

**功能说明**
排查网络丢包和 TCP 重传问题，定位丢包发生在网络哪个层级。

**适用场景**
- 网络延迟高
- 传输速度慢
- 连接不稳定
- 数据传输丢包

**使用方法**
```bash
chmod +x network-packet-loss-check.sh
sudo ./network-packet-loss-check.sh
```

**排查内容**
| 检查项 | 命令 | 说明 |
|:-------|:-----|:-----|
| 网卡丢包 | ip -s link show | 查看 RX/TX 丢包和错误 |
| TCP 统计 | netstat -s | TCP 重传、丢失统计 |
| Ping 测试 | ping -c 20 | ICMP 丢包率测试 |
| 路由跳点 | mtr / traceroute | 定位问题节点 |
| 连接队列 | ss -ltn | 检查监听队列溢出 |
| 缓冲区 | ethtool -g | 检查 Ring Buffer |
| 软中断 | cat /proc/softirqs | 检查 CPU 中断负载 |

**输出示例**
```
[1] 网卡丢包和错误统计
>>> eth0
  接收(RX) - 丢包: 0, 错误: 0
  发送(TX) - 丢包: 152, 错误: 0
⚠ 发现丢包！需要进一步排查

[4] ICMP Ping 丢包率测试
>>> 测试到网关: 192.168.1.1
20 packets transmitted, 20 received, 0% packet loss, time 3800ms
```

---

#### 3. network-connection-check.sh - 连接数耗尽排查

**功能说明**
分析各类网络连接状态，排查连接数耗尽导致的故障。

**适用场景**
- 新建连接失败
- 连接被拒绝
- 服务响应缓慢
- TIME_WAIT 堆积

**使用方法**
```bash
chmod +x network-connection-check.sh
sudo ./network-connection-check.sh
```

**排查内容**
| 检查项 | 命令 | 说明 |
|:-------|:-----|:-----|
| 连接统计 | ss -s | 汇总各状态连接数 |
| TIME_WAIT | ss -ant state time-wait | TIME_WAIT 过多分析 |
| CLOSE_WAIT | ss -ant state close-wait | 连接泄漏检测 |
| SYN_RECV | ss -ant state syn-recv | SYN Flood 检测 |
| 端口范围 | cat /proc/sys/net/ipv4/ip_local_port_range | 客户端端口耗尽 |
| 连接追踪 | cat /proc/net/nf_conntrack | nf_conntrack 耗尽检测 |
| 进程连接 | ss -tnp | 按进程统计连接数 |

**输出示例**
```
[3] TIME_WAIT 连接分析
TIME_WAIT 连接数: 15234
⚠ TIME_WAIT连接数过高，可能导致端口耗尽

[6] SYN_RECV (半开连接) 分析
SYN_RECV 连接数: 5234
⚠ 警告：SYN_RECV连接数极高，可能正在遭受SYN Flood攻击！
```

---

### 二、磁盘故障排查脚本

#### 4. disk-full-check.sh - 磁盘被写满排查

**功能说明**
全面分析磁盘空间占用情况，快速定位占用空间最多的目录和文件。

**适用场景**
- 磁盘空间不足
- 无法写入文件
- 服务启动失败
- /var/log 目录过大

**使用方法**
```bash
chmod +x disk-full-check.sh
sudo ./disk-full-check.sh
```

**排查内容**
| 检查项 | 命令 | 说明 |
|:-------|:-----|:-----|
| 分区使用 | df -h | 各分区空间使用率 |
| Inode 使用 | df -i | 小文件过多导致 inode 耗尽 |
| 大目录 | du -sh /* | 按目录大小排序 |
| 大文件 | find -size +100M | 查找超过100MB的文件 |
| 日志目录 | du -sh /var/log/* | 日志占用分析 |
| Docker 空间 | docker system df | Docker 镜像/容器占用 |
| 已删占用 | lsof +L1 | 已删除但被占用的文件 |

**输出示例**
```
[1] 所有分区空间使用概览
文件系统        容量  已用  可用  已用% 挂载点
/dev/sda1      100G   95G   5G    95%   /

⚠ 使用率超过 90% 的分区:
  ⚠ /: 95%

[4] 查找大文件 (超过100MB)
124M  /var/log/nginx/access.log
512M  /var/log/mysql/slow-query.log
1.2G  /var/log/syslog
```

---

#### 5. disk-io-check.sh - 磁盘I/O高排查

**功能说明**
分析磁盘 I/O 性能瓶颈，定位导致 I/O 高的进程和原因。

**适用场景**
- 服务器卡顿
- 读写速度慢
- 响应延迟高
- 磁盘使用率 100%

**使用方法**
```bash
chmod +x disk-io-check.sh
sudo ./disk-io-check.sh
```

**排查内容**
| 检查项 | 命令 | 说明 |
|:-------|:-----|:-----|
| 实时 I/O | iostat -x | 设备使用率和队列深度 |
| I/O 等待 | vmstat / iostat | CPU 等待 I/O 时间 |
| 进程 I/O | iotop -aoP | 按进程显示 I/O |
| 磁盘健康 | smartctl -a | SSD/HDD 健康状态 |
| 碎片程度 | filefrag | 文件系统碎片检查 |
| 调度器 | cat /sys/block/sda/queue/scheduler | I/O 调度算法 |
| 阻塞进程 | ps aux | 等待 I/O 的 D 状态进程 |

**输出示例**
```
[2] I/O等待时间分析
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 4  1      0   512M   128M   2.5G    0    0   150    80   200  400  5 10 70 15  0

⚠ CPU 等待 I/O 时间 (wa) 达到 15%，存在 I/O 瓶颈
```

---

#### 6. disk-log-cleanup.sh - 日志快速增长处理

**功能说明**
智能清理日志文件，释放磁盘空间，支持模拟运行和自定义保留策略。

**适用场景**
- 日志文件占用大量空间
- 需要清理历史日志
- 磁盘空间告警
- 定期维护

**使用方法**
```bash
# 模拟运行（只显示将要删除的文件）
chmod +x disk-log-cleanup.sh
sudo ./disk-log-cleanup.sh --dry-run

# 执行清理（保留最近7天）
sudo ./disk-log-cleanup.sh

# 保留最近14天的日志
sudo ./disk-log-cleanup.sh --keep-days 14
```

**功能特性**
| 功能 | 说明 |
|:-----|:-----|
| 模拟运行 | `--dry-run` 参数预览清理效果 |
| 保留策略 | `--keep-days` 自定义保留天数 |
| 日志统计 | 分析各服务的日志占用 |
| 安全删除 | 自动跳过正在使用的文件 |
| logrotate | 自动生成推荐配置 |

**输出示例**
```
⚠ 模拟运行模式 - 不会实际删除任何文件

[3] 可清理日志分析
1) 超过 7 天的 .log 文件:
  数量: 23 个
  总大小: 1.2 GB

可清理日志统计:
  文件数量: 45
  总大小: 2.5 GB
  清理后 /var/log 目录大小约: 预计减少 2.5 GB
```

---

### 三、系统资源故障排查脚本

#### 7. system-resource-check.sh - CPU高/内存高/僵尸进程排查

**功能说明**
综合排查系统资源问题，包括 CPU 高负载、内存不足、僵尸进程等。

**适用场景**
- 系统负载高
- 响应缓慢
- OOM 频繁
- 进程异常
- 僵尸进程

**使用方法**
```bash
chmod +x system-resource-check.sh
sudo ./system-resource-check.sh
```

**排查内容**

**CPU 资源**
| 检查项 | 命令 | 说明 |
|:-------|:-----|:-----|
| 使用率 | top / vmstat | CPU 总体使用情况 |
| 高负载进程 | ps aux --sort=-%cpu | CPU 占用最高的进程 |
| 多核使用 | mpstat -P ALL | 各 CPU 核心使用率 |
| 负载分析 | uptime / w | 1/5/15 分钟负载 |

**内存资源**
| 检查项 | 命令 | 说明 |
|:-------|:-----|:-----|
| 使用概览 | free -h | 内存总量和使用情况 |
| 高内存进程 | ps aux --sort=-%mem | 内存占用最高的进程 |
| Swap 分析 | vmstat / free | Swap 使用和交换活动 |
| OOM 日志 | dmesg | 检查 OOM Killer 记录 |

**进程状态**
| 检查项 | 命令 | 说明 |
|:-------|:-----|:-----|
| 僵尸进程 | ps aux | 查找 Z 状态的进程 |
| 阻塞进程 | ps aux | 查找 D 状态的进程 |
| 线程统计 | /proc/*/status | 各进程线程数 |
| 文件描述符 | /proc/sys/fs/file-nr | FD 使用情况 |

**输出示例**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  第一部分：CPU 资源排查
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[CPU-2] CPU 占用最高的进程
USER       PID %CPU %MEM     COMMAND
root      1234 98.5  2.1   python3 app.py
nginx     5678 45.2  1.5   nginx: worker

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  第二部分：内存资源排查
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[MEM-1] 内存使用概览
              total        used        free      shared  buff/cache   available
Mem:           31Gi       28Gi       1.2Gi       200Mi       1.8Gi       2.5Gi
Swap:         8.0Gi       3.2Gi       4.8Gi

⚠ 警告：内存使用率超过90%，可能触发OOM

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  第三部分：进程状态排查
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[PROC-1] 僵尸进程检查
僵尸进程数量: 3
⚠ 发现 3 个僵尸进程！

僵尸进程详情:
USER       PID %CPU %MEM STAT COMMAND
root      9999  0.0  0.0 Z   <defunct>
```

---

## 快速使用指南

### 推荐排查顺序

```
1. 系统响应慢？
   → system-resource-check.sh（先看整体）

2. 网络连接问题？
   → network-connection-check.sh（检查连接数）
   → network-bandwidth-check.sh（检查带宽）
   → network-packet-loss-check.sh（检查丢包）

3. 磁盘空间不足？
   → disk-full-check.sh（定位占用）
   → disk-log-cleanup.sh（清理日志）

4. I/O 性能差？
   → disk-io-check.sh（分析 I/O）
```

### 常用命令速查

```bash
# 安装依赖工具
apt update && apt install -y net-tools iproute2 sysstat smartmontools lsof

# 快速健康检查
./system-resource-check.sh

# 网络故障快速定位
ss -s                          # 连接统计
netstat -tuln                  # 监听端口
netstat -an | grep ESTABLISHED # 活跃连接

# 磁盘问题快速定位
df -h                          # 空间使用
du -sh /* | sort -rh | head   # 大目录
lsof +L1                       # 已删除但占用

# 进程快速定位
ps aux --sort=-%cpu | head     # CPU 高
ps aux --sort=-%mem | head     # 内存高
ps aux | grep Z                # 僵尸进程
```

---

## 故障排查最佳实践

### 1. 排查前准备

```bash
# 记录问题发生时间
date

# 保存初步信息
top -bn1 > /tmp/top.txt
free -h > /tmp/mem.txt
df -h > /tmp/disk.txt
ss -s > /tmp/network.txt
```

### 2. 常见阈值参考

| 指标 | 正常 | 警告 | 严重 |
|:-----|:-----|:-----|:-----|
| CPU 使用率 | < 70% | 70-90% | > 90% |
| 内存使用率 | < 80% | 80-90% | > 90% |
| 磁盘使用率 | < 80% | 80-90% | > 90% |
| 负载/核心数 | < 0.7 | 0.7-1.0 | > 1.0 |
| TIME_WAIT | < 1000 | 1000-10000 | > 10000 |
| %iowait | < 10% | 10-30% | > 30% |

### 3. 紧急处理流程

```
1. 确定影响范围
   - 全部服务还是部分服务？
   - 哪些用户/请求受影响？

2. 快速止血
   - 流量异常 → 限制来源IP
   - 资源耗尽 → 重启相关服务
   - 连接攻击 → 启用防护规则

3. 定位根因
   - 查看日志
   - 分析资源使用
   - 复现问题

4. 彻底解决
   - 修复配置
   - 优化代码
   - 升级资源
```

---

## 脚本维护

### 贡献指南

欢迎提交新的故障排查脚本或改进现有脚本：

1. 每个脚本需要包含完整的注释说明
2. 使用统一的颜色输出格式
3. 提供清晰的错误诊断和建议
4. 测试通过后再提交 PR

### 版本历史

| 版本 | 日期 | 更新内容 |
|:-----|:-----|:---------|
| 1.0.0 | 2026-05-13 | 初始版本，包含7个故障排查脚本 |

---

## 许可证

与主仓库一致，采用 MIT 许可证。