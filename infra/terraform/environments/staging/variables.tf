# General Variables
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "ecommerce-microservices"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "staging"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

# VPC Variables
variable "main_vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "public_subnets" {
  description = "List of public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "private_subnets" {
  description = "List of private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.1.10.0/24", "10.1.20.0/24"]
}

# EKS Variables
variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "node_instance_types" {
  description = "Instance types for EKS node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "desired_capacity" {
  description = "Desired number of nodes"
  type        = number
  default     = 3
}

variable "max_capacity" {
  description = "Maximum number of nodes"
  type        = number
  default     = 6
}

variable "min_capacity" {
  description = "Minimum number of nodes"
  type        = number
  default     = 2
}

# RDS Variables
variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15.4"
}

variable "postgres_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.small"
}

variable "postgres_allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 50
}

variable "postgres_max_allocated_storage" {
  description = "Maximum allocated storage in GB"
  type        = number
  default     = 200
}

variable "postgres_database_name" {
  description = "Name of the database"
  type        = string
  default     = "ecommerce"
}

variable "postgres_username" {
  description = "Master username"
  type        = string
  default     = "postgres"
}

variable "postgres_backup_retention" {
  description = "Backup retention period in days"
  type        = number
  default     = 14
}

variable "postgres_deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = true
}

variable "postgres_final_snapshot" {
  description = "Create final snapshot on deletion"
  type        = bool
  default     = true
}

variable "postgres_create_replica" {
  description = "Create read replica"
  type        = bool
  default     = true
}

# ElastiCache Variables
variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.small"
}

variable "redis_num_cache_nodes" {
  description = "Number of cache nodes"
  type        = number
  default     = 2
}

variable "redis_multi_az_enabled" {
  description = "Enable Multi-AZ"
  type        = bool
  default     = true
}

variable "redis_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.0"
}