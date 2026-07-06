variable "project" {
  description = "Project name"
  type        = string
}

variable "env" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for ALB"
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security group ID for the ALB"
  type        = string
}

variable "ecs_sg_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "app_image" {
  description = "Docker image for the application container"
  type        = string
  default     = "nginx:stable-alpine"
}

variable "app_port" {
  description = "Port the application container exposes"
  type        = number
  default     = 80
}

variable "cpu" {
  description = "Fargate task CPU units (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate task memory in MiB"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of ECS task replicas"
  type        = number
  default     = 1
}

variable "db_host" {
  description = "RDS endpoint passed to the container as an env var"
  type        = string
  default     = ""
}

variable "db_name" {
  description = "Database name passed to the container"
  type        = string
  default     = ""
}

variable "db_secret_arn" {
  description = "Secrets Manager ARN holding DB credentials"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
