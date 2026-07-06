terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Project     = var.project
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

# ─────────────────────────────────────────────
# Network  (VPC, subnets, IGW, NAT, SGs)
# ─────────────────────────────────────────────
module "network" {
  source = "../../modules/network"

  project  = var.project
  env      = var.env
  vpc_cidr = var.vpc_cidr
  app_port = var.app_port
  tags     = local.common_tags
}

# ─────────────────────────────────────────────
# RDS PostgreSQL
# ─────────────────────────────────────────────
module "rds" {
  source = "../../modules/rds"

  project            = var.project
  env                = var.env
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  rds_sg_id          = module.network.rds_sg_id

  db_name               = var.rds_db_name
  db_username           = var.rds_username
  db_password           = var.rds_password
  instance_class        = var.rds_instance_class
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage

  backup_retention_period = var.rds_backup_retention
  deletion_protection     = var.rds_deletion_protection
  multi_az                = var.rds_multi_az
  skip_final_snapshot     = true

  tags = local.common_tags
}

# ─────────────────────────────────────────────
# ECS / Fargate + ALB
# ─────────────────────────────────────────────
module "ecs" {
  source = "../../modules/ecs"

  project            = var.project
  env                = var.env
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  public_subnet_ids  = module.network.public_subnet_ids
  alb_sg_id          = module.network.alb_sg_id
  ecs_sg_id          = module.network.ecs_sg_id

  app_image     = var.app_image
  app_port      = var.app_port
  cpu           = var.ecs_cpu
  memory        = var.ecs_memory
  desired_count = var.ecs_desired_count

  db_host       = module.rds.db_address
  db_name       = module.rds.db_name
  db_secret_arn = module.rds.db_secret_arn

  tags = local.common_tags
}

# ─────────────────────────────────────────────
# Outputs
# ─────────────────────────────────────────────
output "alb_dns_name" {
  description = "Public ALB endpoint"
  value       = module.ecs.alb_dns_name
}

output "rds_endpoint" {
  description = "RDS connection endpoint (private)"
  value       = module.rds.db_endpoint
  sensitive   = true
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}
