project_name = "ecommerce"
environment  = "dev"
location     = "East Asia"

postgres_sku = "B_Standard_B1ms"

redis_sku = {
  name     = "Basic"
  family   = "C"
  capacity = 0
}

# 暂时允许所有 IP 访问（生产环境应限制特定 IP）
allowed_ip_ranges = [
  "0.0.0.0"
]

tags = {
  ManagedBy   = "Terraform"
  Environment = "Development"
  Project     = "E-commerce Microservices"
  CostCenter  = "Development"
}