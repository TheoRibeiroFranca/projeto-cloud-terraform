variable "name_prefix" {
  description = "Prefixo dos nomes dos recursos (ex.: convcommerce-sp)."
  type        = string
}

variable "vpc_id" {
  description = "VPC dos target groups."
  type        = string
}

variable "public_subnet_ids" {
  description = "Subnets do ALB público."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Subnets do ALB interno."
  type        = list(string)
}

variable "public_security_group_id" {
  description = "Security group do ALB público."
  type        = string
}

variable "internal_security_group_id" {
  description = "Security group do ALB interno."
  type        = string
}

# Dois load balancers, como em Ohio:
#
#   ALB público (internet, porta 80)
#     /api/admin*                     -> 403 (rotas de administração não ficam expostas)
#     /api/chat*, /api/conversations* -> chatbot
#     /api/*                          -> backend-api
#     todo o resto                    -> frontend
#
#   ALB interno (só dentro da VPC)
#     tudo -> backend-api   (o chatbot chama o backend por aqui)
#
# Target groups do tipo "instance": as tasks rodam em modo bridge com portas
# dinâmicas, e o ECS registra cada task com a porta que ela recebeu.

locals {
  target_groups = {
    frontend    = { port = 8080, internal = false }
    backend     = { port = 8000, internal = false }
    chatbot     = { port = 8000, internal = false }
    backend-int = { port = 8000, internal = true }
  }
}

resource "aws_lb" "public" {
  name               = "${var.name_prefix}-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [var.public_security_group_id]

  # Descarta cabeçalhos HTTP malformados antes de chegarem às aplicações.
  drop_invalid_header_fields = true
}

resource "aws_lb" "internal" {
  name               = "${var.name_prefix}-internal"
  load_balancer_type = "application"
  internal           = true
  subnets            = var.private_subnet_ids
  security_groups    = [var.internal_security_group_id]

  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "this" {
  for_each = local.target_groups

  name        = "${var.name_prefix}-${each.key}"
  vpc_id      = var.vpc_id
  target_type = "instance"
  protocol    = "HTTP"
  port        = each.value.port

  # Ao tirar uma task (deploy, drenagem), o ALB espera 30 s as requisições
  # em andamento terminarem.
  deregistration_delay = 30

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# --- ALB público ---------------------------------------------------------

resource "aws_lb_listener" "public_http" {
  load_balancer_arn = aws_lb.public.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this["frontend"].arn
  }
}

resource "aws_lb_listener_rule" "block_admin" {
  listener_arn = aws_lb_listener.public_http.arn
  priority     = 10

  condition {
    path_pattern {
      values = ["/api/admin*"]
    }
  }

  action {
    type = "fixed-response"

    fixed_response {
      content_type = "application/json"
      status_code  = "403"
      message_body = jsonencode({ detail = "admin indisponivel publicamente" })
    }
  }
}

resource "aws_lb_listener_rule" "chatbot" {
  listener_arn = aws_lb_listener.public_http.arn
  priority     = 20

  condition {
    path_pattern {
      values = ["/api/chat*", "/api/conversations*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this["chatbot"].arn
  }
}

resource "aws_lb_listener_rule" "backend" {
  listener_arn = aws_lb_listener.public_http.arn
  priority     = 30

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this["backend"].arn
  }
}

# --- ALB interno ---------------------------------------------------------

resource "aws_lb_listener" "internal_http" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this["backend-int"].arn
  }
}

# --- Saídas --------------------------------------------------------------

# O ECS só aceita um target group que já esteja ligado a um load balancer;
# o depends_on faz os serviços esperarem os listeners e as regras.
output "target_group_arns" {
  description = "ARN de cada target group."
  value       = { for k, tg in aws_lb_target_group.this : k => tg.arn }

  depends_on = [
    aws_lb_listener.public_http,
    aws_lb_listener.internal_http,
    aws_lb_listener_rule.chatbot,
    aws_lb_listener_rule.backend,
  ]
}

# Rótulos usados pela métrica "requisições por target" do autoscaling.
output "request_count_labels" {
  description = "Rótulo app/.../targetgroup/... de cada target group, no ALB que de fato o serve."
  # Cada rótulo tem de apontar para o ALB que recebe o tráfego daquele target
  # group. Antes este output só cobria os públicos e colava todos ao ALB
  # público — então a política do backend-api vigiava o target group público,
  # que recebe ~0,1 requisição por minuto, enquanto o tráfego real (590-632
  # req/alvo/min) entra pelo ALB interno, vindo do chatbot. A política nunca
  # disparava e o serviço escalava só por CPU, por acidente. Medido em Ohio
  # em 17/11/2026; ver docs/evidencias/ohio/ANALISE.md no repo do backend.
  value = {
    for k, tg in aws_lb_target_group.this :
    k => "${local.target_groups[k].internal ? aws_lb.internal.arn_suffix : aws_lb.public.arn_suffix}/${tg.arn_suffix}"
  }
}

output "public_dns_name" {
  description = "Endereço público da loja."
  value       = aws_lb.public.dns_name
}

output "internal_dns_name" {
  description = "Endereço do ALB interno (BACKEND_URL do chatbot)."
  value       = aws_lb.internal.dns_name
}

output "public_arn_suffix" {
  description = "Sufixo do ARN do ALB público (métricas do CloudWatch)."
  value       = aws_lb.public.arn_suffix
}

output "internal_arn_suffix" {
  description = "Sufixo do ARN do ALB interno (métricas do CloudWatch)."
  value       = aws_lb.internal.arn_suffix
}

output "target_group_arn_suffixes" {
  description = "Sufixo do ARN de cada target group (métricas do CloudWatch)."
  value       = { for k, tg in aws_lb_target_group.this : k => tg.arn_suffix }
}
