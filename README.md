# 运维一键排查脚本集

> 35个Shell脚本，覆盖K8S、中间件、Linux系统、网络协议、内核、部署、告警、日常巡检八大模块
> 对应课程模块：29-K8S故障排查、30-中间件故障排查、31-Linux系统故障排查、32-网络协议深度解析、33-计算机基础与内核、34-部署发布、35-告警处置、36-日常运维

---

## 脚本总览

| 模块 | 脚本数量 | 覆盖场景 |
|------|---------|---------|
| [29-k8s](#29-k8s-k8s故障排查) | 5个 | Pod状态、服务超时、节点健康、Ingress配置 |
| [30-middleware](#30-middleware-中间件故障排查) | 5个 | MySQL、Redis、Elasticsearch、Kafka、Nginx |
| [31-linux](#31-linux-linux系统故障排查) | 5个 | CPU、内存、磁盘IO、进程、启动故障 |
| [32-network](#32-network-网络协议深度解析) | 5个 | TCP连接、TIME_WAIT、网络延迟、TLS、DNS |
| [33-kernel](#33-kernel-内核深度排查) | 5个 | 调度器、缺页中断、PageCache、系统调用、内核健康 |
| [34-deploy](#34-deploy-部署发布) | 5个 | 蓝绿部署、金丝雀、滚动发布、回滚、预检 |
| [35-alert](#35-alert-告警处置) | 4个 | 告警签收、分诊、自动修复、事后分析 |
| [36-daily](#36-daily-日常巡检) | 1个 | 一键日常健康巡检 |

---

## 29-k8s：K8S故障排查

| 脚本 | 功能 | 用法 | 典型场景 |
|------|------|------|---------|
| `check-pod-pending.sh` | 检查Pod Pending状态，分析Pending原因 | `./check-pod-pending.sh [namespace]` | Pod一直处于Pending，无法调度 |
| `check-pod-restart.sh` | 检查Pod频繁重启原因 | `./check-pod-restart.sh [namespace]` | Pod反复CrashLoopBackOff |
| `check-service-timeout.sh` | 检查Service超时和Endpoint状态 | `./check-service-timeout.sh [service-name] [namespace]` | 服务访问超时，连接不上 |
| `check-ingress.sh` | 检查Ingress配置和后端健康 | `./check-ingress.sh [ingress-name] [namespace]` | 域名访问404/502/503 |
| `check-node-health.sh` | 检查K8S节点健康状态 | `./check-node-health.sh` | 节点NotReady，Pod调度失败 |

**排查思路：** Pod状态 → Service连通 → Ingress路由 → 节点资源

---

## 30-middleware：中间件故障排查

| 脚本 | 功能 | 用法 | 典型场景 |
|------|------|------|---------|
| `check-mysql.sh` | MySQL连接超时与慢查询排查 | `./check-mysql.sh [host] [port] [user] [password]` | 连接超时、慢查询、锁等待 |
| `check-redis.sh` | Redis内存溢出与主从切换排查 | `./check-redis.sh [host] [port] [password]` | 内存不足、主从延迟、连接满 |
| `check-elasticsearch.sh` | ES集群状态与分片排查 | `./check-elasticsearch.sh [host] [port]` | 集群变红/黄、分片未分配 |
| `check-kafka.sh` | Kafka消息积压与Broker健康 | `./check-kafka.sh [bootstrap-server]` | 消息消费延迟、Broker宕机 |
| `check-nginx.sh` | Nginx配置与连接状态排查 | `./check-nginx.sh` | 502/504错误、连接数满 |

**排查思路：** 连接层 → 服务端状态 → 存储层 → 集群健康

---

## 31-linux：Linux系统故障排查

| 脚本 | 功能 | 用法 | 典型场景 |
|------|------|------|---------|
| `check-cpu.sh` | CPU性能瓶颈诊断 | `./check-cpu.sh [pid]` | CPU使用率100%、负载过高 |
| `check-memory.sh` | 内存泄漏与OOM排查 | `./check-memory.sh [pid]` | 内存不足、OOM Killer触发 |
| `check-diskio.sh` | 磁盘IO瓶颈分析 | `./check-diskio.sh [device]` | 磁盘IO wait高、读写慢 |
| `check-process.sh` | 僵尸进程与D状态进程排查 | `./check-process.sh` | 僵尸进程累积、进程卡死 |
| `check-boot.sh` | 系统启动故障排查 | `./check-boot.sh` | 开机卡住、服务启动失败 |

**排查思路：** CPU → 内存 → 磁盘 → 进程 → 启动链路

---

## 32-network：网络协议深度排查

| 脚本 | 功能 | 用法 | 典型场景 |
|------|------|------|---------|
| `check-tcp-conn.sh` | TCP连接状态与端口占用排查 | `./check-tcp-conn.sh [port]` | 端口被占、连接数满、SYN Flood |
| `check-time-wait.sh` | TIME_WAIT状态过多排查 | `./check-time-wait.sh` | TIME_WAIT堆积、端口耗尽 |
| `check-network-latency.sh` | 网络延迟与丢包排查 | `./check-network-latency.sh [target-host]` | 网络慢、ping不通、丢包 |
| `check-tls.sh` | TLS/SSL证书与握手排查 | `./check-tls.sh [host] [port]` | 证书过期、TLS握手失败 |
| `check-dns.sh` | DNS解析故障排查 | `./check-dns.sh [domain]` | 域名解析失败、DNS劫持 |

**排查思路：** TCP连接 → 端口状态 → 网络延迟 → TLS握手 → DNS解析

---

## 33-kernel：内核深度排查

| 脚本 | 功能 | 用法 | 典型场景 |
|------|------|------|---------|
| `check-scheduler.sh` | CPU调度器与上下文切换排查 | `./check-scheduler.sh [pid]` | 上下文切换过高、调度延迟 |
| `check-pagefault.sh` | 缺页中断与内存访问分析 | `./check-pagefault.sh [pid]` | 大量Minor/Major Page Fault |
| `check-pagecache.sh` | PageCache缓存命中率分析 | `./check-pagecache.sh` | 缓存命中率低、频繁读磁盘 |
| `check-syscall.sh` | 系统调用频率与性能分析 | `./check-syscall.sh [pid]` | 系统调用过多、性能下降 |
| `check-kernel-health.sh` | 内核整体健康状态检查 | `./check-kernel-health.sh` | 内核日志异常、模块加载失败 |

**排查思路：** 调度器 → 内存访问 → 缓存效率 → 系统调用 → 内核整体

---

## 34-deploy：部署发布

| 脚本 | 功能 | 用法 | 典型场景 |
|------|------|------|---------|
| `deploy-check.sh` | 部署前环境检查（依赖、资源、网络） | `./deploy-check.sh [target]` | 发布前预检、资源不足排查 |
| `deploy-rollout.sh` | 滚动发布脚本（K8S Deployment滚动更新） | `./deploy-rollout.sh [deployment]` | 零停机滚动发布 |
| `deploy-blue-green.sh` | 蓝绿部署脚本（流量切换） | `./deploy-blue-green.sh [service]` | 新旧版本快速切换、零风险回滚 |
| `deploy-canary.sh` | 金丝雀发布脚本（流量灰度） | `./deploy-canary.sh [service]` | 小流量验证、渐进式发布 |
| `deploy-rollback.sh` | 一键回滚脚本 | `./deploy-rollback.sh [deployment]` | 发布失败快速回滚 |

**使用思路：** 部署检查 → 选择策略（滚动/蓝绿/金丝雀） → 发布 → 异常回滚

---

## 35-alert：告警处置

| 脚本 | 功能 | 用法 | 典型场景 |
|------|------|------|---------|
| `alert-ack.sh` | 告警签收与静默管理 | `./alert-ack.sh [alert-id]` | 收到告警后第一时间签收 |
| `alert-triage.sh` | 告警分诊与影响面评估 | `./alert-triage.sh [service]` | 判断告警影响范围、定级 |
| `alert-auto-fix.sh` | 告警自动修复脚本 | `./alert-auto-fix.sh [alert-type]` | 磁盘满、OOM等常见告警自动恢复 |
| `alert-postmortem.sh` | 事后分析与复盘 | `./alert-postmortem.sh [incident-id]` | 故障后数据汇总与改进建议 |

**使用思路：** 告警签收 → 分诊评估 → 自动修复 → 事后复盘

---

## 36-daily：日常巡检

| 脚本 | 功能 | 用法 | 典型场景 |
|------|------|------|---------|
| `daily-check.sh` | 一键日常健康巡检（系统+网络+服务全量检查） | `./daily-check.sh [target]` | 每日一次系统健康体检 |

**检查范围：** 系统状态 → 资源使用 → 服务状态 → 网络连通 → 关键进程 → 日志异常

---

## 使用建议

### 1. 快速定位问题域

```bash
# 不知道问题在哪？按层次排查：
# 第一层：Linux系统层
./31-linux/check-cpu.sh
./31-linux/check-memory.sh

# 第二层：网络层
./32-network/check-network-latency.sh [目标IP]
./32-network/check-dns.sh [域名]

# 第三层：中间件层
./30-middleware/check-mysql.sh 127.0.0.1 3306 root password

# 第四层：K8S层
./29-k8s/check-pod-pending.sh
./29-k8s/check-node-health.sh

# 第五层：部署发布层
./34-deploy/deploy-check.sh
./34-deploy/deploy-rollback.sh [回滚]

# 第六层：告警处置层
./35-alert/alert-ack.sh [告警ID]
./35-alert/alert-auto-fix.sh disk-full

# 第七层：日常巡检
./36-daily/daily-check.sh
```

### 2. 面试时展示

> "我写了35个一键排查脚本，覆盖K8S、中间件、Linux、网络、内核、部署、告警、日常巡检八个层面。遇到问题时，按系统→网络→中间件→K8S的层次排查，每个脚本都有颜色输出，OK是绿色，WARN是黄色，FAIL是红色，一目了然。遇到发布问题我有蓝绿和金丝雀策略，告警可以自动修复，日常可以一键体检。"

### 3. 脚本特点

- **颜色输出**：OK(绿)/WARN(黄)/FAIL(红)/INFO(白)，一眼定位问题
- **参数化**：支持传参，如namespace、host、port等
- **零依赖**：纯Shell实现，不依赖额外工具
- **模块化**：按课程模块组织，学习路径清晰

---

## 目录结构

```
troubleshoot-scripts/
├── README.md                    # 本文件
├── 29-k8s/                      # K8S故障排查（5个脚本）
│   ├── check-pod-pending.sh
│   ├── check-pod-restart.sh
│   ├── check-service-timeout.sh
│   ├── check-ingress.sh
│   └── check-node-health.sh
├── 30-middleware/               # 中间件故障排查（5个脚本）
│   ├── check-mysql.sh
│   ├── check-redis.sh
│   ├── check-elasticsearch.sh
│   ├── check-kafka.sh
│   └── check-nginx.sh
├── 31-linux/                    # Linux系统故障排查（5个脚本）
│   ├── check-cpu.sh
│   ├── check-memory.sh
│   ├── check-diskio.sh
│   ├── check-process.sh
│   └── check-boot.sh
├── 32-network/                  # 网络协议深度排查（5个脚本）
│   ├── check-tcp-conn.sh
│   ├── check-time-wait.sh
│   ├── check-network-latency.sh
│   ├── check-tls.sh
│   └── check-dns.sh
├── 33-kernel/                   # 内核深度排查（5个脚本）
│   ├── check-scheduler.sh
│   ├── check-pagefault.sh
│   ├── check-pagecache.sh
│   ├── check-syscall.sh
│   └── check-kernel-health.sh
├── 34-deploy/                   # 部署发布（5个脚本）
│   ├── deploy-check.sh
│   ├── deploy-rollout.sh
│   ├── deploy-blue-green.sh
│   ├── deploy-canary.sh
│   └── deploy-rollback.sh
├── 35-alert/                    # 告警处置（4个脚本）
│   ├── alert-ack.sh
│   ├── alert-triage.sh
│   ├── alert-auto-fix.sh
│   └── alert-postmortem.sh
└── 36-daily/                    # 日常巡检（1个脚本）
    └── daily-check.sh
```
