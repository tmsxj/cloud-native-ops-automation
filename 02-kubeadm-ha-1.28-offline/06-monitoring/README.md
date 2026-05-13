# 06-monitoring - 监控部署

## 功能说明

本目录包含 Prometheus + Grafana 监控系统的部署脚本。

## 脚本清单

| 脚本 | 功能说明 |
|:-----|:---------|
| install-prometheus.sh | Prometheus+Grafana安装脚本 |

## 使用方法

### 在master1上执行

```bash
# 进入目录
cd 06-monitoring

# 添加执行权限
chmod +x install-prometheus.sh

# 执行脚本
./install-prometheus.sh
```

## 脚本功能

`install-prometheus.sh` 脚本完成以下步骤：

1. **添加Helm仓库**：添加 prometheus-community 仓库
2. **创建命名空间**：创建 monitoring 命名空间
3. **安装监控栈**：使用 Helm 安装 kube-prometheus-stack
4. **等待部署**：等待 Pod 启动
5. **验证部署**：检查服务状态

## 部署配置

| 配置项 | 值 | 说明 |
|:-------|:---|:-----|
| Helm Chart | prometheus-community/kube-prometheus-stack | 监控栈Chart |
| 版本 | 45.3.0 | Chart版本 |
| 命名空间 | monitoring | 部署命名空间 |
| Prometheus服务类型 | NodePort | 节点端口访问 |
| Grafana服务类型 | NodePort | 节点端口访问 |
| Grafana密码 | admin123 | 管理员密码 |

## 访问方式

```bash
# 获取Grafana端口
kubectl get svc -n monitoring prometheus-grafana -o jsonpath='{.spec.ports[0].nodePort}'

# 访问地址
http://192.168.1.51:<GRAFANA_PORT>
用户名: admin
密码: admin123
```

## 已部署组件

| 组件 | 说明 |
|:-----|:-----|
| Prometheus | 指标收集和存储 |
| Grafana | 可视化面板 |
| Alertmanager | 告警管理 |
| Node Exporter | 节点指标采集 |
| kube-state-metrics | Kubernetes状态指标 |

## 验证

```bash
# 查看监控Pod状态
kubectl get pods -n monitoring

# 查看监控服务
kubectl get svc -n monitoring
```

## 注意事项

1. 需要 Helm 3 版本
2. 需要足够的资源（建议每个节点至少 2GB 内存）
3. 部署时间可能较长（需要拉取多个镜像）

## 下一步

完成监控部署后，部署日志系统。