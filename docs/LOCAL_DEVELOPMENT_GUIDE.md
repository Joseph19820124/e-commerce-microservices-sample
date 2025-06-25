# 本地开发测试指南

## 本地测试选项

### 选项1: 完全本地测试 (推荐入门)
**无需AWS账户，使用本地Kubernetes**

### 选项2: 混合测试
**本地应用 + 云端基础设施**

### 选项3: 完整云端测试
**需要AWS账户，完整环境测试**

---

## 选项1: 完全本地测试环境

### 1.1 环境准备

#### 安装本地Kubernetes
```bash
# 选择一种本地Kubernetes方案：

# 方案A: Docker Desktop (推荐MacOS/Windows)
# 1. 安装Docker Desktop
# 2. 启用Kubernetes功能
# Settings -> Kubernetes -> Enable Kubernetes

# 方案B: Kind (跨平台)
# 安装Kind
brew install kind  # macOS
# 或 curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64

# 创建集群
kind create cluster --name ecommerce-local --config=scripts/local/kind-config.yaml

# 方案C: Minikube
brew install minikube  # macOS
minikube start --memory=8192 --cpus=4
```

#### 安装必要工具
```bash
# Kubernetes工具
kubectl version --client
helm version

# 容器工具
docker version

# 本地开发工具
brew install k9s  # Kubernetes UI
brew install stern  # 多Pod日志查看
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

# 或使用Kubernetes部署
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

#### 部署本地Redis
```bash
# Docker方式
docker run -d \
  --name redis-local \
  -p 6379:6379 \
  redis:7-alpine

# Kubernetes方式
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

### 1.3 简化版监控部署

#### 部署Prometheus (轻量版)
```bash
# 使用Helm安装简化版Prometheus
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 安装轻量版监控栈
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

echo "🚀 Starting local development environment..."

# 构建本地镜像
echo "Building local images..."
cd cart-cna-microservice
docker build -t cart-service:local .
cd ..

cd products-cna-microservice
docker build -t product-service:local .
cd ..

cd users-cna-microservice
docker build -t user-service:local .
cd ..

# 加载镜像到Kind集群 (如果使用Kind)
if command -v kind &> /dev/null; then
    echo "Loading images to Kind cluster..."
    kind load docker-image cart-service:local --name ecommerce-local
    kind load docker-image product-service:local --name ecommerce-local
    kind load docker-image user-service:local --name ecommerce-local
fi

# 部署服务
echo "Deploying services..."
kubectl apply -f local-dev/

# 等待服务就绪
echo "Waiting for services to be ready..."
kubectl wait --for=condition=ready pod -l app=postgres-local --timeout=60s
kubectl wait --for=condition=ready pod -l app=redis-local --timeout=60s
kubectl wait --for=condition=ready pod -l app=cart-service-local --timeout=120s

echo "✅ Local development environment is ready!"
echo ""
echo "🔗 Service URLs:"
echo "Cart Service: http://localhost:8080 (use kubectl port-forward)"
echo "Grafana: http://localhost:3000"
echo "Prometheus: http://localhost:9090"
echo ""
echo "📝 Quick commands:"
echo "kubectl port-forward svc/cart-service-local 8080:80"
echo "kubectl logs -f deployment/cart-service-local"
echo "kubectl get pods"
```

---

## 选项2: 混合测试环境

### 2.1 本地应用 + 云端基础设施

如果您有AWS账户，可以：
- 使用云端RDS、ElastiCache
- 本地运行应用服务
- 连接到云端基础设施进行测试

#### 连接云端数据库
```bash
# 获取RDS连接信息
aws rds describe-db-instances --db-instance-identifier ecommerce-dev-db

# 配置本地应用连接云端数据库
export DATABASE_URL="jdbc:postgresql://ecommerce-dev-db.xxx.us-west-2.rds.amazonaws.com:5432/ecommerce"
export REDIS_URL="redis://ecommerce-dev-redis.xxx.cache.amazonaws.com:6379"
```

---

## 本地测试脚本

### 自动化本地测试
```bash
#!/bin/bash
# scripts/local-test.sh

echo "🧪 Running local tests..."

# 健康检查
echo "Checking service health..."
kubectl port-forward svc/cart-service-local 8080:80 &
PF_PID=$!
sleep 5

# API测试
echo "Testing APIs..."
curl -f http://localhost:8080/actuator/health || echo "❌ Health check failed"

# 功能测试
echo "Testing cart functionality..."
response=$(curl -s -X POST http://localhost:8080/api/cart/items \
  -H "Content-Type: application/json" \
  -d '{"userId": 1, "productId": 1, "quantity": 2}')

if [[ $response != *"error"* ]]; then
    echo "✅ Cart API test passed"
else
    echo "❌ Cart API test failed: $response"
fi

# 清理
kill $PF_PID 2>/dev/null || true

echo "🎉 Local tests completed!"
```

### 性能测试 (本地)
```bash
# 简单负载测试
#!/bin/bash
kubectl port-forward svc/cart-service-local 8080:80 &
PF_PID=$!
sleep 5

# 使用Apache Bench进行简单负载测试
ab -n 1000 -c 10 http://localhost:8080/actuator/health

kill $PF_PID 2>/dev/null || true
```

---

## 开发工作流

### 日常开发流程
```bash
# 1. 启动本地环境
./scripts/local-dev.sh

# 2. 开发代码
# 修改 cart-cna-microservice/src/...

# 3. 重新构建和部署
cd cart-cna-microservice
docker build -t cart-service:local .
kind load docker-image cart-service:local --name ecommerce-local  # 如果使用Kind
kubectl rollout restart deployment/cart-service-local

# 4. 测试
./scripts/local-test.sh

# 5. 查看日志
kubectl logs -f deployment/cart-service-local
```

### 调试技巧
```bash
# 查看所有Pod状态
kubectl get pods

# 查看服务日志
kubectl logs -f deployment/cart-service-local

# 进入Pod调试
kubectl exec -it deployment/cart-service-local -- sh

# 查看资源使用
kubectl top pods

# 使用k9s进行交互式管理
k9s
```

---

## 常见问题解决

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

## 快速开始命令

### 一键启动本地环境
```bash
# 克隆项目
git clone https://github.com/Joseph19820124/e-commerce-microservices-sample.git
cd e-commerce-microservices-sample

# 创建本地集群 (Kind)
kind create cluster --name ecommerce-local

# 启动本地开发环境
./scripts/local-dev.sh

# 运行测试
./scripts/local-test.sh
```

### 清理环境
```bash
# 删除Kind集群
kind delete cluster --name ecommerce-local

# 或清理Kubernetes资源
kubectl delete namespace default --force
kubectl delete namespace monitoring --force

# 清理Docker容器
docker stop postgres-local redis-local
docker rm postgres-local redis-local
```

---

## 成本对比

| 测试方式 | AWS成本 | 本地资源需求 | 测试覆盖度 | 推荐场景 |
|---------|---------|------------|-----------|----------|
| 完全本地 | $0 | 8GB RAM + 4 CPU | 70% | 日常开发 |
| 混合测试 | ~$50/月 | 4GB RAM + 2 CPU | 90% | 集成测试 |
| 完整云端 | ~$200/月 | 最小本地环境 | 100% | 生产验证 |

**推荐**: 从完全本地开始，逐步过渡到混合或云端测试。