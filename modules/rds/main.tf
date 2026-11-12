# Postgres do catálogo, estoque, contas e pedidos.
#
# A senha do administrador é gerada e guardada pelo próprio RDS no Secrets
# Manager (manage_master_user_password). Ela nunca passa pelo Terraform: não
# aparece no código, no plan nem no state.

resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-db"
  subnet_ids = var.subnet_ids

  tags = { Name = "${var.name_prefix}-db" }
}

resource "aws_db_instance" "this" {
  identifier = var.name_prefix

  engine                     = "postgres"
  engine_version             = var.engine_version
  auto_minor_version_upgrade = true
  instance_class             = var.instance_class

  db_name                     = var.db_name
  username                    = var.master_username
  manage_master_user_password = true

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period   = var.backup_retention_days
  copy_tags_to_snapshot     = true
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name_prefix}-final"

  apply_immediately = true

  tags = { Name = var.name_prefix }
}
