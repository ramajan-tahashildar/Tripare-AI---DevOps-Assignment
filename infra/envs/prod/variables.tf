variable "project" {
  description = "Project name"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "app_image" {
  description = "Docker image for the application"
  type        = string
}

variable "app_port" {
  description = "Application container port"
  type        = number
}

variable "ecs_cpu" {
  description = "ECS task CPU units"
  type        = number
}

variable "ecs_memory" {
  description = "ECS task memory in MiB"
  type        = number
}

variable "ecs_desired_count" {
  description = "Number of ECS task replicas"
  type        = number
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
}

variable "rds_allocated_storage" {
  description = "RDS initial storage in GiB"
  type        = number
}

variable "rds_max_allocated_storage" {
  description = "RDS max autoscaling storage in GiB"
  type        = number
}

variable "rds_db_name" {
  description = "Database name"
  type        = string
}

variable "rds_username" {
  description = "RDS master username"
  type        = string
}

variable "rds_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "rds_backup_retention" {
  description = "Days to retain RDS automated backups"
  type        = number
}

variable "rds_deletion_protection" {
  description = "Enable RDS deletion protection"
  type        = bool
}

variable "rds_multi_az" {
  description = "Enable RDS Multi-AZ"
  type        = bool
}
