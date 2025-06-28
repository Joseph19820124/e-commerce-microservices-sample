# 获取当前客户端配置
data "azurerm_client_config" "current" {}

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

# PostgreSQL 灵活服务器
resource "azurerm_postgresql_flexible_server" "main" {
  name                = "${var.project_name}-${var.environment}-psql"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  administrator_login    = var.admin_username
  administrator_password = random_password.postgres.result
  
  sku_name   = var.postgres_sku
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