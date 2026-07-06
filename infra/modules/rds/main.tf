# ─────────────────────────────────────────────
# DB Subnet Group  (RDS must live in private subnets)
# ─────────────────────────────────────────────
resource "aws_db_subnet_group" "this" {
  name        = "${var.project}-${var.env}-rds-subnet-group"
  subnet_ids  = var.private_subnet_ids
  description = "Private subnet group for ${var.project} ${var.env} RDS"

  tags = merge(var.tags, { Name = "${var.project}-${var.env}-rds-subnet-group" })
}

# ─────────────────────────────────────────────
# RDS Parameter Group
# ─────────────────────────────────────────────
resource "aws_db_parameter_group" "this" {
  name        = "${var.project}-${var.env}-pg16"
  family      = "postgres16"
  description = "Custom parameter group for ${var.project} ${var.env}"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_duration"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # log queries taking > 1 s
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────────
# Secrets Manager — DB credentials
# ─────────────────────────────────────────────
resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.project}/${var.env}/rds/credentials"
  description             = "RDS master credentials for ${var.project} ${var.env}"
  recovery_window_in_days = 0 # instant delete in dev; set to 30 for prod

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = aws_db_instance.this.address
    port     = 5432
    dbname   = var.db_name
  })

  # Avoid circular dependency — update after instance is created
  depends_on = [aws_db_instance.this]
}

# ─────────────────────────────────────────────
# RDS PostgreSQL Instance
# ─────────────────────────────────────────────
resource "aws_db_instance" "this" {
  identifier = "${var.project}-${var.env}-postgres"

  engine               = "postgres"
  engine_version       = var.engine_version
  instance_class       = var.instance_class
  db_name              = var.db_name
  username             = var.db_username
  password             = var.db_password
  parameter_group_name = aws_db_parameter_group.this.name

  # Storage
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  # Network — strictly private; no public access
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.rds_sg_id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  # Backup & maintenance
  backup_retention_period   = var.backup_retention_period
  backup_window             = "03:00-04:00"
  maintenance_window        = "Mon:04:00-Mon:05:00"
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot     = true

  # Deletion safeguards
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.project}-${var.env}-final-snapshot"

  # Observability
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  performance_insights_enabled    = true
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn

  tags = merge(var.tags, { Name = "${var.project}-${var.env}-postgres" })

  lifecycle {
    prevent_destroy = false
    ignore_changes  = [password] # manage password changes via Secrets Manager rotation
  }
}

# ─────────────────────────────────────────────
# IAM Role for Enhanced Monitoring
# ─────────────────────────────────────────────
data "aws_iam_policy_document" "rds_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name               = "${var.project}-${var.env}-rds-monitoring-role"
  assume_role_policy = data.aws_iam_policy_document.rds_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
