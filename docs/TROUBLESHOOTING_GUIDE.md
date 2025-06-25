# E-Commerce Microservices Troubleshooting Guide

## 快速诊断命令

### 系统状态检查
```bash
# 运行完整健康检查
./scripts/health-check.sh production

# 运行自动化测试
./scripts/automated-testing.sh all production

# 快速集群状态检查
kubectl get nodes
kubectl get pods -A | grep -v Running
kubectl top nodes
kubectl get events --sort-by='.lastTimestamp' | tail -20
```

---

## Phase 1: 基础设施问题排查

### Terraform部署失败

#### 问题症状
- `terraform apply` 失败
- AWS资源创建错误
- 网络配置问题

#### 排查步骤
```bash
# 1. 检查Terraform状态
cd infra/terraform/environments/dev
terraform state list
terraform state show <resource_name>

# 2. 检查AWS凭证
aws sts get-caller-identity
aws ec2 describe-regions

# 3. 检查资源限制
aws ec2 describe-account-attributes
aws servicequotas get-service-quota --service-code ec2 --quota-code L-0263D0A3

# 4. 验证网络配置
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=ecommerce-*"
aws ec2 describe-subnets --filters "Name=vpc-id,Values=<vpc-id>"
```

#### 常见解决方案
```bash
# 重新初始化Terraform
terraform init -reconfigure

# 导入现有资源
terraform import aws_vpc.main <vpc-id>

# 清理失败状态
terraform state rm <failed_resource>
terraform apply -target=<specific_resource>
```

### EKS集群问题

#### 问题症状
- 无法连接到集群
- 节点不加入集群
- Pod无法调度

#### 排查步骤
```bash
# 1. 检查EKS集群状态
aws eks describe-cluster --name ecommerce-dev-cluster
aws eks list-nodegroups --cluster-name ecommerce-dev-cluster

# 2. 更新kubeconfig
aws eks update-kubeconfig --region us-west-2 --name ecommerce-dev-cluster

# 3. 检查节点状态
kubectl get nodes -o wide
kubectl describe node <node-name>

# 4. 检查网络插件
kubectl get pods -n kube-system -l k8s-app=aws-node
kubectl logs -l k8s-app=aws-node -n kube-system
```

#### 常见解决方案
```bash
# 重启网络插件
kubectl rollout restart daemonset aws-node -n kube-system

# 检查IAM权限
aws iam get-role --role-name eksWorkerNodeInstanceRole

# 重新创建节点组
aws eks delete-nodegroup --cluster-name ecommerce-dev-cluster --nodegroup-name workers
# 然后重新apply terraform
```

---

## Phase 2: 安全组件问题排查

### Keycloak无法启动

#### 问题症状
- Keycloak Pod一直处于CrashLoopBackOff
- 无法访问管理控制台
- 数据库连接失败

#### 排查步骤
```bash
# 1. 检查Pod状态和日志
kubectl get pods -l app=keycloak -n security
kubectl logs -l app=keycloak -n security --previous
kubectl describe pod <keycloak-pod> -n security

# 2. 检查数据库连接
kubectl get secret keycloak-db-secret -n security -o yaml
kubectl run db-test --image=postgres:15 --rm -it -- psql -h <db-host> -U <user> -d keycloak

# 3. 检查配置
kubectl get configmap keycloak-config -n security -o yaml
```

#### 常见解决方案
```bash
# 重置Keycloak数据库
kubectl exec -it postgres-0 -- psql -U postgres -c "DROP DATABASE IF EXISTS keycloak;"
kubectl exec -it postgres-0 -- psql -U postgres -c "CREATE DATABASE keycloak;"

# 重新部署Keycloak
kubectl delete pod -l app=keycloak -n security
kubectl apply -f k8s/security/keycloak.yaml

# 检查资源限制
kubectl get pod <keycloak-pod> -n security -o yaml | grep -A 10 resources
```

### Vault密封状态

#### 问题症状
- Vault处于密封状态
- 无法访问秘钥
- Pods无法获取秘钥

#### 排查步骤
```bash
# 1. 检查Vault状态
kubectl exec -it vault-0 -n security -- vault status

# 2. 检查初始化状态
kubectl logs vault-0 -n security | grep -i "init\|unseal"

# 3. 检查集群状态
kubectl exec -it vault-0 -n security -- vault operator raft list-peers
```

#### 解决方案
```bash
# 1. 解封Vault
kubectl exec -it vault-0 -n security -- vault operator unseal <unseal-key-1>
kubectl exec -it vault-0 -n security -- vault operator unseal <unseal-key-2>
kubectl exec -it vault-0 -n security -- vault operator unseal <unseal-key-3>

# 2. 如果需要重新初始化
kubectl exec -it vault-0 -n security -- vault operator init

# 3. 恢复自动解封（如果配置了）
kubectl apply -f k8s/security/vault-auto-unseal.yaml
```

### mTLS证书问题

#### 问题症状
- 服务间通信失败
- 证书验证错误
- Istio sidecar启动失败

#### 排查步骤
```bash
# 1. 检查Istio安装
kubectl get pods -n istio-system
istioctl version

# 2. 检查证书状态
kubectl exec -it <pod-name> -c istio-proxy -- openssl s_client -connect <service>:443 -verify_return_error

# 3. 检查mTLS策略
kubectl get peerauthentication -A
kubectl get destinationrule -A

# 4. 检查代理配置
istioctl proxy-config cluster <pod-name>
istioctl proxy-config secret <pod-name>
```

#### 解决方案
```bash
# 重启Istio组件
kubectl rollout restart deployment/istiod -n istio-system

# 重新生成证书
kubectl delete secret cacerts -n istio-system
kubectl create secret generic cacerts -n istio-system \
  --from-file=root-cert.pem \
  --from-file=cert-chain.pem \
  --from-file=ca-cert.pem \
  --from-file=ca-key.pem

# 重启受影响的Pod
kubectl rollout restart deployment/<service-name>
```

---

## Phase 3: 微服务问题排查

### 应用Pod启动失败

#### 问题症状
- Pod处于ImagePullBackOff状态
- 应用启动异常
- 健康检查失败

#### 排查步骤
```bash
# 1. 检查Pod状态
kubectl get pods -l app=cart-service
kubectl describe pod <pod-name>
kubectl logs <pod-name> --previous

# 2. 检查镜像
docker pull <image-name>
kubectl get events --field-selector involvedObject.name=<pod-name>

# 3. 检查配置
kubectl get configmap <app-config> -o yaml
kubectl get secret <app-secret> -o yaml
```

#### 解决方案
```bash
# 重新构建和推送镜像
docker build -t <image-name>:latest .
docker push <image-name>:latest

# 更新部署
kubectl set image deployment/cart-service cart-service=<new-image>

# 检查资源限制
kubectl get pod <pod-name> -o yaml | grep -A 10 resources
```

### 数据库连接问题

#### 问题症状
- 应用无法连接数据库
- 连接池耗尽
- 数据库锁等待

#### 排查步骤
```bash
# 1. 检查数据库状态
kubectl get pods -l app=postgres
kubectl logs -l app=postgres

# 2. 测试连接
kubectl run db-test --image=postgres:15 --rm -it -- \
  psql -h postgres-service -U postgres -d ecommerce

# 3. 检查连接池配置
kubectl logs <app-pod> | grep -i "connection\|pool\|database"

# 4. 监控数据库性能
kubectl exec -it postgres-0 -- psql -U postgres -c "
  SELECT datname, numbackends, xact_commit, xact_rollback 
  FROM pg_stat_database WHERE datname = 'ecommerce';
"
```

#### 解决方案
```bash
# 重启数据库连接
kubectl rollout restart deployment/cart-service

# 清理数据库连接
kubectl exec -it postgres-0 -- psql -U postgres -c "
  SELECT pg_terminate_backend(pid) 
  FROM pg_stat_activity 
  WHERE datname = 'ecommerce' AND state = 'idle';
"

# 优化连接池配置
kubectl patch configmap app-config --patch '
data:
  spring.datasource.hikari.maximum-pool-size: "20"
  spring.datasource.hikari.minimum-idle: "5"
'
```

### 事件系统问题

#### 问题症状
- Kafka消息堆积
- 消费者延迟
- 消息丢失

#### 排查步骤
```bash
# 1. 检查Kafka集群
kubectl get pods -l app=kafka -n messaging
kubectl logs kafka-0 -n messaging

# 2. 检查Topic状态
kubectl exec -it kafka-0 -n messaging -- kafka-topics.sh \
  --list --bootstrap-server localhost:9092

# 3. 监控消费者组
kubectl exec -it kafka-0 -n messaging -- kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 --list

kubectl exec -it kafka-0 -n messaging -- kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 --describe --group <group-name>
```

#### 解决方案
```bash
# 重置消费者偏移量
kubectl exec -it kafka-0 -n messaging -- kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 --group <group-name> \
  --reset-offsets --to-latest --all-topics --execute

# 增加分区数
kubectl exec -it kafka-0 -n messaging -- kafka-topics.sh \
  --alter --topic <topic-name> --partitions 6 \
  --bootstrap-server localhost:9092

# 清理日志
kubectl exec -it kafka-0 -n messaging -- kafka-log-dirs.sh \
  --bootstrap-server localhost:9092 --describe
```

---

## Phase 4: 可观测性问题排查

### Prometheus指标收集问题

#### 问题症状
- 某些服务指标缺失
- 监控Dashboard无数据
- 告警不触发

#### 排查步骤
```bash
# 1. 检查Prometheus状态
kubectl get pods -l app.kubernetes.io/name=prometheus -n monitoring
kubectl logs prometheus-kube-prometheus-prometheus-0 -n monitoring

# 2. 检查服务发现
kubectl get servicemonitor -n monitoring
kubectl get endpoints -l app=cart-service

# 3. 检查指标端点
kubectl port-forward svc/cart-service 8080:80 &
curl http://localhost:8080/actuator/prometheus

# 4. 验证Prometheus配置
kubectl get prometheus -n monitoring -o yaml
```

#### 解决方案
```bash
# 重新加载Prometheus配置
kubectl exec prometheus-kube-prometheus-prometheus-0 -n monitoring -- \
  curl -X POST http://localhost:9090/-/reload

# 重启Prometheus
kubectl rollout restart statefulset/prometheus-kube-prometheus-prometheus -n monitoring

# 检查标签选择器
kubectl label service cart-service app.kubernetes.io/name=cart-service
```

### Grafana Dashboard问题

#### 问题症状
- Dashboard显示"No data"
- 图表加载缓慢
- 查询错误

#### 排查步骤
```bash
# 1. 检查Grafana状态
kubectl get pods -l app.kubernetes.io/name=grafana -n monitoring
kubectl logs <grafana-pod> -n monitoring

# 2. 检查数据源连接
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring &
# 访问 http://localhost:3000，检查Data Sources

# 3. 验证PromQL查询
curl "http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090/api/v1/query?query=up"
```

#### 解决方案
```bash
# 重新导入Dashboard
kubectl apply -f k8s/monitoring/grafana-dashboards.yaml

# 重启Grafana
kubectl rollout restart deployment/prometheus-grafana -n monitoring

# 手动添加数据源
kubectl exec -it <grafana-pod> -n monitoring -- \
  grafana-cli admin reset-admin-password admin123
```

### 日志收集问题

#### 问题症状
- 日志未出现在Elasticsearch
- Fluentd Pod异常
- 日志格式错误

#### 排查步骤
```bash
# 1. 检查Fluentd状态
kubectl get pods -l app=fluentd -n logging
kubectl logs <fluentd-pod> -n logging

# 2. 检查Elasticsearch
kubectl get pods -l app=elasticsearch -n logging
curl "http://elasticsearch.logging.svc.cluster.local:9200/_cluster/health"

# 3. 验证日志路径
kubectl exec -it <fluentd-pod> -n logging -- ls -la /var/log/containers/
```

#### 解决方案
```bash
# 重启Fluentd
kubectl rollout restart daemonset/fluentd -n logging

# 清理Elasticsearch索引
curl -X DELETE "http://elasticsearch.logging.svc.cluster.local:9200/logstash-*"

# 更新Fluentd配置
kubectl apply -f k8s/logging/fluentd.yaml
```

---

## Phase 5: CI/CD问题排查

### GitLab CI流水线失败

#### 问题症状
- 构建步骤失败
- 镜像推送失败
- 部署超时

#### 排查步骤
```bash
# 1. 检查GitLab Runner状态
# 在GitLab项目中查看 Settings > CI/CD > Runners

# 2. 检查CI/CD变量
# 验证 HARBOR_USERNAME, HARBOR_PASSWORD, KUBECONFIG_CONTENT等

# 3. 本地测试构建
docker build -t test-image .
docker run --rm test-image

# 4. 检查Harbor连接
docker login harbor.ecommerce.com -u <username>
```

#### 解决方案
```bash
# 更新CI/CD变量
# 在GitLab项目中 Settings > CI/CD > Variables

# 重新注册Runner
gitlab-runner register --url <gitlab-url> --registration-token <token>

# 清理Docker构建缓存
docker system prune -a
```

### ArgoCD同步问题

#### 问题症状
- Application处于OutOfSync状态
- 自动同步不工作
- 健康检查失败

#### 排查步骤
```bash
# 1. 检查ArgoCD状态
kubectl get pods -n argocd
kubectl logs -l app.kubernetes.io/name=argocd-server -n argocd

# 2. 检查Application状态
kubectl get applications -n argocd
kubectl describe application ecommerce-production -n argocd

# 3. 检查同步策略
argocd app get ecommerce-production
argocd app diff ecommerce-production
```

#### 解决方案
```bash
# 手动同步
argocd app sync ecommerce-production

# 强制刷新
argocd app refresh ecommerce-production --hard

# 重置同步状态
argocd app patch ecommerce-production --patch '{"operation":{"sync":{"syncStrategy":{"force":true}}}}'
```

### 蓝绿部署问题

#### 问题症状
- Rollout卡在进行中状态
- 分析失败
- 流量未切换

#### 排查步骤
```bash
# 1. 检查Rollout状态
kubectl argo rollouts get rollout cart-service-rollout -n production
kubectl argo rollouts describe rollout cart-service-rollout -n production

# 2. 检查分析结果
kubectl get analysisruns -n production
kubectl describe analysisrun <analysis-run-name> -n production

# 3. 检查Prometheus指标
curl "http://prometheus.monitoring.svc.cluster.local:9090/api/v1/query?query=http_requests_total"
```

#### 解决方案
```bash
# 手动促进部署
kubectl argo rollouts promote cart-service-rollout -n production

# 中止部署
kubectl argo rollouts abort cart-service-rollout -n production

# 回滚到上一版本
kubectl argo rollouts undo cart-service-rollout -n production
```

---

## 性能问题排查

### 高CPU使用率

#### 排查步骤
```bash
# 1. 检查Pod资源使用
kubectl top pods -A
kubectl describe pod <high-cpu-pod>

# 2. 分析应用性能
kubectl exec -it <pod-name> -- top
kubectl exec -it <pod-name> -- ps aux

# 3. 检查JVM性能（Java应用）
kubectl exec -it <pod-name> -- jstack <pid>
kubectl exec -it <pod-name> -- jstat -gc <pid>
```

#### 解决方案
```bash
# 增加CPU限制
kubectl patch deployment cart-service --patch '
spec:
  template:
    spec:
      containers:
      - name: cart-service
        resources:
          limits:
            cpu: "2000m"
          requests:
            cpu: "500m"
'

# 启用HPA
kubectl apply -f k8s/performance/optimization-configs.yaml
```

### 内存泄漏

#### 排查步骤
```bash
# 1. 监控内存使用趋势
kubectl top pod <pod-name> --containers

# 2. 生成内存转储（Java应用）
kubectl exec -it <pod-name> -- jcmd <pid> GC.run_finalization
kubectl exec -it <pod-name> -- jcmd <pid> VM.classloader_stats

# 3. 检查内存配置
kubectl get pod <pod-name> -o yaml | grep -A 10 resources
```

#### 解决方案
```bash
# 重启Pod
kubectl delete pod <pod-name>

# 调整内存限制
kubectl patch deployment cart-service --patch '
spec:
  template:
    spec:
      containers:
      - name: cart-service
        resources:
          limits:
            memory: "4Gi"
          requests:
            memory: "1Gi"
'
```

---

## 网络问题排查

### 服务间通信失败

#### 排查步骤
```bash
# 1. 检查Service和Endpoints
kubectl get svc
kubectl get endpoints

# 2. 测试网络连通性
kubectl run net-test --image=busybox --rm -it -- sh
# 在容器内执行
nslookup cart-service.default.svc.cluster.local
wget -qO- http://cart-service/actuator/health

# 3. 检查网络策略
kubectl get networkpolicy -A
```

#### 解决方案
```bash
# 重启网络插件
kubectl rollout restart daemonset aws-node -n kube-system

# 检查DNS配置
kubectl get configmap coredns -n kube-system -o yaml

# 临时放开网络策略
kubectl delete networkpolicy --all
```

---

## 数据备份和恢复

### 数据库备份

```bash
# 创建备份
kubectl exec -it postgres-0 -- pg_dump -U postgres ecommerce > backup-$(date +%Y%m%d).sql

# 恢复数据
kubectl exec -i postgres-0 -- psql -U postgres ecommerce < backup-20241225.sql
```

### 配置备份

```bash
# 备份所有配置
kubectl get all,configmap,secret,pv,pvc -A -o yaml > cluster-backup-$(date +%Y%m%d).yaml

# 备份特定命名空间
kubectl get all,configmap,secret -n production -o yaml > production-backup-$(date +%Y%m%d).yaml
```

---

## 紧急响应流程

### 生产环境故障

1. **立即响应**
   ```bash
   # 检查整体状态
   ./scripts/health-check.sh production
   
   # 查看最近事件
   kubectl get events --sort-by='.lastTimestamp' | tail -20
   ```

2. **隔离问题**
   ```bash
   # 停止流量到故障服务
   kubectl scale deployment <service-name> --replicas=0
   
   # 或切换到备用版本
   kubectl argo rollouts undo <rollout-name>
   ```

3. **收集信息**
   ```bash
   # 导出日志
   kubectl logs <pod-name> > incident-logs-$(date +%Y%m%d-%H%M).log
   
   # 导出配置
   kubectl get pod <pod-name> -o yaml > incident-config-$(date +%Y%m%d-%H%M).yaml
   ```

4. **恢复服务**
   ```bash
   # 回滚到上一版本
   kubectl rollout undo deployment/<service-name>
   
   # 或使用备份恢复
   kubectl apply -f backup-config.yaml
   ```

### 联系信息

- **Platform Team**: platform-team@company.com
- **Security Team**: security-team@company.com  
- **Database Team**: db-team@company.com
- **Emergency Hotline**: +1-xxx-xxx-xxxx

---

## 常用命令速查

### 快速诊断
```bash
# 集群整体状态
kubectl get nodes,pods -A | grep -v Running

# 资源使用情况
kubectl top nodes
kubectl top pods -A

# 最近事件
kubectl get events --sort-by='.lastTimestamp' -A | tail -20

# 失败的Pod
kubectl get pods -A --field-selector=status.phase!=Running
```

### 日志查看
```bash
# 实时日志
kubectl logs -f <pod-name>

# 上一次重启的日志
kubectl logs <pod-name> --previous

# 多个Pod的日志
kubectl logs -l app=cart-service

# 指定时间范围的日志
kubectl logs <pod-name> --since=1h
```

### 故障恢复
```bash
# 重启Deployment
kubectl rollout restart deployment/<name>

# 回滚到上一版本
kubectl rollout undo deployment/<name>

# 强制删除Pod
kubectl delete pod <pod-name> --force --grace-period=0

# 清理失败的Job
kubectl delete job --field-selector=status.successful=0
```

记住：**在生产环境操作时，务必先在测试环境验证解决方案！**