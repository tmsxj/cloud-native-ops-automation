#!/bin/bash

###############################################################################
# 脚本名称：install-elk.sh
# 功能说明：ELK Stack日志系统部署脚本
# 适用场景：在Kubernetes集群中部署日志收集系统
# 使用方法：在master1上执行
###############################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo -e "  ELK Stack日志系统部署"
echo -e "==========================================${NC}"
echo ""

#-------------------------------------------------------------------------------
# 1. 创建日志命名空间
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[1] 创建日志命名空间 ${NC}"
echo "----------------------------------------------"

kubectl create namespace logging || true

echo -e "${GREEN}✓ 命名空间创建完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 2. 部署Elasticsearch
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[2] 部署Elasticsearch ${NC}"
echo "----------------------------------------------"

cat > elasticsearch-single-node.yaml << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: elasticsearch
  namespace: logging
  labels:
    app: elasticsearch
spec:
  serviceName: elasticsearch
  replicas: 1
  selector:
    matchLabels:
      app: elasticsearch
  template:
    metadata:
      labels:
        app: elasticsearch
    spec:
      securityContext:
        fsGroup: 1000
      containers:
      - name: elasticsearch
        image: 192.168.1.61/library/docker.elastic.co_elasticsearch_elasticsearch:8.11.0
        ports:
        - containerPort: 9200
          name: http
        - containerPort: 9300
          name: transport
        env:
        - name: discovery.type
          value: single-node
        - name: xpack.security.enabled
          value: "false"
        - name: ES_JAVA_OPTS
          value: "-Xms1g -Xmx1g"
        volumeMounts:
        - name: data
          mountPath: /usr/share/elasticsearch/data
      volumes:
      - name: data
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch
  namespace: logging
spec:
  ports:
  - port: 9200
    targetPort: 9200
  selector:
    app: elasticsearch
EOF

kubectl apply -f elasticsearch-single-node.yaml

echo -e "${GREEN}✓ Elasticsearch部署完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 3. 部署Filebeat
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[3] 部署Filebeat ${NC}"
echo "----------------------------------------------"

cat > filebeat-kubernetes.yaml << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: filebeat
  namespace: logging
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: filebeat
rules:
- apiGroups: [""]
  resources: ["pods", "nodes", "namespaces"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: filebeat
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: filebeat
subjects:
- kind: ServiceAccount
  name: filebeat
  namespace: logging
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: filebeat-config
  namespace: logging
data:
  filebeat.yml: |
    filebeat.inputs:
    - type: container
      paths:
        - /var/log/containers/*.log
      processors:
        - add_kubernetes_metadata:
            host: ${NODE_NAME}
            matchers:
            - logs_path:
                logs_path: "/var/log/containers/"
    output.elasticsearch:
      hosts: ['elasticsearch.logging:9200']
      indices:
        - index: "filebeat-%{[agent.version]}-%{+yyyy.MM.dd}"
    setup.template.name: "filebeat"
    setup.template.pattern: "filebeat-*"
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: filebeat
  namespace: logging
spec:
  selector:
    matchLabels:
      name: filebeat
  template:
    metadata:
      labels:
        name: filebeat
    spec:
      serviceAccountName: filebeat
      containers:
      - name: filebeat
        image: 192.168.1.61/library/docker.elastic.co_beats_filebeat:8.11.0
        args: [
          "-c", "/etc/filebeat.yml",
          "-e",
        ]
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        volumeMounts:
        - name: config
          mountPath: /etc/filebeat.yml
          subPath: filebeat.yml
        - name: varlog
          mountPath: /var/log
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
        - name: pods
          mountPath: /var/log/pods
          readOnly: true
      volumes:
      - name: config
        configMap:
          name: filebeat-config
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
      - name: pods
        hostPath:
          path: /var/log/pods
EOF

kubectl apply -f filebeat-kubernetes.yaml

echo -e "${GREEN}✓ Filebeat部署完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 4. 部署Kibana
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[4] 部署Kibana ${NC}"
echo "----------------------------------------------"

cat > kibana.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kibana
  namespace: logging
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kibana
  template:
    metadata:
      labels:
        app: kibana
    spec:
      containers:
      - name: kibana
        image: 192.168.1.61/library/docker.elastic.co_kibana_kibana:8.11.0
        ports:
        - containerPort: 5601
        env:
        - name: ELASTICSEARCH_HOSTS
          value: http://elasticsearch.logging:9200
---
apiVersion: v1
kind: Service
metadata:
  name: kibana
  namespace: logging
spec:
  ports:
  - port: 5601
    targetPort: 5601
    nodePort: 30601
  type: NodePort
  selector:
    app: kibana
EOF

kubectl apply -f kibana.yaml

echo -e "${GREEN}✓ Kibana部署完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 5. 等待部署完成
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[5] 等待部署完成 ${NC}"
echo "----------------------------------------------"

echo "等待Elasticsearch启动..."
kubectl wait --namespace logging \
    --for=condition=ready pod \
    --selector=app=elasticsearch \
    --timeout=300s

echo "等待Kibana启动..."
kubectl wait --namespace logging \
    --for=condition=ready pod \
    --selector=app=kibana \
    --timeout=300s

echo -e "${GREEN}✓ 部署完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 6. 验证部署
#-------------------------------------------------------------------------------
echo -e "${YELLOW}[6] 验证部署 ${NC}"
echo "----------------------------------------------"

echo "查看日志Pod状态:"
kubectl get pods -n logging

echo ""
echo "查看日志服务:"
kubectl get svc -n logging

echo ""
echo "Kibana访问地址: http://192.168.1.51:30601"

echo -e "${GREEN}✓ 验证完成${NC}"
echo ""

#-------------------------------------------------------------------------------
# 完成总结
#-------------------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo -e "  ELK Stack部署完成"
echo -e "==========================================${NC}"
echo ""

echo "已部署组件:"
echo "  ✓ Elasticsearch - 日志存储"
echo "  ✓ Filebeat - 日志收集"
echo "  ✓ Kibana - 日志可视化"
echo ""

echo "访问地址:"
echo "  Kibana: http://192.168.1.51:30601"
echo ""

echo "管理命令:"
echo "  kubectl get pods -n logging      # 查看Pod"
echo "  kubectl get svc -n logging       # 查看服务"
echo ""

echo -e "${BLUE}==========================================${NC}"