# 本地开发与测试指南

## 本地测试选项

### 选项 1：完全本地测试（初学者推荐）
**无需 AWS 账户，使用本地 Kubernetes**

### 选项 2：混合测试
**本地应用 + 云端基础设施**

### 选项 3：完全云端测试
**需要 AWS 账户，完整环境测试**

---

## 选项 1：完全本地测试环境

### 1.1 环境准备

#### 安装本地 Kubernetes
```bash
# 选择一个本地 Kubernetes 解决方案：

# 选项 A：Docker Desktop（推荐用于 MacOS/Windows）
# 1. 安装 Docker Desktop
# 2. 启用 Kubernetes
# 设置 -> Kubernetes -> 启用 Kubernetes

# 选项 B：Kind（跨平台）
# 安装 Kind
brew install kind  # macOS
# 或 curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64

# 创建集群
kind create cluster --name ecommerce-local --config=scripts/local/kind-config.yaml

# 选项 C：Minikube
brew install minikube  # macOS
minikube start --memory=8192 --cpus=4
```

#### 安装必需工具
```bash
# Kubernetes 工具
kubectl version --client
helm version

# 容器工具
docker version

# 本地开发工具
brew install k9s  # Kubernetes UI
brew install stern  # 多 Pod 日志查看器
```

### 1.2 本地基础设施部署

#### 创建本地配置
```bash
# 创建本地开发配置目录
mkdir -p local-dev/{postgres,redis,kafka,monitoring}
```

#### 部署本地数据库
```bash
# PostgreSQL
docker run -d \
  --name postgres-local \
  -e POSTGRES_DB=ecommerce \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=password \
  -p 5432:5432 \
  postgres:15

# 或使用 Kubernetes 部署
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-local
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres-local
  template:
    metadata:
      labels:
        app: postgres-local
    spec:
      containers:
      - name: postgres
        image: postgres:15
        env:
        - name: POSTGRES_DB
          value: ecommerce
        - name: POSTGRES_USER
          value: postgres
        - name: POSTGRES_PASSWORD
          value: password
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: postgres-storage
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-local
spec:
  selector:
    app: postgres-local
  ports:
  - port: 5432
    targetPort: 5432
  type: ClusterIP
EOF
```

#### 部署本地 Redis
```bash
# Docker 方式
docker run -d \
  --name redis-local \
  -p 6379:6379 \
  redis:7-alpine

# Kubernetes 方式
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-local
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis-local
  template:
    metadata:
      labels:
        app: redis-local
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
---
apiVersion: v1
kind: Service
metadata:
  name: redis-local
spec:
  selector:
    app: redis-local
  ports:
  - port: 6379
    targetPort: 6379
EOF
```

### 1.3 简化监控部署

#### 部署 Prometheus（轻量级）
```bash
# 使用 Helm 安装轻量级 Prometheus
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 安装轻量级监控栈
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.persistence.enabled=false \
  --set prometheus.prometheusSpec.retention=1d \
  --set prometheus.prometheusSpec.resources.requests.memory=512Mi \
  --set prometheus.prometheusSpec.resources.limits.memory=1Gi
```

#### 访问监控界面
```bash
# Grafana
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring
# 访问 http://localhost:3000 (admin/prom-operator)

# Prometheus
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring
# 访问 http://localhost:9090
```

### 1.4 微服务本地开发

#### 创建本地开发配置
```yaml
# local-dev/cart-service-local.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cart-service-local
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cart-service-local
  template:
    metadata:
      labels:
        app: cart-service-local
    spec:
      containers:
      - name: cart-service
        image: cart-service:local
        imagePullPolicy: Never  # 使用本地构建的镜像
        ports:
        - containerPort: 8080
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "local"
        - name: DATABASE_URL
          value: "jdbc:postgresql://postgres-local:5432/ecommerce"
        - name: REDIS_URL
          value: "redis://redis-local:6379"
        resources:
          requests:
            memory: 256Mi
            cpu: 100m
          limits:
            memory: 512Mi
            cpu: 500m
---
apiVersion: v1
kind: Service
metadata:
  name: cart-service-local
spec:
  selector:
    app: cart-service-local
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP
```

#### 本地构建和部署脚本
```bash
#!/bin/bash
# scripts/local-dev.sh

set -e

echo "🚀 启动本地开发环境..."

# 构建本地镜像
echo "构建本地镜像..."
cd cart-cna-microservice
docker build -t cart-service:local .
cd ..

cd products-cna-microservice
docker build -t product-service:local .
cd ..

cd users-cna-microservice
docker build -t user-service:local .
cd ..

# 加载镜像到 Kind 集群（如果使用 Kind）
if command -v kind &> /dev/null; then
    echo "加载镜像到 Kind 集群..."
    kind load docker-image cart-service:local --name ecommerce-local
    kind load docker-image product-service:local --name ecommerce-local
    kind load docker-image user-service:local --name ecommerce-local
fi

# 部署服务
echo "部署服务..."
kubectl apply -f local-dev/

# 等待服务就绪
echo "等待服务就绪..."
kubectl wait --for=condition=ready pod -l app=postgres-local --timeout=60s
kubectl wait --for=condition=ready pod -l app=redis-local --timeout=60s
kubectl wait --for=condition=ready pod -l app=cart-service-local --timeout=120s

echo "✅ 本地开发环境已就绪！"
echo ""
echo "🔗 服务 URL："
echo "购物车服务：http://localhost:8080（使用 kubectl port-forward）"
echo "Grafana：http://localhost:3000"
echo "Prometheus：http://localhost:9090"
echo ""
echo "📝 快速命令："
echo "kubectl port-forward svc/cart-service-local 8080:80"
echo "kubectl logs -f deployment/cart-service-local"
echo "kubectl get pods"
```

---

## 选项 2：混合测试环境

### 2.1 本地应用 + 云端基础设施

如果您有 AWS 账户，可以：
- 使用云端 RDS、ElastiCache
- 在本地运行应用服务
- 连接到云端基础设施进行测试

#### 连接到云端数据库
```bash
# 获取 RDS 连接信息
aws rds describe-db-instances --db-instance-identifier ecommerce-dev-db

# 配置本地应用连接到云端数据库
export DATABASE_URL="jdbc:postgresql://ecommerce-dev-db.xxx.us-west-2.rds.amazonaws.com:5432/ecommerce"
export REDIS_URL="redis://ecommerce-dev-redis.xxx.cache.amazonaws.com:6379"
```

---

## 本地测试脚本

### 自动化本地测试
```bash
#!/bin/bash
# scripts/local-test.sh

echo "🧪 运行本地测试..."

# 健康检查
echo "检查服务健康状态..."
kubectl port-forward svc/cart-service-local 8080:80 &
PF_PID=$!
sleep 5

# API 测试
echo "测试 API..."
curl -f http://localhost:8080/actuator/health || echo "❌ 健康检查失败"

# 功能测试
echo "测试购物车功能..."
response=$(curl -s -X POST http://localhost:8080/api/cart/items \
  -H "Content-Type: application/json" \
  -d '{"userId": 1, "productId": 1, "quantity": 2}')

if [[ $response != *"error"* ]]; then
    echo "✅ 购物车 API 测试通过"
else
    echo "❌ 购物车 API 测试失败：$response"
fi

# 清理
kill $PF_PID 2>/dev/null || true

echo "🎉 本地测试完成！"
```

### 性能测试（本地）
```bash
# 简单负载测试
#!/bin/bash
kubectl port-forward svc/cart-service-local 8080:80 &
PF_PID=$!
sleep 5

# 使用 Apache Bench 进行简单负载测试
ab -n 1000 -c 10 http://localhost:8080/actuator/health

kill $PF_PID 2>/dev/null || true
```

---

## 开发工作流程

### 日常开发流程
```bash
# 1. 启动本地环境
./scripts/local-dev.sh

# 2. 开发代码
# 编辑 cart-cna-microservice/src/...

# 3. 重新构建和部署
cd cart-cna-microservice
docker build -t cart-service:local .
kind load docker-image cart-service:local --name ecommerce-local  # 如果使用 Kind
kubectl rollout restart deployment/cart-service-local

# 4. 测试
./scripts/local-test.sh

# 5. 查看日志
kubectl logs -f deployment/cart-service-local
```

### 调试技巧
```bash
# 查看所有 Pod 状态
kubectl get pods

# 查看服务日志
kubectl logs -f deployment/cart-service-local

# 进入 Pod 进行调试
kubectl exec -it deployment/cart-service-local -- sh

# 查看资源使用情况
kubectl top pods

# 使用 k9s 进行交互式管理
k9s
```

---

## 常见问题与解决方案

### 1. 镜像拉取失败
```bash
# 确保使用本地构建的镜像
kubectl patch deployment cart-service-local -p '{"spec":{"template":{"spec":{"containers":[{"name":"cart-service","imagePullPolicy":"Never"}]}}}}'
```

### 2. 服务无法访问
```bash
# 检查服务状态
kubectl get svc
kubectl describe svc cart-service-local

# 端口转发测试
kubectl port-forward svc/cart-service-local 8080:80
```

### 3. 资源不足
```bash
# 减少资源请求
kubectl patch deployment cart-service-local -p '{"spec":{"template":{"spec":{"containers":[{"name":"cart-service","resources":{"requests":{"memory":"128Mi","cpu":"50m"}}}]}}}}'
```

### 4. 数据库连接问题
```bash
# 测试数据库连接
kubectl run db-test --image=postgres:15 --rm -it -- psql -h postgres-local -U postgres -d ecommerce
```

---

## 快速启动命令

### 一键启动本地环境
```bash
# 克隆项目
git clone https://github.com/Joseph19820124/e-commerce-microservices-sample.git
cd e-commerce-microservices-sample

# 创建本地集群（Kind）
kind create cluster --name ecommerce-local

# 启动本地开发环境
./scripts/local-dev.sh

# 运行测试
./scripts/local-test.sh
```

### 清理环境
```bash
# 删除 Kind 集群
kind delete cluster --name ecommerce-local

# 或清理 Kubernetes 资源
kubectl delete namespace default --force
kubectl delete namespace monitoring --force

# 清理 Docker 容器
docker stop postgres-local redis-local
docker rm postgres-local redis-local
```

---

## 成本对比

| 测试模式 | AWS 成本 | 本地资源需求 | 测试覆盖率 | 推荐场景 |
|---------|----------|-------------|-----------|---------|
| 完全本地 | $0 | 8GB 内存 + 4 CPU | 70% | 日常开发 |
| 混合模式 | ~$50/月 | 4GB 内存 + 2 CPU | 90% | 集成测试 |
| 完全云端 | ~$200/月 | 最小本地需求 | 100% | 生产验证 |

**建议**：从完全本地开始，然后逐步过渡到混合或云端测试。