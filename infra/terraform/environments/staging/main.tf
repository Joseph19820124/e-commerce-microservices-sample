provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Environment = "staging"
      Project     = "ecommerce-microservices"
      ManagedBy   = "terraform"
    }
  }
}

# Generate random passwords
resource "random_password" "rds_password" {
  length  = 16
  special = true
}

resource "random_password" "redis_auth_token" {
  length  = 32
  special = false
}

# Store passwords in AWS Secrets Manager
resource "aws_secretsmanager_secret" "rds_password" {
  name = "${var.environment}-rds-password"
}

resource "aws_secretsmanager_secret_version" "rds_password" {
  secret_id     = aws_secretsmanager_secret.rds_password.id
  secret_string = random_password.rds_password.result
}

resource "aws_secretsmanager_secret" "redis_auth_token" {
  name = "${var.environment}-redis-auth-token"
}

resource "aws_secretsmanager_secret_version" "redis_auth_token" {
  secret_id     = aws_secretsmanager_secret.redis_auth_token.id
  secret_string = random_password.redis_auth_token.result
}

# VPC Module
module "vpc" {
  source = "../../modules/vpc"
  
  name            = "${var.project_name}-${var.environment}"
  region          = var.region
  main_vpc_cidr   = var.main_vpc_cidr
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
  
  enable_nat_gateway    = true
  enable_s3_endpoint    = true
  enable_vpc_endpoints  = true
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# EKS Module
module "eks" {
  source = "../../modules/eks"
  
  cluster_name         = "${var.project_name}-${var.environment}"
  kubernetes_version   = var.kubernetes_version
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = concat(module.vpc.public_subnet_ids, module.vpc.private_subnet_ids)
  private_subnet_ids  = module.vpc.private_subnet_ids
  
  node_instance_types = var.node_instance_types
  desired_capacity    = var.desired_capacity
  max_capacity        = var.max_capacity
  min_capacity        = var.min_capacity
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# RDS Module
module "rds" {
  source = "../../modules/rds"
  
  identifier      = "${var.project_name}-${var.environment}-postgres"
  engine_version  = var.postgres_version
  instance_class  = var.postgres_instance_class
  
  allocated_storage     = var.postgres_allocated_storage
  max_allocated_storage = var.postgres_max_allocated_storage
  
  database_name = var.postgres_database_name
  username      = var.postgres_username
  password      = random_password.rds_password.result
  
  vpc_id     = module.vpc.vpc_id
  vpc_cidr   = module.vpc.vpc_cidr_block
  subnet_ids = module.vpc.private_subnet_ids
  
  backup_retention_period = var.postgres_backup_retention
  deletion_protection     = var.postgres_deletion_protection
  final_snapshot         = var.postgres_final_snapshot
  create_replica         = var.postgres_create_replica
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# ElastiCache Module
module "elasticache" {
  source = "../../modules/elasticache"
  
  cluster_id        = "${var.project_name}-${var.environment}-redis"
  node_type         = var.redis_node_type
  num_cache_nodes   = var.redis_num_cache_nodes
  multi_az_enabled  = var.redis_multi_az_enabled
  engine_version    = var.redis_engine_version
  
  vpc_id     = module.vpc.vpc_id
  vpc_cidr   = module.vpc.vpc_cidr_block
  subnet_ids = module.vpc.private_subnet_ids
  
  auth_token = random_password.redis_auth_token.result
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}