# 08-demo - 演示应用部署

## 功能说明

本目录包含 OpenTelemetry Astronomy Shop Demo 的部署脚本。

## 脚本清单

| 脚本 | 功能说明 |
|:-----|:---------|
| install-demo.sh | OpenTelemetry Demo安装脚本 |

## 使用方法

### 在master1上执行

```bash
# 进入目录
cd 08-demo

# 添加执行权限
chmod +x install-demo.sh

# 执行脚本
./install-demo.sh
```

## 脚本功能

`install-demo.sh` 脚本完成以下步骤：

1. **添加Helm仓库**：添加 open-telemetry 仓库
2. **创建命名空间**：创建 demo 命名空间
3. **部署演示应用**：使用 Helm 安装 opentelemetry-demo
4. **等待部署**：等待 Pod 启动
5. **配置Ingress**：创建 frontend Ingress

## 部署配置

| 配置项 | 值 | 说明 |
|:-------|:---|:-----|
| Helm Chart | open-telemetry/opentelemetry-demo | Demo Chart |
| 版本 | 0.40.0 | Chart版本 |
| 命名空间 | demo | 部署命名空间 |

## 访问方式

```bash
# 配置本地hosts
echo "192.168.1.51 shop.example.com" >> /etc/hosts

# 访问地址
http://shop.example.com
```

## 已部署组件

| 组件 | 说明 |
|:-----|:-----|
| frontend | 前端服务 |
| 后端微服务 | 多个微服务组件 |
| OpenTelemetry Collector | 遥测数据收集 |

## 验证

```bash
# 查看演示应用Pod状态
kubectl get pods -n demo

# 查看演示应用服务
kubectl get svc -n demo
```

## 注意事项

1. 需要配置本地 hosts 文件
2. 需要 Ingress Controller（nginx-ingress）
3. 部署时间可能较长（需要拉取多个镜像）

## 完成

这是部署流程的最后一步。完成后可以使用验证脚本检查集群状态。