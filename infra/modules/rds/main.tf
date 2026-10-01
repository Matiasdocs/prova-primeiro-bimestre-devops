resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-private"
  subnet_ids = var.private_subnet_ids
  tags       = { Name = "${var.name}-db-subnets" }
}
resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name}-"
  family      = "postgres16"
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
  tags = { Name = "${var.name}-postgres16" }
}
resource "aws_db_instance" "this" {
  identifier                   = var.name
  engine                       = "postgres"
  engine_version               = "16"
  instance_class               = "db.t3.micro"
  allocated_storage            = 20
  storage_type                 = "gp3"
  storage_encrypted            = true
  db_name                      = "reservas"
  username                     = "reservas_app"
  password                     = var.db_password
  port                         = 5432
  db_subnet_group_name         = aws_db_subnet_group.this.name
  vpc_security_group_ids       = [var.security_group_id]
  parameter_group_name         = aws_db_parameter_group.this.name
  publicly_accessible          = false
  multi_az                     = false
  auto_minor_version_upgrade   = true
  backup_retention_period      = 0
  delete_automated_backups     = true
  deletion_protection          = false
  skip_final_snapshot          = true
  apply_immediately            = true
  performance_insights_enabled = false
  monitoring_interval          = 0
  copy_tags_to_snapshot        = true
  tags                         = { Name = "${var.name}-rds" }
}
