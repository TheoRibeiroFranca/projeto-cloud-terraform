# Fluxo permitido (mesmo de Ohio, com o RDS mais fechado):
#
#   internet --80--> ALB público --portas dinâmicas--> instâncias ECS
#   instâncias ECS --80--> ALB interno --portas dinâmicas--> instâncias ECS
#   instâncias ECS --5432--> RDS
#   instâncias ECS --443--> AWS (ECR, Bedrock, SSM, CloudWatch) e internet via NAT
#
# As tasks usam o modo de rede "bridge" com portas dinâmicas, por isso o ALB
# fala com as instâncias na faixa efêmera 32768-65535.
#
# Grupos sem regras de saída ficam sem saída nenhuma: o Terraform remove a
# regra padrão "tudo liberado" que a AWS cria.

locals {
  ephemeral_from = 32768
  ephemeral_to   = 65535
}

resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb"
  description = "ALB publico: HTTP da internet"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-alb" }
}

resource "aws_security_group" "alb_internal" {
  name        = "${var.name_prefix}-alb-internal"
  description = "ALB interno: chamadas entre servicos"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-alb-internal" }
}

resource "aws_security_group" "ecs" {
  name        = "${var.name_prefix}-ecs"
  description = "Instancias do cluster ECS"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-ecs" }
}

resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds"
  description = "Postgres: so as instancias ECS"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-rds" }
}

# --- ALB público ---------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP da internet"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ecs" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Para as tasks nas instancias ECS"
  ip_protocol                  = "tcp"
  from_port                    = local.ephemeral_from
  to_port                      = local.ephemeral_to
  referenced_security_group_id = aws_security_group.ecs.id
}

# --- ALB interno ---------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "alb_internal_from_ecs" {
  security_group_id            = aws_security_group.alb_internal.id
  description                  = "HTTP vindo das tasks"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.ecs.id
}

resource "aws_vpc_security_group_egress_rule" "alb_internal_to_ecs" {
  security_group_id            = aws_security_group.alb_internal.id
  description                  = "Para as tasks nas instancias ECS"
  ip_protocol                  = "tcp"
  from_port                    = local.ephemeral_from
  to_port                      = local.ephemeral_to
  referenced_security_group_id = aws_security_group.ecs.id
}

# --- Instâncias ECS ------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  for_each = {
    alb          = aws_security_group.alb.id
    alb_internal = aws_security_group.alb_internal.id
  }

  security_group_id            = aws_security_group.ecs.id
  description                  = "Portas dinamicas vindas do ${each.key}"
  ip_protocol                  = "tcp"
  from_port                    = local.ephemeral_from
  to_port                      = local.ephemeral_to
  referenced_security_group_id = each.value
}

resource "aws_vpc_security_group_egress_rule" "ecs_to_alb_internal" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "Chamadas para o ALB interno"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.alb_internal.id
}

resource "aws_vpc_security_group_egress_rule" "ecs_to_rds" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "Postgres"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.rds.id
}

resource "aws_vpc_security_group_egress_rule" "ecs_https" {
  security_group_id = aws_security_group.ecs.id
  description       = "HTTPS para APIs da AWS e internet via NAT"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# --- RDS -----------------------------------------------------------------
# Só entrada das instâncias ECS e nenhuma saída (em Ohio, a saída está aberta).

resource "aws_vpc_security_group_ingress_rule" "rds_from_ecs" {
  security_group_id            = aws_security_group.rds.id
  description                  = "Postgres vindo das instancias ECS"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.ecs.id
}
