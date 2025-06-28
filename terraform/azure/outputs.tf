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

output "postgresql_admin_username" {
  description = "PostgreSQL 管理员用户名"
  value       = azurerm_postgresql_flexible_server.main.administrator_login
}

output "postgresql_admin_password" {
  description = "PostgreSQL 管理员密码"
  value       = random_password.postgres.result
  sensitive   = true
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

output "redis_primary_access_key" {
  description = "Redis 主访问密钥"
  value       = azurerm_redis_cache.main.primary_access_key
  sensitive   = true
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