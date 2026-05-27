#!/bin/bash

echo "=========================================="
echo " Harbor HTTPS 连接 K8s 集群问题沙箱模拟"
echo "=========================================="
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}步骤 1：模拟 Harbor HTTPS 配置${NC}"
echo "----------------------------------------------"
cat > harbor.yml << 'EOF'
hostname: 192.168.1.61
http:
  port: 80
https:
  port: 443
  certificate: /data/cert/server.crt
  private_key: /data/cert/server.key
harbor_admin_password: Harbor12345
EOF

cat harbor.yml
echo ""
echo -e "${YELLOW}⚠️ 现在尝试连接...${NC}"
echo ""
echo -e "${RED}❌ 错误：x509: cannot validate certificate${NC}"
echo -e "${RED}❌ 错误：http: server gave HTTP response to HTTPS client${NC}"
echo ""

echo -e "${YELLOW}步骤 2：改为 HTTP 方式（您的方案 ✅）${NC}"
echo "----------------------------------------------"
cat > harbor.http.yml << 'EOF'
hostname: 192.168.1.61
http:
  port: 80
# https:  # 注释掉
harbor_admin_password: Harbor12345
EOF

cat harbor.http.yml
echo ""

echo -e "${YELLOW}步骤 3：创建 hosts.toml${NC}"
echo "----------------------------------------------"
mkdir -p certs.d/192.168.1.61
cat > certs.d/192.168.1.61/hosts.toml << 'EOF'
server = "http://192.168.1.61"

[host."http://192.168.1.61"]
  capabilities = ["pull", "resolve"]
EOF

cat certs.d/192.168.1.61/hosts.toml
echo ""

echo -e "${GREEN}=========================================="
echo -e " 成功！现在可以正常拉取镜像了！"
echo -e "==========================================${NC}"
echo ""
echo -e "总结："
echo -e "  - HTTPS：需要证书，IP 访问时证书需包含该 IP SAN"
echo -e "  - HTTP：适合测试环境，无需证书，配置简单"
echo ""
echo -e "您当前的配置就是 HTTP 方式，是正确的！"
