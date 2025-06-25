# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.cluster_id}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = var.tags
}

# Security Group for ElastiCache
resource "aws_security_group" "redis" {
  name_prefix = "${var.cluster_id}-redis-sg"
  vpc_id      = var.vpc_id

  ingress {
    description = "Redis"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_id}-redis-sg"
  })
}

# ElastiCache Parameter Group
resource "aws_elasticache_parameter_group" "redis" {
  family = "redis7.x"
  name   = "${var.cluster_id}-params"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  parameter {
    name  = "timeout"
    value = "300"
  }

  parameter {
    name  = "tcp-keepalive"
    value = "300"
  }

  tags = var.tags
}

# KMS key for ElastiCache encryption
resource "aws_kms_key" "redis" {
  description             = "ElastiCache encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = var.tags
}

resource "aws_kms_alias" "redis" {
  name          = "alias/${var.cluster_id}-redis"
  target_key_id = aws_kms_key.redis.key_id
}

# ElastiCache Replication Group
resource "aws_elasticache_replication_group" "main" {
  replication_group_id       = var.cluster_id
  description                = "Redis cluster for ${var.cluster_id}"
  
  node_type                  = var.node_type
  port                       = 6379
  parameter_group_name       = aws_elasticache_parameter_group.redis.name

  num_cache_clusters         = var.num_cache_nodes
  automatic_failover_enabled = var.num_cache_nodes > 1
  multi_az_enabled          = var.multi_az_enabled

  subnet_group_name = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  kms_key_id                 = aws_kms_key.redis.arn
  auth_token                 = var.auth_token

  engine_version             = var.engine_version
  auto_minor_version_upgrade = true

  maintenance_window = var.maintenance_window
  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window         = var.snapshot_window

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis.name
    destination_type = "cloudwatch-logs"
    log_format      = "json"
    log_type        = "slow-log"
  }

  tags = var.tags
}

# CloudWatch log group for Redis logs
resource "aws_cloudwatch_log_group" "redis" {
  name              = "/aws/elasticache/${var.cluster_id}"
  retention_in_days = 7

  tags = var.tags
}