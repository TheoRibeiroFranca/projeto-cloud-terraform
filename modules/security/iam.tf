# Roles distintas, como o enunciado pede:
#   - instâncias EC2: só o necessário para entrar no cluster ECS e no SSM
#   - execução das tasks: baixar imagens, enviar logs, ler os segredos
#   - aplicação: uma role por serviço, só com o que cada um usa
#
# Os recursos ainda não existem neste módulo, então os ARNs são montados a
# partir dos nomes combinados em var.names.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account   = data.aws_caller_identity.current.account_id
  region    = data.aws_region.current.region
  partition = data.aws_partition.current.partition

  arn = {
    ecr_repos      = "arn:${local.partition}:ecr:${local.region}:${local.account}:repository/${var.names.ecr_repository_prefix}/*"
    log_groups     = "arn:${local.partition}:logs:${local.region}:${local.account}:log-group:${var.names.log_group_prefix}/*"
    ssm_param      = "arn:${local.partition}:ssm:${local.region}:${local.account}:parameter${var.names.ssm_prefix}"
    orders_queue   = "arn:${local.partition}:sqs:${local.region}:${local.account}:${var.names.orders_queue}"
    conversations  = "arn:${local.partition}:dynamodb:${local.region}:${local.account}:table/${var.names.conversations_table}"
    embedding      = "arn:${local.partition}:bedrock:${local.region}::foundation-model/${var.bedrock_embedding_model_id}"
    chat_profile   = "arn:${local.partition}:bedrock:${local.region}:${local.account}:inference-profile/${var.bedrock_chat_inference_profile}"
    chat_model_any = "arn:${local.partition}:bedrock:*::foundation-model/${var.bedrock_chat_model_id}"
    chat_model_glb = "arn:${local.partition}:bedrock:::foundation-model/${var.bedrock_chat_model_id}"
  }

  # Parâmetro que liga e desliga falhas simuladas, lido pelas aplicações.
  faults_parameter = "${local.arn.ssm_param}/faults"
}

data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "assume_ecs_tasks" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    # Só tasks desta conta podem assumir as roles.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
    }
  }
}

# =========================================================================
# 1. Instâncias EC2 do cluster
# =========================================================================

resource "aws_iam_role" "ecs_instance" {
  name               = "${var.name_prefix}-ecs-instance"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_role_policy_attachment" "ecs_instance" {
  for_each = {
    ecs = "arn:${local.partition}:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
    ssm = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  role       = aws_iam_role.ecs_instance.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "${var.name_prefix}-ecs-instance"
  role = aws_iam_role.ecs_instance.name
}

# =========================================================================
# 2. Execução das tasks (usada pelo ECS, não pelo código)
# =========================================================================
# Em vez da política gerenciada (que libera qualquer repositório e log group),
# só os repositórios, logs e segredos do projeto.

resource "aws_iam_role" "task_execution" {
  name               = "${var.name_prefix}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.assume_ecs_tasks.json
}

data "aws_iam_policy_document" "task_execution" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # esta ação não aceita recurso específico
  }

  statement {
    sid = "PullProjectImages"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [local.arn.ecr_repos]
  }

  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${local.arn.log_groups}:*"]
  }

  statement {
    sid       = "ReadRdsSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.rds_secret_arn]
  }

  # Só os parâmetros que viram variáveis de ambiente, não o caminho inteiro.
  statement {
    sid     = "ReadAppSecrets"
    actions = ["ssm:GetParameters"]
    resources = [
      "${local.arn.ssm_param}/admin_token",
      "${local.arn.ssm_param}/auth_jwt_secret",
    ]
  }
}

resource "aws_iam_role_policy" "task_execution" {
  name   = "task-execution"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution.json
}

# =========================================================================
# 3. Aplicação: uma role por serviço
# =========================================================================

data "aws_iam_policy_document" "backend_api" {
  statement {
    sid       = "PublishOrders"
    actions   = ["sqs:SendMessage", "sqs:GetQueueUrl", "sqs:GetQueueAttributes"]
    resources = [local.arn.orders_queue]
  }

  statement {
    sid       = "Embeddings"
    actions   = ["bedrock:InvokeModel"]
    resources = [local.arn.embedding]
  }

  statement {
    sid       = "ReadFaults"
    actions   = ["ssm:GetParameter"]
    resources = [local.faults_parameter]
  }
}

data "aws_iam_policy_document" "order_worker" {
  statement {
    sid = "ConsumeOrders"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:SendMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
    ]
    resources = [local.arn.orders_queue]
  }

  statement {
    sid       = "ReadFaults"
    actions   = ["ssm:GetParameter"]
    resources = [local.faults_parameter]
  }
}

data "aws_iam_policy_document" "chatbot" {
  statement {
    sid = "Conversations"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
    ]
    resources = [local.arn.conversations]
  }

  # O perfil global encaminha a chamada para o modelo em outra região,
  # por isso o modelo base aparece com região curinga.
  statement {
    sid       = "InvokeChatModel"
    actions   = ["bedrock:InvokeModel"]
    resources = [local.arn.chat_profile, local.arn.chat_model_any, local.arn.chat_model_glb]
  }

  statement {
    sid       = "ReadFaults"
    actions   = ["ssm:GetParameter"]
    resources = [local.faults_parameter]
  }
}

locals {
  app_policies = {
    backend-api  = data.aws_iam_policy_document.backend_api.json
    order-worker = data.aws_iam_policy_document.order_worker.json
    chatbot      = data.aws_iam_policy_document.chatbot.json
  }

  # O frontend só serve páginas e não chama a AWS: role sem permissões.
  app_services = concat(keys(local.app_policies), ["frontend"])
}

resource "aws_iam_role" "app" {
  for_each = toset(local.app_services)

  name               = "${var.name_prefix}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.assume_ecs_tasks.json
}

resource "aws_iam_role_policy" "app" {
  for_each = local.app_policies

  name   = "app"
  role   = aws_iam_role.app[each.key].id
  policy = each.value
}
