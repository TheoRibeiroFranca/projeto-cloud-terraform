# Passos que dependem da aplicação já estar rodando, executados pelo próprio
# apply. Assim o ambiente nasce completo, sem comandos manuais depois:
#
#   embeddings   gera os vetores da busca semântica para o catálogo
#   admin        cria a conta de administrador da loja
#
# Os dois rodam como tasks avulsas do ECS, com a task definition do
# backend-api (mesma imagem, roles e acesso ao banco). As migrations não
# precisam disto: o backend aplica sozinho ao subir.

locals {
  one_off_env = {
    REGION            = var.region
    CLUSTER           = module.ecs_cluster.cluster_name
    CAPACITY_PROVIDER = module.ecs_cluster.capacity_provider_name
    BACKEND_SERVICE   = module.backend_api.service_name
    # Família, não a revisão: a task avulsa usa a revisão mais recente.
    FAMILY = module.backend_api.task_definition_family
  }
}

# --- Embeddings ------------------------------------------------------------
# Roda de novo a cada versão nova do backend; só gera os que faltam.

resource "terraform_data" "embeddings" {
  triggers_replace = {
    task_definition = module.backend_api.task_definition_arn
  }

  provisioner "local-exec" {
    command     = <<-EOT
      aws ecs wait services-stable --region "$REGION" --cluster "$CLUSTER" --services "$BACKEND_SERVICE"
      "${path.root}/../scripts/run-task.sh" "$FAMILY" python -m app.cli embed --limit 500
    EOT
    environment = local.one_off_env
  }
}

# --- Conta de administrador ---------------------------------------------------

ephemeral "random_password" "admin" {
  length  = 24
  special = false
}

# Para ver a senha:
#   aws ssm get-parameter --region sa-east-1 --with-decryption \
#     --name /convcommerce/sp/admin_password --query Parameter.Value --output text
resource "aws_ssm_parameter" "admin_password" {
  name             = "${local.names.ssm_prefix}/admin_password"
  description      = "Senha da conta de administrador da loja (${var.admin_email})"
  type             = "SecureString"
  value_wo         = ephemeral.random_password.admin.result
  value_wo_version = 1
}

resource "terraform_data" "admin" {
  triggers_replace = {
    email = var.admin_email
  }

  provisioner "local-exec" {
    command = "${path.root}/../scripts/bootstrap-admin.sh"
    environment = merge(local.one_off_env, {
      STORE_URL                = "http://${module.alb.public_dns_name}"
      ADMIN_EMAIL              = var.admin_email
      ADMIN_NAME               = var.admin_name
      ADMIN_PASSWORD_PARAMETER = aws_ssm_parameter.admin_password.name
    })
  }
}
