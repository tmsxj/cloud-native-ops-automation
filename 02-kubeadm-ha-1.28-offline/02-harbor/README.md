# 02-harbor - Harbor部署

## 功能说明

本目录包含 Harbor 私有镜像仓库的部署脚本和配置文件。

## 脚本清单

| 脚本 | 功能说明 |
|:-----|:---------|
| install.sh | Harbor离线安装脚本 |

## 使用方法

### 在harbor节点（192.168.1.61）上执行

```bash
# 进入目录
cd 02-harbor

# 添加执行权限
chmod +x install.sh

# 执行脚本（需要root权限）
sudo ./install.sh
```

## 脚本功能

`install.sh` 脚本完成以下步骤：

1. **安装Docker**：添加Docker仓库并安装
2. **下载Harbor**：下载 Harbor v2.9.0 离线安装包
3. **配置Harbor**：生成 harbor.yml 配置文件
4. **安装Harbor**：执行 install.sh 安装
5. **验证安装**：检查容器状态和登录测试

## Harbor配置

| 配置项 | 值 | 说明 |
|:-------|:---|:-----|
| 地址 | 192.168.1.61 | Harbor节点IP |
| 端口 | 80 | HTTP端口 |
| 用户名 | admin | 管理员用户名 |
| 密码 | Harbor12345 | 管理员密码 |
| 数据目录 | /data | 镜像数据存储目录 |

## 访问方式

```bash
# 浏览器访问
http://192.168.1.61

# Docker登录
docker login 192.168.1.61 -u admin -p Harbor12345
```

## 管理命令

```bash
cd /data/harbor

# 启动
docker compose up -d

# 停止
docker compose stop

# 重启
docker compose restart

# 查看状态
docker compose ps
```

## 注意事项

1. 需要在 harbor 节点（192.168.1.61）上执行
2. 需要 root 权限
3. 确保至少有 4GB 内存和足够的磁盘空间
4. 安装包约 1.5GB，需要提前下载

## 下一步

完成 Harbor 部署后，进入下一步配置 containerd 使用 Harbor 镜像。