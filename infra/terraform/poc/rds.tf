# RDS PostgreSQL for the Temporal server (persistence + advanced visibility,
# so no OpenSearch/Cassandra needed). Hand-rolled rather than via a module so
# the moving parts are visible for learning.

resource "random_password" "db" {
  length  = 24
  special = false # keep it URL/DSN-safe for Temporal config
}

resource "aws_db_subnet_group" "temporal" {
  name       = "${local.name}-temporal"
  subnet_ids = module.vpc.private_subnets
  tags       = local.common_tags
}

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds"
  description = "Allow Postgres from EKS nodes only"
  vpc_id      = module.vpc.vpc_id
  tags        = local.common_tags
}

resource "aws_security_group_rule" "rds_from_nodes" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = module.eks.node_security_group_id
  description              = "Postgres from EKS worker nodes"
}

resource "aws_db_instance" "temporal" {
  identifier     = "${local.name}-temporal"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = "temporal"
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.temporal.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  multi_az               = false
  publicly_accessible    = false

  # POC conveniences: fast, cheap teardown.
  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true

  tags = local.common_tags
}

# Stash the full connection info so the Temporal Helm release (Phase 2) and any
# debugging can read it without exposing the password in plan output.
resource "aws_secretsmanager_secret" "db" {
  name = "${local.name}/temporal-db"
  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    host     = aws_db_instance.temporal.address
    port     = aws_db_instance.temporal.port
    username = aws_db_instance.temporal.username
    password = random_password.db.result
    dbname   = aws_db_instance.temporal.db_name
  })
}
