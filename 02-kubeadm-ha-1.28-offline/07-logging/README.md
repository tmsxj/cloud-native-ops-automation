# 07-logging - 日志系统部署

## 功能说明

本目录包含 ELK Stack 日志系统的部署脚本。

## 脚本清单

| 脚本 | 功能说明 |
|:-----|:---------|
| install-elk.sh | ELK Stack安装脚本 |

## 使用方法

### 在master1上执行

```bash
# 进入目录
cd 07-logging

# 添加执行权限
chmod +x install-elk.sh

# 执行脚本
./install-elk.sh
```

## 脚本功能

`install-elk.sh` 脚本完成以下步骤：

1. **创建命名空间**：创建 logging 命名空间
2. **部署Elasticsearch**：部署单节点 Elasticsearch
3. **部署Filebeat**：部署 DaemonSet 模式的 Filebeat
4. **部署Kibana**：部署 Kibana 可视化界面
5. **等待部署**：等待 Pod 启动
6. **验证部署**：检查服务状态

## 部署配置

| 配置项 | 值 | 说明 |
|:-------|:---|:-----|
| Elasticsearch版本 | 8.11.0 | ES版本 |
| Filebeat版本 | 8.11.0 | Filebeat版本 |
| Kibana版本 | 8.11.0 | Kibana版本 |
| 命名空间 | logging | 部署命名空间 |
| Kibana端口 | 30601 | NodePort端口 |

## 访问方式

```bash
# Kibana访问地址
http://192.168.1.51:30601
```

## 已部署组件

| 组件 | 说明 |
|:-----|:-----|
| Elasticsearch | 日志存储和检索 |
| Filebeat | 日志收集（DaemonSet） |
| Kibana | 日志可视化 |

## 验证

```bash
# 查看日志Pod状态
kubectl get pods -n logging

# 查看日志服务
kubectl get svc -n logging
```

## 注意事项

1. 当前为单节点 Elasticsearch（测试用）
2. 生产环境建议使用 StatefulSet 和 PVC
3. 需要足够的资源（建议至少 2GB 内存给 Elasticsearch）

## 下一步

完成日志部署后，部署演示应用。