# Harbor HTTPS 连接 K8s 问题沙箱演示

## 问题

当您尝试用 HTTPS 方式连接 Harbor 和 K8s 时，会遇到以下 TLS 相关错误：

### 错误 1：证书 IP SAN 问题
```
x509: cannot validate certificate for 192.168.1.61 because it doesn't contain any IP SANs
```

### 错误 2：协议不匹配
```
http: server gave HTTP response to HTTPS client
```

---

## 演示说明

运行沙箱演示脚本可以看到这两种场景：

```bash
cd sandbox
chmod +x run-demo.sh
./run-demo.sh
```

---

## 解决方案（您当前在用的 ✅）

### 1. Harbor 配置（HTTP 方式）

在 `harbor.yml` 中注释 HTTPS：
```yaml
hostname: 192.168.1.61
http:
  port: 80
# https:  # 注释掉
```

### 2. containerd 配置

创建 `hosts.toml`:
```toml
server = "http://192.168.1.61"

[host."http://192.168.1.61"]
  capabilities = ["pull", "resolve"]
```

---

## 为什么测试环境用 HTTP 就够了？

- 无需管理自签名证书
- 配置简单，不易出错
- 测试环境对安全性要求不高

---

## 相关文件

| 文件 | 说明 |
|:-----|:-----|
| `run-demo.sh` | 运行沙箱演示 |
| `../02-harbor/install.sh` | Harbor 安装脚本 |
| `../03-containerd/configure.sh` | containerd 配置脚本 |