variable "ssm_prefix" {
  description = "Caminho dos parâmetros no SSM (ex.: /convcommerce/sp)."
  type        = string
}

variable "secrets_version" {
  description = <<-EOT
    Aumente este número para gerar valores novos para os segredos (rotação).
    Enquanto ele não muda, os valores ficam como estão.
  EOT
  type        = number
  default     = 1
}

# --- Segredos gerados ----------------------------------------------------
# Recursos "ephemeral" e argumentos "_wo" (write-only): o valor é gerado,
# enviado para o SSM e descartado. Não fica no código, no plan nem no state.

ephemeral "random_password" "auth_jwt_secret" {
  length  = 64
  special = false
}

ephemeral "random_password" "admin_token" {
  length  = 48
  special = false
}

resource "aws_ssm_parameter" "auth_jwt_secret" {
  name             = "${var.ssm_prefix}/auth_jwt_secret"
  description      = "Chave que assina as sessões de login"
  type             = "SecureString"
  value_wo         = ephemeral.random_password.auth_jwt_secret.result
  value_wo_version = var.secrets_version
}

resource "aws_ssm_parameter" "admin_token" {
  name             = "${var.ssm_prefix}/admin_token"
  description      = "Token das rotas administrativas"
  type             = "SecureString"
  value_wo         = ephemeral.random_password.admin_token.result
  value_wo_version = var.secrets_version
}

# --- Falhas simuladas ----------------------------------------------------
# Começa tudo desligado. Nas demonstrações, o valor é mudado na hora (console
# ou CLI); o Terraform não desfaz essa mudança no próximo apply.

resource "aws_ssm_parameter" "faults" {
  name        = "${var.ssm_prefix}/faults"
  description = "Liga e desliga falhas simuladas nas aplicacoes"
  type        = "String"
  value = jsonencode({
    llm_error_rate    = 0
    llm_delay_ms      = 0
    worker_error_rate = 0
    worker_delay_ms   = 0
    db_error_rate     = 0
  })

  lifecycle {
    ignore_changes = [value]
  }
}

output "parameter_arns" {
  description = "ARNs dos parâmetros."
  value = {
    auth_jwt_secret = aws_ssm_parameter.auth_jwt_secret.arn
    admin_token     = aws_ssm_parameter.admin_token.arn
    faults          = aws_ssm_parameter.faults.arn
  }
}

output "faults_parameter_name" {
  description = "Nome do parâmetro de falhas (FAULTS_PARAMETER das aplicações)."
  value       = aws_ssm_parameter.faults.name
}
