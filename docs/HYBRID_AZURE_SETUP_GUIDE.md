# Azure 混合测试环境部署指南（选项2）

## 概述

本指南详细介绍如何使用 Terraform 在 Azure 上部署云端基础设施，同时在本地运行应用程序，实现混合测试环境。

## 目录

1. [前提条件](#前提条件)
2. [Terraform 基础设施即代码](#terraform-基础设施即代码)
3. [手动部署步骤](#手动部署步骤)
4. [本地应用配置](#本地应用配置)
5. [连接和测试](#连接和测试)
6. [监控和日志](#监控和日志)
7. [成本优化](#成本优化)
8. [故障排除](#故障排除)

---

## 前提条件

### 工具安装

```bash
# 1. 安装 Terraform
# macOS
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Linux
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install terraform

# 验证安装
terraform --version

# 2. 安装 Azure CLI
# macOS
brew install azure-cli

# Linux
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# 3. 登录 Azure
az login
az account list --output table
az account set --subscription "你的订阅ID"
```

### 目录结构

```
e-commerce-microservices-sample/
├── terraform/
│   ├── azure/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── providers.tf
│   │   ├── modules/
│   │   │   ├── database/
│   │   │   │   ├── main.tf
│   │   │   │   ├── variables.tf
│   │   │   │   └── outputs.tf
│   │   │   ├── redis/
│   │   │   │   ├── main.tf
│   │   │   │   ├── variables.tf
│   │   │   │   └── outputs.tf
│   │   │   └── monitoring/
│   │   │       ├── main.tf
│   │   │       ├── variables.tf
│   │   │       └── outputs.tf
│   │   └── environments/
│   │       ├── dev/
│   │       │   ├── terraform.tfvars
│   │       │   └── backend.tf
│   │       └── staging/
│   │           ├── terraform.tfvars
│   │           └── backend.tf
```

---

## Terraform 基础设施即代码

### 1. 提供者配置 (providers.tf)

```hcl
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
```

### 2. 变量定义 (variables.tf)

```hcl
variable "project_name" {
  description = "项目名称"
  type        = string
  default     = "ecommerce"
}

variable "environment" {
  description = "环境名称"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure 区域"
  type        = string
  default     = "East Asia"
}

variable "postgres_sku" {
  description = "PostgreSQL SKU"
  type        = string
  default     = "B_Gen5_1"
}

variable "redis_sku" {
  description = "Redis SKU"
  type = object({
    name     = string
    family   = string
    capacity = number
  })
  default = {
    name     = "Basic"
    family   = "C"
    capacity = 0
  }
}

variable "admin_username" {
  description = "数据库管理员用户名"
  type        = string
  default     = "postgres"
}

variable "allowed_ip_ranges" {
  description = "允许访问的 IP 范围"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default = {
    ManagedBy   = "Terraform"
    Environment = "Development"
    Project     = "E-commerce Microservices"
  }
}
```

### 3. 主配置文件 (main.tf)

```hcl
# 资源组
resource "azurerm_resource_group" "main" {
  name     = "${var.project_name}-${var.environment}-rg"
  location = var.location
  tags     = var.tags
}

# 随机密码生成
resource "random_password" "postgres" {
  length  = 20
  special = true
  upper   = true
  lower   = true
  numeric = true
}

resource "random_password" "redis" {
  length  = 32
  special = false
  upper   = true
  lower   = true
  numeric = true
}

# 虚拟网络
resource "azurerm_virtual_network" "main" {
  name                = "${var.project_name}-${var.environment}-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/16"]
  tags                = var.tags
}

# 子网
resource "azurerm_subnet" "database" {
  name                 = "database-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
  
  delegation {
    name = "postgres"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
    }
  }
}

resource "azurerm_subnet" "redis" {
  name                 = "redis-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
}

# PostgreSQL 灵活服务器
resource "azurerm_postgresql_flexible_server" "main" {
  name                = "${var.project_name}-${var.environment}-psql"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  administrator_login    = var.admin_username
  administrator_password = random_password.postgres.result
  
  sku_name   = "B_Standard_B1ms"
  version    = "15"
  
  storage_mb = 32768
  
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
  
  tags = var.tags
}

# PostgreSQL 数据库
resource "azurerm_postgresql_flexible_server_database" "main" {
  name      = var.project_name
  server_id = azurerm_postgresql_flexible_server.main.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

# PostgreSQL 防火墙规则（允许 Azure 服务）
resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# PostgreSQL 防火墙规则（允许本地 IP）
resource "azurerm_postgresql_flexible_server_firewall_rule" "local_ip" {
  for_each = toset(var.allowed_ip_ranges)
  
  name             = "AllowIP_${replace(each.value, ".", "_")}"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = each.value
  end_ip_address   = each.value
}

# Redis 缓存
resource "azurerm_redis_cache" "main" {
  name                = "${var.project_name}-${var.environment}-redis"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  sku_name = var.redis_sku.name
  family   = var.redis_sku.family
  capacity = var.redis_sku.capacity
  
  enable_non_ssl_port = false
  minimum_tls_version = "1.2"
  
  redis_configuration {
    enable_authentication = true
  }
  
  tags = var.tags
}

# Application Insights
resource "azurerm_application_insights" "main" {
  name                = "${var.project_name}-${var.environment}-insights"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  retention_in_days   = 30
  
  tags = var.tags
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.project_name}-${var.environment}-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  
  tags = var.tags
}

# Key Vault（存储敏感信息）
resource "azurerm_key_vault" "main" {
  name                = "${var.project_name}${var.environment}kv"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  
  purge_protection_enabled = false
  
  tags = var.tags
}

# 获取当前客户端配置
data "azurerm_client_config" "current" {}

# Key Vault 访问策略
resource "azurerm_key_vault_access_policy" "terraform" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Purge"
  ]
}

# 存储密码到 Key Vault
resource "azurerm_key_vault_secret" "postgres_password" {
  name         = "postgres-password"
  value        = random_password.postgres.result
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.terraform]
}

resource "azurerm_key_vault_secret" "redis_key" {
  name         = "redis-primary-key"
  value        = azurerm_redis_cache.main.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.terraform]
}
```

### 4. 输出配置 (outputs.tf)

```hcl
output "resource_group_name" {
  description = "资源组名称"
  value       = azurerm_resource_group.main.name
}

output "postgresql_server_name" {
  description = "PostgreSQL 服务器名称"
  value       = azurerm_postgresql_flexible_server.main.name
}

output "postgresql_fqdn" {
  description = "PostgreSQL 完全限定域名"
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "postgresql_connection_string" {
  description = "PostgreSQL 连接字符串"
  value       = "jdbc:postgresql://${azurerm_postgresql_flexible_server.main.fqdn}:5432/${azurerm_postgresql_flexible_server_database.main.name}?sslmode=require"
  sensitive   = true
}

output "redis_hostname" {
  description = "Redis 主机名"
  value       = azurerm_redis_cache.main.hostname
}

output "redis_ssl_port" {
  description = "Redis SSL 端口"
  value       = azurerm_redis_cache.main.ssl_port
}

output "redis_connection_string" {
  description = "Redis 连接字符串"
  value       = "rediss://:${azurerm_redis_cache.main.primary_access_key}@${azurerm_redis_cache.main.hostname}:${azurerm_redis_cache.main.ssl_port}"
  sensitive   = true
}

output "application_insights_key" {
  description = "Application Insights 检测密钥"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights 连接字符串"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "key_vault_uri" {
  description = "Key Vault URI"
  value       = azurerm_key_vault.main.vault_uri
}
```

### 5. 环境配置 (environments/dev/terraform.tfvars)

```hcl
project_name = "ecommerce"
environment  = "dev"
location     = "East Asia"

postgres_sku = "B_Gen5_1"

redis_sku = {
  name     = "Basic"
  family   = "C"
  capacity = 0
}

# 添加你的本地公网 IP
allowed_ip_ranges = [
  "YOUR_LOCAL_PUBLIC_IP"
]

tags = {
  ManagedBy   = "Terraform"
  Environment = "Development"
  Project     = "E-commerce Microservices"
  CostCenter  = "Development"
}
```

### 6. 后端配置 (environments/dev/backend.tf)

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstateecommerce"
    container_name       = "tfstate"
    key                  = "dev.terraform.tfstate"
  }
}
```

---

## 部署步骤

### 1. 创建 Terraform 状态存储

```bash
# 创建资源组
az group create --name terraform-state-rg --location eastasia

# 创建存储账户
az storage account create \
  --name tfstateecommerce \
  --resource-group terraform-state-rg \
  --location eastasia \
  --sku Standard_LRS

# 创建容器
az storage container create \
  --name tfstate \
  --account-name tfstateecommerce
```

### 2. 获取本地公网 IP

```bash
# 获取本地公网 IP
MY_IP=$(curl -s ifconfig.me)
echo "Your public IP: $MY_IP"

# 更新 terraform.tfvars 中的 allowed_ip_ranges
```

### 3. 初始化和部署

```bash
cd terraform/azure

# 初始化 Terraform
terraform init -backend-config=environments/dev/backend.tf

# 查看执行计划
terraform plan -var-file=environments/dev/terraform.tfvars

# 部署基础设施
terraform apply -var-file=environments/dev/terraform.tfvars -auto-approve

# 保存输出到文件
terraform output -json > infrastructure-outputs.json
```

### 4. 创建环境配置脚本

```bash
#!/bin/bash
# scripts/setup-azure-env.sh

# 从 Terraform 输出获取值
OUTPUTS=$(terraform output -json)

# 创建 .env 文件
cat > .env.azure-hybrid <<EOF
# Database Configuration
DATABASE_HOST=$(echo $OUTPUTS | jq -r .postgresql_fqdn.value)
DATABASE_NAME=$(echo $OUTPUTS | jq -r .postgresql_server_name.value | cut -d'-' -f1)
DATABASE_USER=${DATABASE_USER:-postgres}
DATABASE_PASSWORD=$(az keyvault secret show --vault-name $(echo $OUTPUTS | jq -r .key_vault_uri.value | cut -d'/' -f3 | cut -d'.' -f1) --name postgres-password --query value -o tsv)
DATABASE_URL="jdbc:postgresql://\${DATABASE_HOST}:5432/\${DATABASE_NAME}?sslmode=require"

# Redis Configuration
REDIS_HOST=$(echo $OUTPUTS | jq -r .redis_hostname.value)
REDIS_PORT=$(echo $OUTPUTS | jq -r .redis_ssl_port.value)
REDIS_PASSWORD=$(az keyvault secret show --vault-name $(echo $OUTPUTS | jq -r .key_vault_uri.value | cut -d'/' -f3 | cut -d'.' -f1) --name redis-primary-key --query value -o tsv)
REDIS_SSL=true

# Application Insights
APPLICATIONINSIGHTS_CONNECTION_STRING=$(echo $OUTPUTS | jq -r .application_insights_connection_string.value)

# Spring Profile
SPRING_PROFILES_ACTIVE=azure-hybrid
EOF

echo "Environment configuration saved to .env.azure-hybrid"
```

---

## 本地应用配置

### 1. Spring Boot 配置 (application-azure-hybrid.yml)

```yaml
spring:
  datasource:
    url: ${DATABASE_URL}
    username: ${DATABASE_USER}@${DATABASE_HOST}
    password: ${DATABASE_PASSWORD}
    hikari:
      connection-timeout: 30000
      maximum-pool-size: 10
      connection-test-query: SELECT 1
  
  redis:
    host: ${REDIS_HOST}
    port: ${REDIS_PORT}
    password: ${REDIS_PASSWORD}
    ssl: ${REDIS_SSL:true}
    timeout: 2000ms
    lettuce:
      pool:
        max-active: 8
        max-idle: 8
        min-idle: 0

  cloud:
    azure:
      applicationinsights:
        enabled: true
        connection-string: ${APPLICATIONINSIGHTS_CONNECTION_STRING}

management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  metrics:
    export:
      prometheus:
        enabled: true

logging:
  level:
    root: INFO
    com.example: DEBUG
    org.springframework.cloud.azure: DEBUG
```

### 2. Docker Compose 配置 (docker-compose.azure.yml)

```yaml
version: '3.8'

services:
  cart-service:
    build:
      context: ./cart-cna-microservice
      args:
        - SPRING_PROFILES_ACTIVE=azure-hybrid
    image: cart-service:azure-hybrid
    container_name: cart-service-azure
    ports:
      - "8081:8080"
    env_file:
      - .env.azure-hybrid
    environment:
      - JVM_OPTS=-Xmx512m -Xms256m
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/actuator/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - ecommerce-network

  product-service:
    build:
      context: ./products-cna-microservice
      args:
        - SPRING_PROFILES_ACTIVE=azure-hybrid
    image: product-service:azure-hybrid
    container_name: product-service-azure
    ports:
      - "8082:8080"
    env_file:
      - .env.azure-hybrid
    environment:
      - JVM_OPTS=-Xmx512m -Xms256m
    networks:
      - ecommerce-network

  user-service:
    build:
      context: ./users-cna-microservice
      args:
        - SPRING_PROFILES_ACTIVE=azure-hybrid
    image: user-service:azure-hybrid
    container_name: user-service-azure
    ports:
      - "8083:8080"
    env_file:
      - .env.azure-hybrid
    environment:
      - JVM_OPTS=-Xmx512m -Xms256m
    networks:
      - ecommerce-network

networks:
  ecommerce-network:
    driver: bridge
```

### 3. 启动脚本 (scripts/start-azure-hybrid.sh)

```bash
#!/bin/bash
set -e

echo "🚀 Starting Azure Hybrid Environment..."

# 检查环境文件
if [ ! -f .env.azure-hybrid ]; then
    echo "❌ .env.azure-hybrid not found. Run setup-azure-env.sh first."
    exit 1
fi

# 加载环境变量
export $(cat .env.azure-hybrid | grep -v '^#' | xargs)

# 测试数据库连接
echo "🔍 Testing database connection..."
docker run --rm \
  -e PGPASSWORD=$DATABASE_PASSWORD \
  postgres:15 \
  psql "host=$DATABASE_HOST port=5432 dbname=$DATABASE_NAME user=$DATABASE_USER@${DATABASE_HOST%%.*} sslmode=require" \
  -c "SELECT version();" || { echo "❌ Database connection failed"; exit 1; }

# 测试 Redis 连接
echo "🔍 Testing Redis connection..."
docker run --rm redis:7 \
  redis-cli -h $REDIS_HOST -p $REDIS_PORT -a $REDIS_PASSWORD --tls ping || \
  { echo "❌ Redis connection failed"; exit 1; }

# 构建和启动服务
echo "🏗️ Building services..."
docker-compose -f docker-compose.azure.yml build

echo "🚀 Starting services..."
docker-compose -f docker-compose.azure.yml up -d

# 等待服务启动
echo "⏳ Waiting for services to be ready..."
sleep 30

# 健康检查
echo "🏥 Performing health checks..."
services=("cart-service:8081" "product-service:8082" "user-service:8083")

for service in "${services[@]}"; do
    IFS=':' read -r name port <<< "$service"
    echo -n "Checking $name... "
    if curl -f http://localhost:$port/actuator/health > /dev/null 2>&1; then
        echo "✅"
    else
        echo "❌"
    fi
done

echo "🎉 Azure Hybrid Environment is ready!"
echo ""
echo "📊 Monitoring:"
echo "  - Application Insights: https://portal.azure.com"
echo "  - Local endpoints:"
echo "    - Cart Service: http://localhost:8081"
echo "    - Product Service: http://localhost:8082"
echo "    - User Service: http://localhost:8083"
```

---

## 测试和验证

### 1. 功能测试脚本 (scripts/test-azure-hybrid.sh)

```bash
#!/bin/bash

echo "🧪 Running Azure Hybrid Tests..."

# API 测试函数
test_api() {
    local service=$1
    local port=$2
    local endpoint=$3
    local method=$4
    local data=$5
    
    echo -n "Testing $service $endpoint... "
    
    if [ "$method" = "GET" ]; then
        response=$(curl -s -w "\n%{http_code}" http://localhost:$port$endpoint)
    else
        response=$(curl -s -w "\n%{http_code}" -X $method \
            -H "Content-Type: application/json" \
            -d "$data" \
            http://localhost:$port$endpoint)
    fi
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [[ $http_code -ge 200 && $http_code -lt 300 ]]; then
        echo "✅ ($http_code)"
        return 0
    else
        echo "❌ ($http_code)"
        echo "Response: $body"
        return 1
    fi
}

# 测试各个服务
echo "📦 Cart Service Tests:"
test_api "Cart" 8081 "/actuator/health" "GET"
test_api "Cart" 8081 "/api/cart/items" "POST" '{"userId":1,"productId":1,"quantity":2}'

echo ""
echo "📦 Product Service Tests:"
test_api "Product" 8082 "/actuator/health" "GET"
test_api "Product" 8082 "/api/products" "GET"

echo ""
echo "📦 User Service Tests:"
test_api "User" 8083 "/actuator/health" "GET"
test_api "User" 8083 "/api/users/1" "GET"

echo ""
echo "✅ Tests completed!"
```

### 2. 性能测试 (scripts/perf-test-azure.sh)

```bash
#!/bin/bash

echo "🚀 Running performance tests..."

# 安装 k6（如果未安装）
if ! command -v k6 &> /dev/null; then
    echo "Installing k6..."
    brew install k6
fi

# k6 测试脚本
cat > k6-azure-test.js <<'EOF'
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '30s', target: 10 },
    { duration: '1m', target: 20 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.1'],
  },
};

export default function() {
  // 测试购物车服务
  let cartResponse = http.get('http://localhost:8081/actuator/health');
  check(cartResponse, {
    'cart service healthy': (r) => r.status === 200,
  });
  
  // 测试产品服务
  let productResponse = http.get('http://localhost:8082/api/products');
  check(productResponse, {
    'product service responds': (r) => r.status === 200,
  });
  
  sleep(1);
}
EOF

# 运行测试
k6 run k6-azure-test.js
```

---

## 监控和日志

### 1. 配置 Application Insights

```java
// 添加到 Spring Boot 应用
@Component
public class ApplicationInsightsConfig {
    
    @Value("${APPLICATIONINSIGHTS_CONNECTION_STRING}")
    private String connectionString;
    
    @Bean
    public TelemetryClient telemetryClient() {
        TelemetryConfiguration configuration = TelemetryConfiguration.createDefault();
        configuration.setConnectionString(connectionString);
        return new TelemetryClient(configuration);
    }
}
```

### 2. 自定义指标

```java
@RestController
public class MetricsController {
    
    private final TelemetryClient telemetryClient;
    
    @PostMapping("/api/cart/items")
    public ResponseEntity<?> addToCart(@RequestBody CartItem item) {
        // 记录自定义事件
        telemetryClient.trackEvent("AddToCart", 
            Map.of("userId", String.valueOf(item.getUserId()),
                   "productId", String.valueOf(item.getProductId())));
        
        // 记录自定义指标
        telemetryClient.trackMetric("CartItemQuantity", item.getQuantity());
        
        // 业务逻辑...
    }
}
```

### 3. 日志聚合查询

```bash
# 使用 Azure CLI 查询日志
az monitor app-insights query \
  --app $APP_INSIGHTS_NAME \
  --resource-group $RESOURCE_GROUP \
  --analytics-query "
    traces
    | where timestamp > ago(1h)
    | where severityLevel > 2
    | project timestamp, message, severityLevel
    | order by timestamp desc
    | limit 100
  "
```

---

## 成本优化

### 1. 自动关闭脚本 (scripts/azure-cost-control.sh)

```bash
#!/bin/bash

# 停止开发环境资源
stop_dev_resources() {
    echo "🛑 Stopping development resources..."
    
    # 停止 PostgreSQL
    az postgres flexible-server stop \
        --resource-group ecommerce-dev-rg \
        --name ecommerce-dev-psql
    
    echo "✅ Resources stopped"
}

# 启动开发环境资源
start_dev_resources() {
    echo "🚀 Starting development resources..."
    
    # 启动 PostgreSQL
    az postgres flexible-server start \
        --resource-group ecommerce-dev-rg \
        --name ecommerce-dev-psql
    
    echo "✅ Resources started"
}

# 检查时间（工作时间：9-18点）
current_hour=$(date +%H)
if [[ $current_hour -ge 18 || $current_hour -lt 9 ]]; then
    stop_dev_resources
else
    start_dev_resources
fi
```

### 2. 成本监控

```bash
# 创建成本预算
az consumption budget create \
  --amount 50 \
  --budget-name ecommerce-dev-budget \
  --category Cost \
  --time-grain Monthly \
  --start-date $(date +%Y-%m-01) \
  --end-date $(date -d "+1 year" +%Y-%m-01) \
  --resource-group ecommerce-dev-rg \
  --notifications-enabled true \
  --contact-emails your-email@example.com \
  --threshold 80
```

### 3. 资源标记策略

```hcl
# 在 Terraform 中添加成本中心标记
locals {
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    CostCenter  = "Development"
    Owner       = "DevTeam"
    AutoShutdown = "true"
    WorkingHours = "9-18"
  }
}
```

---

## 故障排除

### 常见问题

#### 1. 数据库连接失败

```bash
# 检查防火墙规则
az postgres flexible-server firewall-rule list \
  --resource-group ecommerce-dev-rg \
  --server-name ecommerce-dev-psql

# 添加当前 IP
MY_IP=$(curl -s ifconfig.me)
az postgres flexible-server firewall-rule create \
  --resource-group ecommerce-dev-rg \
  --server-name ecommerce-dev-psql \
  --name AllowMyIP \
  --start-ip-address $MY_IP \
  --end-ip-address $MY_IP
```

#### 2. Redis 连接问题

```bash
# 测试 Redis 连接
docker run -it --rm redis:7 redis-cli \
  -h <redis-hostname> \
  -p 6380 \
  -a <redis-password> \
  --tls \
  ping

# 检查 Redis 配置
az redis show \
  --resource-group ecommerce-dev-rg \
  --name ecommerce-dev-redis \
  --query "{hostname:hostname, sslPort:sslPort, nonSslPort:nonSslPort}"
```

#### 3. Application Insights 无数据

```bash
# 验证连接字符串
az monitor app-insights component show \
  --app ecommerce-dev-insights \
  --resource-group ecommerce-dev-rg \
  --query connectionString

# 检查应用日志
docker logs cart-service-azure | grep -i "applicationinsights"
```

#### 4. 性能问题

```bash
# 查看资源使用情况
az postgres flexible-server show \
  --resource-group ecommerce-dev-rg \
  --name ecommerce-dev-psql \
  --query "{cpu:sku.name, storage:storageSizeGb}"

# 升级 SKU（如需要）
az postgres flexible-server update \
  --resource-group ecommerce-dev-rg \
  --name ecommerce-dev-psql \
  --sku-name Standard_B2s
```

---

## 清理资源

### 完全清理

```bash
# 使用 Terraform 销毁所有资源
cd terraform/azure
terraform destroy -var-file=environments/dev/terraform.tfvars -auto-approve

# 或使用 Azure CLI
az group delete --name ecommerce-dev-rg --yes --no-wait
```

### 保留数据清理

```bash
# 导出数据
pg_dump -h <postgres-host> -U postgres@<server-name> -d ecommerce > backup.sql

# 仅删除计算资源，保留存储
terraform destroy -target=azurerm_redis_cache.main -auto-approve
```

---

## 成本估算

| 资源 | SKU | 月成本（估算） |
|-----|-----|-------------|
| PostgreSQL Flexible Server | B_Standard_B1ms | ~$15 |
| Redis Cache | Basic C0 | ~$16 |
| Application Insights | 基础（5GB/月） | ~$3 |
| Log Analytics | 按使用付费 | ~$5 |
| Key Vault | 标准 | ~$0.5 |
| **总计** | | **~$40/月** |

*注：实际成本可能因使用量和区域而异*

---

## 最佳实践

1. **安全性**
   - 使用 Key Vault 存储敏感信息
   - 启用 SSL/TLS 连接
   - 定期轮换密码
   - 使用托管身份（Managed Identity）

2. **可靠性**
   - 配置自动备份
   - 实现重试逻辑
   - 使用健康检查
   - 配置警报

3. **性能**
   - 使用连接池
   - 启用查询缓存
   - 监控慢查询
   - 适当的资源大小

4. **成本**
   - 使用自动关闭
   - 选择合适的 SKU
   - 监控使用情况
   - 定期审查资源

---

## 参考链接

- [Terraform Azure Provider 文档](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure PostgreSQL Flexible Server](https://docs.microsoft.com/azure/postgresql/flexible-server/)
- [Azure Cache for Redis](https://docs.microsoft.com/azure/azure-cache-for-redis/)
- [Application Insights](https://docs.microsoft.com/azure/azure-monitor/app/app-insights-overview)
- [Spring Cloud Azure](https://docs.microsoft.com/azure/developer/java/spring-framework/)