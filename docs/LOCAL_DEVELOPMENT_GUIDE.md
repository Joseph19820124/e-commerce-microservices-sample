# Local Development & Testing Guide

## Local Testing Options

### Option 1: Fully Local Testing (Recommended for Beginners)
**No AWS account required, use local Kubernetes**

### Option 2: Hybrid Testing
**Local applications + Cloud infrastructure**

### Option 3: Full Cloud Testing
**AWS account required, full environment testing**

---

## Option 1: Fully Local Testing Environment

### 1.1 Environment Preparation

#### Install Local Kubernetes
```bash
# Choose a local Kubernetes solution:

# Option A: Docker Desktop (Recommended for MacOS/Windows)
# 1. Install Docker Desktop
# 2. Enable Kubernetes
# Settings -> Kubernetes -> Enable Kubernetes

# Option B: Kind (Cross-platform)
# Install Kind
brew install kind  # macOS
# Or curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64

# Create cluster
kind create cluster --name ecommerce-local --config=scripts/local/kind-config.yaml

# Option C: Minikube
brew install minikube  # macOS
minikube start --memory=8192 --cpus=4
```

#### Install Required Tools
```bash
# Kubernetes tools
kubectl version --client
helm version

# Container tools
docker version

# Local development tools
brew install k9s  # Kubernetes UI
brew install stern  # Multi-pod log viewer
```

### 1.2 Local Infrastructure Deployment

#### Create Local Configurations
```bash
# Create local development config directories
mkdir -p local-dev/{postgres,redis,kafka,monitoring}
```

#### Deploy Local Database
```bash
# PostgreSQL
docker run -d \
  --name postgres-local \
  -e POSTGRES_DB=ecommerce \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=password \
  -p 5432:5432 \
  postgres:15

# Or deploy with Kubernetes
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

#### Deploy Local Redis
```bash
# Docker method
docker run -d \
  --name redis-local \
  -p 6379:6379 \
  redis:7-alpine

# Kubernetes method
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

### 1.3 Simplified Monitoring Deployment

#### Deploy Prometheus (Lightweight)
```bash
# Use Helm to install a lightweight Prometheus
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install lightweight monitoring stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.persistence.enabled=false \
  --set prometheus.prometheusSpec.retention=1d \
  --set prometheus.prometheusSpec.resources.requests.memory=512Mi \
  --set prometheus.prometheusSpec.resources.limits.memory=1Gi
```

#### Access Monitoring Interfaces
```bash
# Grafana
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring
# Visit http://localhost:3000 (admin/prom-operator)

# Prometheus
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring
# Visit http://localhost:9090
```

### 1.4 Microservices Local Development

#### Create Local Development Config
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
        imagePullPolicy: Never  # Use locally built image
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

#### Local Build and Deployment Script
```bash
#!/bin/bash
# scripts/local-dev.sh

set -e

echo "🚀 Starting local development environment..."

# Build local images
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

# Load images into Kind cluster (if using Kind)
if command -v kind &> /dev/null; then
    echo "Loading images to Kind cluster..."
    kind load docker-image cart-service:local --name ecommerce-local
    kind load docker-image product-service:local --name ecommerce-local
    kind load docker-image user-service:local --name ecommerce-local
fi

# Deploy services
echo "Deploying services..."
kubectl apply -f local-dev/

# Wait for services to be ready
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

## Option 2: Hybrid Testing Environment

### 2.1 Local Application + Cloud Infrastructure

If you have an AWS account, you can:
- Use cloud RDS, ElastiCache
- Run application services locally
- Connect to cloud infrastructure for testing

#### Connect to Cloud Database
```bash
# Get RDS connection info
aws rds describe-db-instances --db-instance-identifier ecommerce-dev-db

# Configure local app to connect to cloud database
export DATABASE_URL="jdbc:postgresql://ecommerce-dev-db.xxx.us-west-2.rds.amazonaws.com:5432/ecommerce"
export REDIS_URL="redis://ecommerce-dev-redis.xxx.cache.amazonaws.com:6379"
```

---

## Local Testing Scripts

### Automated Local Testing
```bash
#!/bin/bash
# scripts/local-test.sh

echo "🧪 Running local tests..."

# Health check
echo "Checking service health..."
kubectl port-forward svc/cart-service-local 8080:80 &
PF_PID=$!
sleep 5

# API test
echo "Testing APIs..."
curl -f http://localhost:8080/actuator/health || echo "❌ Health check failed"

# Functionality test
echo "Testing cart functionality..."
response=$(curl -s -X POST http://localhost:8080/api/cart/items \
  -H "Content-Type: application/json" \
  -d '{"userId": 1, "productId": 1, "quantity": 2}')

if [[ $response != *"error"* ]]; then
    echo "✅ Cart API test passed"
else
    echo "❌ Cart API test failed: $response"
fi

# Cleanup
kill $PF_PID 2>/dev/null || true

echo "🎉 Local tests completed!"
```

### Performance Testing (Local)
```bash
# Simple load test
#!/bin/bash
kubectl port-forward svc/cart-service-local 8080:80 &
PF_PID=$!
sleep 5

# Use Apache Bench for simple load test
ab -n 1000 -c 10 http://localhost:8080/actuator/health

kill $PF_PID 2>/dev/null || true
```

---

## Development Workflow

### Daily Development Process
```bash
# 1. Start local environment
./scripts/local-dev.sh

# 2. Develop code
# Edit cart-cna-microservice/src/...

# 3. Rebuild and redeploy
cd cart-cna-microservice
docker build -t cart-service:local .
kind load docker-image cart-service:local --name ecommerce-local  # If using Kind
kubectl rollout restart deployment/cart-service-local

# 4. Test
./scripts/local-test.sh

# 5. View logs
kubectl logs -f deployment/cart-service-local
```

### Debugging Tips
```bash
# View all pod statuses
kubectl get pods

# View service logs
kubectl logs -f deployment/cart-service-local

# Enter pod for debugging
kubectl exec -it deployment/cart-service-local -- sh

# View resource usage
kubectl top pods

# Use k9s for interactive management
k9s
```

---

## Common Issues & Solutions

### 1. Image Pull Failure
```bash
# Ensure using locally built image
kubectl patch deployment cart-service-local -p '{"spec":{"template":{"spec":{"containers":[{"name":"cart-service","imagePullPolicy":"Never"}]}}}}'
```

### 2. Service Inaccessible
```bash
# Check service status
kubectl get svc
kubectl describe svc cart-service-local

# Port-forward test
kubectl port-forward svc/cart-service-local 8080:80
```

### 3. Insufficient Resources
```bash
# Reduce resource requests
kubectl patch deployment cart-service-local -p '{"spec":{"template":{"spec":{"containers":[{"name":"cart-service","resources":{"requests":{"memory":"128Mi","cpu":"50m"}}}]}}}}'
```

### 4. Database Connection Issues
```bash
# Test database connection
kubectl run db-test --image=postgres:15 --rm -it -- psql -h postgres-local -U postgres -d ecommerce
```

---

## Quick Start Commands

### One-Click Local Environment Startup
```bash
# Clone the project
git clone https://github.com/Joseph19820124/e-commerce-microservices-sample.git
cd e-commerce-microservices-sample

# Create local cluster (Kind)
kind create cluster --name ecommerce-local

# Start local development environment
./scripts/local-dev.sh

# Run tests
./scripts/local-test.sh
```

### Clean Up Environment
```bash
# Delete Kind cluster
kind delete cluster --name ecommerce-local

# Or clean up Kubernetes resources
kubectl delete namespace default --force
kubectl delete namespace monitoring --force

# Clean up Docker containers
docker stop postgres-local redis-local
docker rm postgres-local redis-local
```

---

## Cost Comparison

| Testing Mode | AWS Cost | Local Resource Needs | Test Coverage | Recommended Scenario |
|-------------|----------|---------------------|--------------|---------------------|
| Fully Local | $0 | 8GB RAM + 4 CPU | 70% | Daily development |
| Hybrid | ~$50/month | 4GB RAM + 2 CPU | 90% | Integration testing |
| Full Cloud | ~$200/month | Minimal local | 100% | Production validation |

**Recommendation**: Start with fully local, then gradually move to hybrid or cloud testing.