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
  default     = "B_Standard_B1ms"
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