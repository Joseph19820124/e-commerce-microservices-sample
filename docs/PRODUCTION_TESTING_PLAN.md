# E-Commerce Microservices Production Testing Plan

## 概述

本文档提供了Phase 1-5的详尽测试计划，确保在生产环境部署前验证所有组件的功能性、安全性和性能。

## 测试环境要求

### 基础要求
- AWS账户，具有EKS、RDS、ElastiCache等服务权限
- kubectl、terraform、docker、helm已安装
- 测试域名（如 `test.ecommerce.com`）
- SSL证书管理工具

### 工具准备
```bash
# 必需工具
kubectl version --client
terraform version
docker version
helm version

# 测试工具
curl --version
jq --version
# 安装k6（性能测试）
brew install k6
# 安装newman（API测试）
npm install -g newman
```

---

## Phase 1: 基础设施测试

### 1.1 Terraform基础设施验证

#### 预验证步骤
```bash
# 1. 验证Terraform配置
cd infra/terraform/environments/dev
terraform init
terraform validate
terraform plan -detailed-exitcode

# 2. 检查变量配置
cat variables.tf | grep -E "default|description"

# 3. 验证模块依赖
terraform providers
```

#### 基础设施部署测试
```bash
# 1. 部署开发环境基础设施
terraform apply -auto-approve

# 2. 验证VPC创建
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=ecommerce-dev-vpc"

# 3. 验证子网创建
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)"

# 4. 验证EKS集群
aws eks describe-cluster --name ecommerce-dev-cluster
kubectl cluster-info

# 5. 验证RDS实例
aws rds describe-db-instances --db-instance-identifier ecommerce-dev-db

# 6. 验证ElastiCache集群
aws elasticache describe-cache-clusters --cache-cluster-id ecommerce-dev-redis
```

#### 网络连通性测试
```bash
# 1. 测试EKS节点组
kubectl get nodes -o wide

# 2. 测试Pod网络
kubectl run test-pod --image=busybox --rm -it -- sh
# 在Pod内执行
nslookup kubernetes.default.svc.cluster.local
ping google.com

# 3. 测试数据库连接
kubectl run db-test --image=postgres:15 --rm -it -- sh
# 连接RDS
psql -h $(terraform output -raw rds_endpoint) -U postgres -d ecommerce

# 4. 测试Redis连接
kubectl run redis-test --image=redis:7 --rm -it -- sh
# 连接ElastiCache
redis-cli -h $(terraform output -raw elasticache_endpoint) ping
```

#### 预期结果
- [ ] 所有Terraform资源创建成功
- [ ] EKS集群运行正常，节点Ready
- [ ] RDS实例可连接，数据库创建成功
- [ ] ElastiCache集群可访问
- [ ] 网络路由配置正确

---

## Phase 2: 安全与认证测试

### 2.1 Keycloak身份认证测试

#### 部署Keycloak
```bash
# 1. 部署Keycloak
kubectl apply -f k8s/security/keycloak.yaml

# 2. 等待Pod就绪
kubectl wait --for=condition=ready pod -l app=keycloak -n security --timeout=300s

# 3. 获取Keycloak服务地址
kubectl get svc keycloak-service -n security
```

#### 认证功能测试
```bash
# 1. 访问Keycloak管理控制台
kubectl port-forward svc/keycloak-service 8080:80 -n security &
# 浏览器访问 http://localhost:8080

# 2. 管理员登录测试
# 用户名: admin, 密码: admin123

# 3. 创建测试Realm和用户
# API测试创建用户
curl -X POST "http://localhost:8080/admin/realms/ecommerce/users" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "test@example.com",
    "enabled": true,
    "credentials": [{
      "type": "password",
      "value": "testpass123",
      "temporary": false
    }]
  }'

# 4. 用户认证测试
curl -X POST "http://localhost:8080/realms/ecommerce/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&client_id=ecommerce-client&username=testuser&password=testpass123"
```

### 2.2 Vault秘钥管理测试

#### 部署和初始化Vault
```bash
# 1. 部署Vault
kubectl apply -f k8s/security/vault.yaml

# 2. 初始化Vault
kubectl exec -it vault-0 -n security -- vault operator init

# 3. 解封Vault (使用初始化输出的unseal keys)
kubectl exec -it vault-0 -n security -- vault operator unseal <unseal-key-1>
kubectl exec -it vault-0 -n security -- vault operator unseal <unseal-key-2>
kubectl exec -it vault-0 -n security -- vault operator unseal <unseal-key-3>

# 4. 登录Vault
kubectl exec -it vault-0 -n security -- vault auth -method=userpass username=admin password=admin123
```

#### 秘钥管理测试
```bash
# 1. 创建测试秘钥
kubectl exec -it vault-0 -n security -- vault kv put secret/db-credentials \
  username=postgres \
  password=secretpassword

# 2. 读取秘钥
kubectl exec -it vault-0 -n security -- vault kv get secret/db-credentials

# 3. 测试Kubernetes集成
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vault-test-secret
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "myapp"
    vault.hashicorp.com/agent-inject-secret-database: "secret/db-credentials"
EOF
```

### 2.3 mTLS和服务网格测试

#### 部署Istio
```bash
# 1. 安装Istio
kubectl apply -f k8s/istio/install.yaml

# 2. 验证Istio安装
kubectl get pods -n istio-system

# 3. 启用自动sidecar注入
kubectl label namespace default istio-injection=enabled
```

#### mTLS策略测试
```bash
# 1. 部署测试服务
kubectl apply -f k8s/security/mtls-policy.yaml

# 2. 验证mTLS策略生效
kubectl exec -it $(kubectl get pod -l app=sleep -o jsonpath='{.items[0].metadata.name}') \
  -- curl -s http://httpbin:8000/headers

# 3. 检查证书
kubectl exec -it $(kubectl get pod -l app=sleep -o jsonpath='{.items[0].metadata.name}') \
  -c istio-proxy -- openssl s_client -connect httpbin:8000 -verify_return_error
```

#### 预期结果
- [ ] Keycloak管理控制台可访问
- [ ] 用户认证和授权功能正常
- [ ] Vault秘钥存储和读取正常
- [ ] mTLS证书自动配置和轮换
- [ ] 服务间通信加密验证

---

## Phase 3: 微服务功能测试

### 3.1 应用服务部署测试

#### 构建和部署服务
```bash
# 1. 构建Docker镜像
cd cart-cna-microservice
docker build -t cart-service:test .

cd ../products-cna-microservice
docker build -t product-service:test .

cd ../users-cna-microservice
docker build -t user-service:test .

# 2. 部署到集群
kubectl apply -f k8s/apps/cart-service.yaml
kubectl apply -f k8s/apps/product-service.yaml

# 3. 验证Pod状态
kubectl get pods -l app=cart-service
kubectl get pods -l app=product-service
kubectl get pods -l app=user-service
```

### 3.2 API功能测试

#### 健康检查测试
```bash
# 1. 端口转发
kubectl port-forward svc/cart-service 8080:80 &
kubectl port-forward svc/product-service 8081:80 &
kubectl port-forward svc/user-service 8082:80 &

# 2. 健康检查
curl http://localhost:8080/actuator/health
curl http://localhost:8081/health
curl http://localhost:8082/health
```

#### 业务功能测试
```bash
# 1. 用户服务测试
# 创建用户
curl -X POST http://localhost:8082/api/users \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "test@example.com",
    "password": "password123"
  }'

# 获取用户信息
curl http://localhost:8082/api/users/1

# 2. 产品服务测试
# 获取产品列表
curl http://localhost:8081/api/products

# 搜索产品
curl http://localhost:8081/api/products/search?q=laptop

# 3. 购物车服务测试
# 添加商品到购物车
curl -X POST http://localhost:8080/api/cart/items \
  -H "Content-Type: application/json" \
  -d '{
    "userId": 1,
    "productId": 1,
    "quantity": 2
  }'

# 获取购物车
curl http://localhost:8080/api/cart/1
```

### 3.3 事件驱动架构测试

#### 部署Kafka
```bash
# 1. 部署Kafka集群
kubectl apply -f k8s/messaging/kafka.yaml

# 2. 验证Kafka Pod
kubectl get pods -l app=kafka -n messaging

# 3. 创建测试Topic
kubectl exec -it kafka-0 -n messaging -- kafka-topics.sh \
  --create --topic test-events \
  --bootstrap-server localhost:9092 \
  --partitions 3 --replication-factor 1
```

#### 事件发布订阅测试
```bash
# 1. 测试事件发布
curl -X POST http://localhost:8080/api/cart/items \
  -H "Content-Type: application/json" \
  -d '{
    "userId": 1,
    "productId": 1,
    "quantity": 2
  }'

# 2. 验证事件在Kafka中
kubectl exec -it kafka-0 -n messaging -- kafka-console-consumer.sh \
  --topic cart-events \
  --bootstrap-server localhost:9092 \
  --from-beginning --max-messages 1

# 3. 检查事件处理
kubectl logs -l app=product-service | grep "cart-item-added"
```

#### 预期结果
- [ ] 所有微服务Pod正常运行
- [ ] API端点返回正确响应
- [ ] 数据库连接和数据持久化正常
- [ ] 事件发布和订阅功能正常
- [ ] 服务间通信正常

---

## Phase 4: 可观测性测试

### 4.1 监控系统测试

#### 部署Prometheus和Grafana
```bash
# 1. 安装Prometheus
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  -f k8s/monitoring/prometheus-values.yaml \
  -n monitoring --create-namespace

# 2. 验证Prometheus
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring &
# 访问 http://localhost:9090

# 3. 验证Grafana
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring &
# 访问 http://localhost:3000 (admin/prom-operator)
```

#### 监控指标测试
```bash
# 1. 检查服务指标收集
curl http://localhost:9090/api/v1/query?query=up

# 2. 验证自定义业务指标
curl http://localhost:9090/api/v1/query?query=cart_items_total

# 3. 检查告警规则
curl http://localhost:9090/api/v1/rules

# 4. 触发测试告警
kubectl run load-test --image=busybox --rm -it -- sh
# 在容器内执行高CPU负载
while true; do echo "load test"; done
```

### 4.2 日志聚合测试

#### 部署ELK Stack
```bash
# 1. 部署Elasticsearch
kubectl apply -f k8s/logging/elasticsearch.yaml

# 2. 部署Fluentd
kubectl apply -f k8s/logging/fluentd.yaml

# 3. 验证日志收集
kubectl port-forward svc/elasticsearch 9200:9200 -n logging &

# 4. 查询日志
curl http://localhost:9200/_search?q=cart-service
```

### 4.3 分布式追踪测试

#### 部署Jaeger
```bash
# 1. 部署Jaeger
kubectl apply -f k8s/tracing/jaeger.yaml

# 2. 部署OpenTelemetry Collector
kubectl apply -f k8s/tracing/opentelemetry-collector.yaml

# 3. 验证追踪数据
kubectl port-forward svc/jaeger-query 16686:16686 -n tracing &
# 访问 http://localhost:16686
```

#### 追踪测试
```bash
# 1. 执行一次完整的用户操作流程
# 创建用户 -> 查看产品 -> 添加到购物车

# 2. 在Jaeger UI中查看追踪链路
# 搜索服务：cart-service
# 验证完整的调用链路
```

#### 预期结果
- [ ] Prometheus收集到所有服务指标
- [ ] Grafana Dashboard显示监控数据
- [ ] 告警规则配置正确并能触发
- [ ] 日志正确聚合到Elasticsearch
- [ ] 分布式追踪链路完整

---

## Phase 5: CI/CD流水线测试

### 5.1 GitLab CI流水线测试

#### 准备GitLab环境
```bash
# 1. 配置GitLab Runner (如果使用自托管)
# 或确认GitLab.com shared runners可用

# 2. 设置CI/CD变量
# 在GitLab项目设置中配置：
# HARBOR_USERNAME, HARBOR_PASSWORD
# KUBECONFIG_CONTENT
# AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
```

#### 触发CI/CD测试
```bash
# 1. 提交代码触发流水线
git checkout -b test-ci-cd
echo "# Test CI/CD" >> README.md
git add README.md
git commit -m "Test CI/CD pipeline"
git push origin test-ci-cd

# 2. 创建Merge Request
# 在GitLab Web界面创建MR

# 3. 监控流水线执行
# 在GitLab CI/CD -> Pipelines 查看执行状态
```

### 5.2 ArgoCD GitOps测试

#### 部署ArgoCD
```bash
# 1. 安装ArgoCD
kubectl apply -f k8s/argocd/argocd-install.yaml

# 2. 获取管理员密码
kubectl get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" -n argocd | base64 -d

# 3. 访问ArgoCD UI
kubectl port-forward svc/argocd-server 8080:80 -n argocd &
# 访问 http://localhost:8080 (admin/上面获取的密码)
```

#### GitOps部署测试
```bash
# 1. 创建Application
kubectl apply -f k8s/argocd/applications.yaml

# 2. 验证自动同步
# 修改k8s配置文件并提交
git checkout main
sed -i 's/replicas: 2/replicas: 3/' k8s/apps/cart-service.yaml
git add .
git commit -m "Scale cart service to 3 replicas"
git push origin main

# 3. 在ArgoCD UI中观察自动同步
```

### 5.3 蓝绿部署测试

#### 部署Argo Rollouts
```bash
# 1. 安装Argo Rollouts
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# 2. 应用蓝绿部署策略
kubectl apply -f k8s/deployment-strategies/blue-green.yaml
```

#### 蓝绿部署流程测试
```bash
# 1. 触发新版本部署
kubectl patch rollout cart-service-rollout \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"cart-service","image":"cart-service:v2.0"}]}}}}' \
  -n production

# 2. 监控部署状态
kubectl argo rollouts get rollout cart-service-rollout -n production --watch

# 3. 验证分析结果
kubectl argo rollouts describe rollout cart-service-rollout -n production
```

#### 预期结果
- [ ] GitLab CI流水线全部阶段通过
- [ ] 代码质量检查、安全扫描无问题
- [ ] 镜像成功构建并推送到Harbor
- [ ] ArgoCD自动同步配置变更
- [ ] 蓝绿部署策略正确执行

---

## 性能和负载测试

### 负载测试

#### API负载测试
```bash
# 使用k6进行API负载测试
cat > load-test.js << 'EOF'
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 100 },
    { duration: '5m', target: 100 },
    { duration: '2m', target: 200 },
    { duration: '5m', target: 200 },
    { duration: '2m', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<2000'],
    http_req_failed: ['rate<0.1'],
  },
};

export default function() {
  let responses = http.batch([
    ['GET', 'http://api.test.ecommerce.com/api/products'],
    ['GET', 'http://api.test.ecommerce.com/api/cart/1'],
  ]);
  
  check(responses[0], {
    'products status is 200': (r) => r.status === 200,
  });
  
  sleep(1);
}
EOF

k6 run load-test.js
```

#### 数据库性能测试
```bash
# 使用pgbench测试数据库性能
kubectl exec -it $(kubectl get pod -l app=postgres -o jsonpath='{.items[0].metadata.name}') -- \
  pgbench -i -s 10 ecommerce

kubectl exec -it $(kubectl get pod -l app=postgres -o jsonpath='{.items[0].metadata.name}') -- \
  pgbench -c 20 -j 4 -T 300 ecommerce
```

---

## 安全性测试

### 安全扫描

#### 容器镜像安全扫描
```bash
# 使用Trivy扫描镜像
trivy image cart-service:latest
trivy image product-service:latest
trivy image user-service:latest
```

#### 渗透测试
```bash
# 使用OWASP ZAP进行基础安全测试
docker run -t owasp/zap2docker-stable zap-baseline.py \
  -t http://api.test.ecommerce.com
```

#### 网络安全测试
```bash
# 测试服务间通信安全
kubectl exec -it test-pod -- nmap -p 80,443,8080 cart-service
kubectl exec -it test-pod -- curl -k https://cart-service/api/health
```

---

## 灾难恢复测试

### 备份恢复测试

#### 数据库备份恢复
```bash
# 1. 创建数据库备份
kubectl exec -it postgres-0 -- pg_dump -U postgres ecommerce > backup.sql

# 2. 模拟数据丢失
kubectl exec -it postgres-0 -- psql -U postgres -c "DROP DATABASE ecommerce;"

# 3. 恢复数据
kubectl exec -i postgres-0 -- psql -U postgres < backup.sql
```

#### 服务故障恢复测试
```bash
# 1. 模拟Pod故障
kubectl delete pod -l app=cart-service

# 2. 验证自动恢复
kubectl get pods -l app=cart-service -w

# 3. 模拟节点故障
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# 4. 验证Pod重新调度
kubectl get pods -o wide
```

---

## 测试报告模板

### 测试结果记录表

| 测试阶段 | 测试项目 | 状态 | 问题描述 | 解决方案 |
|---------|---------|------|----------|----------|
| Phase 1 | Terraform部署 | ✅/❌ |  |  |
| Phase 1 | EKS集群验证 | ✅/❌ |  |  |
| Phase 1 | 网络连通性 | ✅/❌ |  |  |
| Phase 2 | Keycloak认证 | ✅/❌ |  |  |
| Phase 2 | Vault秘钥管理 | ✅/❌ |  |  |
| Phase 2 | mTLS配置 | ✅/❌ |  |  |
| Phase 3 | 微服务部署 | ✅/❌ |  |  |
| Phase 3 | API功能测试 | ✅/❌ |  |  |
| Phase 3 | 事件驱动架构 | ✅/❌ |  |  |
| Phase 4 | 监控系统 | ✅/❌ |  |  |
| Phase 4 | 日志聚合 | ✅/❌ |  |  |
| Phase 4 | 分布式追踪 | ✅/❌ |  |  |
| Phase 5 | CI/CD流水线 | ✅/❌ |  |  |
| Phase 5 | GitOps部署 | ✅/❌ |  |  |
| Phase 5 | 蓝绿部署 | ✅/❌ |  |  |
| 性能测试 | API负载测试 | ✅/❌ |  |  |
| 性能测试 | 数据库性能 | ✅/❌ |  |  |
| 安全测试 | 镜像扫描 | ✅/❌ |  |  |
| 安全测试 | 渗透测试 | ✅/❌ |  |  |
| 灾难恢复 | 备份恢复 | ✅/❌ |  |  |

### 关键指标检查清单

#### 性能指标
- [ ] API响应时间P95 < 2秒
- [ ] API响应时间P99 < 5秒
- [ ] 错误率 < 1%
- [ ] 数据库连接池使用率 < 80%
- [ ] 缓存命中率 > 90%

#### 安全指标
- [ ] 所有服务间通信使用mTLS
- [ ] 无高危漏洞镜像
- [ ] 认证和授权正常工作
- [ ] 秘钥轮换机制正常

#### 可用性指标
- [ ] 服务自动恢复 < 30秒
- [ ] 滚动更新零宕机
- [ ] 数据备份和恢复成功
- [ ] 监控告警及时触发

---

## 紧急回滚程序

如果在测试过程中发现严重问题，请按以下步骤回滚：

### 应用回滚
```bash
# 1. 回滚到上一个版本
kubectl argo rollouts undo cart-service-rollout -n production

# 2. 或使用kubectl回滚
kubectl rollout undo deployment/cart-service -n production
```

### 基础设施回滚
```bash
# 1. 使用Terraform回滚
terraform plan -destroy
terraform apply -auto-approve

# 2. 或回滚到指定状态
terraform apply -target=module.eks -auto-approve
```

### 数据回滚
```bash
# 1. 从备份恢复数据库
kubectl exec -i postgres-0 -- psql -U postgres < backup.sql

# 2. 清理测试数据
kubectl exec -it postgres-0 -- psql -U postgres -c "DELETE FROM carts WHERE created_at > '2024-01-01';"
```

---

## 总结

该测试计划覆盖了从基础设施到应用的全栈测试，确保系统在生产环境中的稳定性和安全性。建议按顺序执行测试，并详细记录每个步骤的结果。

**重要提醒：**
1. 在生产环境操作前，务必在测试环境完成所有测试
2. 准备完整的回滚计划
3. 确保有经验丰富的运维人员在场
4. 在低峰期进行部署
5. 逐步放量，监控系统指标