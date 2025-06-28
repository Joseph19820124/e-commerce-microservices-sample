# Azure Terraform 执行指南

## 快速开始

### 自动化部署（推荐）

```bash
# 在项目根目录执行
./scripts/deploy-azure-terraform.sh
```

### 手动部署步骤

#### 1. 安装 Azure CLI（如果尚未安装）

```bash
# macOS
brew install azure-cli

# 验证安装
az --version
```

#### 2. 登录 Azure

```bash
# 登录（会打开浏览器）
az login

# 查看账户信息
az account show
```

#### 3. 执行 Terraform 部署

```bash
# 进入 Terraform 目录
cd terraform/azure

# 初始化（如果尚未完成）
terraform init

# 查看执行计划
terraform plan -var-file=environments/dev/terraform.tfvars

# 应用配置（创建资源）
terraform apply -var-file=environments/dev/terraform.tfvars
```

#### 4. 获取连接信息

```bash
# 查看所有输出
terraform output

# 查看特定输出（不显示敏感信息）
terraform output postgresql_fqdn
terraform output redis_hostname

# 查看敏感信息
terraform output -raw postgresql_admin_password
terraform output -raw redis_primary_access_key
```

#### 5. 创建环境配置文件

```bash
# 在项目根目录创建 .env.azure-hybrid
cd ../..

# 使用 Terraform 输出创建环境文件
cat > .env.azure-hybrid <<EOF
DATABASE_HOST=$(cd terraform/azure && terraform output -raw postgresql_fqdn)
DATABASE_USER=$(cd terraform/azure && terraform output -raw postgresql_admin_username)
DATABASE_PASSWORD=$(cd terraform/azure && terraform output -raw postgresql_admin_password)
DATABASE_URL="jdbc:postgresql://\${DATABASE_HOST}:5432/ecommerce?sslmode=require"
REDIS_HOST=$(cd terraform/azure && terraform output -raw redis_hostname)
REDIS_PORT=$(cd terraform/azure && terraform output -raw redis_ssl_port)
REDIS_PASSWORD=$(cd terraform/azure && terraform output -raw redis_primary_access_key)
REDIS_SSL=true
APPLICATIONINSIGHTS_CONNECTION_STRING=$(cd terraform/azure && terraform output -raw application_insights_connection_string)
SPRING_PROFILES_ACTIVE=azure-hybrid
EOF
```

## 预期结果

部署完成后，你将获得：

### Azure 资源

- **资源组**: `ecommerce-dev-rg`
- **PostgreSQL 服务器**: `ecommerce-dev-psql`
- **Redis 缓存**: `ecommerce-dev-redis`
- **Application Insights**: `ecommerce-dev-insights`
- **Log Analytics**: `ecommerce-dev-logs`

### 成本估算

| 资源 | SKU | 月成本（估算） |
|-----|-----|-------------|
| PostgreSQL | B_Standard_B1ms | ~$15 |
| Redis | Basic C0 | ~$16 |
| Application Insights | 基础 | ~$3 |
| Log Analytics | 按用量 | ~$5 |
| **总计** | | **~$39/月** |

### 连接信息

- **数据库端点**: `ecommerce-dev-psql.postgres.database.azure.com`
- **Redis 端点**: `ecommerce-dev-redis.redis.cache.windows.net:6380`
- **监控**: Azure Portal 中的 Application Insights

## 验证部署

### 1. 检查资源状态

```bash
# 列出资源组中的所有资源
az resource list --resource-group ecommerce-dev-rg --output table
```

### 2. 测试数据库连接

```bash
# 使用 psql 测试连接
psql "host=ecommerce-dev-psql.postgres.database.azure.com port=5432 dbname=ecommerce user=postgres@ecommerce-dev-psql sslmode=require"
```

### 3. 测试 Redis 连接

```bash
# 使用 redis-cli 测试连接
redis-cli -h ecommerce-dev-redis.redis.cache.windows.net -p 6380 -a <password> --tls ping
```

## 启动本地应用

### 1. 创建 Docker Compose 配置

```yaml
# docker-compose.azure.yml
version: '3.8'
services:
  cart-service:
    build: ./cart-cna-microservice
    ports:
      - "8081:8080"
    env_file:
      - .env.azure-hybrid
    environment:
      - SPRING_PROFILES_ACTIVE=azure-hybrid
```

### 2. 启动服务

```bash
# 构建并启动
docker-compose -f docker-compose.azure.yml up --build
```

## 故障排除

### 常见问题

#### 1. Azure CLI 未找到

```bash
# 检查路径
which az

# 如果使用 pip 安装，可能需要添加到 PATH
export PATH="$PATH:/Users/$USER/.local/bin"
```

#### 2. 权限不足

```bash
# 检查 Azure 权限
az role assignment list --assignee $(az account show --query user.name -o tsv)
```

#### 3. IP 访问被拒绝

```bash
# 检查当前 IP
curl ifconfig.me

# 更新防火墙规则
az postgres flexible-server firewall-rule create \
  --resource-group ecommerce-dev-rg \
  --name ecommerce-dev-psql \
  --rule-name AllowMyIP \
  --start-ip-address YOUR_IP \
  --end-ip-address YOUR_IP
```

## 清理资源

### 销毁所有资源

```bash
# 使用 Terraform 销毁
cd terraform/azure
terraform destroy -var-file=environments/dev/terraform.tfvars

# 或直接删除资源组
az group delete --name ecommerce-dev-rg --yes --no-wait
```

## 下一步

1. **配置应用**: 使用生成的 `.env.azure-hybrid` 配置本地应用
2. **监控设置**: 在 Azure Portal 配置告警和仪表板
3. **CI/CD 集成**: 将 Terraform 集成到你的 CI/CD 流水线
4. **安全加固**: 配置更严格的网络访问控制

## 支持

如遇问题：
1. 查看 [故障排除指南](docs/TROUBLESHOOTING_GUIDE.md)
2. 检查 [Azure 文档](https://docs.microsoft.com/azure/)
3. 查看 Terraform 日志和 Azure Portal 中的活动日志