# Dashboard: uma tela com o estado da plataforma, de cima para baixo:
#   1. alarmes            o que está errado agora
#   2. negócio            pedidos, conversas, cotações
#   3. entrada            requisições, erros e latência do ALB
#   4. serviços           tasks rodando e CPU de cada serviço
#   5. capacidade         instâncias, reserva do cluster, Capacity Provider
#   6. fila e IA          backlog, DLQ, latência do modelo e do backend
#   7. banco              CPU e conexões do RDS

locals {
  ci  = "ECS/ContainerInsights"
  env = var.app_env

  all_alarm_arns = concat(
    [for a in aws_cloudwatch_metric_alarm.simple : a.arn],
    [for a in aws_cloudwatch_metric_alarm.tasks_missing : a.arn],
    [aws_cloudwatch_metric_alarm.asg_below_min.arn, aws_cloudwatch_metric_alarm.asg_at_max.arn],
  )

  # Atalho para um gráfico de linhas.
  graph = {
    view   = "timeSeries"
    region = var.region
    period = 60
  }

  widgets = [
    # 1. Alarmes -------------------------------------------------------------
    {
      type = "alarm", x = 0, y = 0, width = 24, height = 4
      properties = {
        title  = "Alarmes"
        alarms = local.all_alarm_arns
      }
    },

    # 2. Negócio ---------------------------------------------------------------
    {
      type = "metric", x = 0, y = 4, width = 12, height = 6
      properties = merge(local.graph, {
        title  = "Pedidos (por 5 min)"
        period = 300
        stat   = "Sum"
        metrics = [
          ["ConvCommerce", "OrdersCreated", "env", local.env, "service", "backend-api", { label = "Criados" }],
          ["ConvCommerce", "OrdersConfirmed", "env", local.env, "service", "order-worker", { label = "Confirmados" }],
          ["ConvCommerce", "OrdersPlacedByChat", "env", local.env, "service", "chatbot", { label = "Fechados pelo chat" }],
          ["ConvCommerce", "WorkerErrors", "env", local.env, "service", "order-worker", { label = "Falhas no worker" }],
        ]
      })
    },
    {
      type = "metric", x = 12, y = 4, width = 12, height = 6
      properties = merge(local.graph, {
        title  = "Conversas (por 5 min)"
        period = 300
        stat   = "Sum"
        metrics = [
          ["ConvCommerce", "ChatTurns", "env", local.env, "service", "chatbot", { label = "Mensagens no chat" }],
          ["ConvCommerce", "QuotesCreated", "env", local.env, "service", "backend-api", { label = "Cotações" }],
          ["ConvCommerce", "DegradedTurns", "env", local.env, "service", "chatbot", { label = "Respostas degradadas" }],
          ["ConvCommerce", "LLMErrors", "env", local.env, "service", "chatbot", "provider", "bedrock", { label = "Erros do Bedrock" }],
        ]
      })
    },

    # 3. Entrada (ALB público) ------------------------------------------------
    {
      type = "metric", x = 0, y = 10, width = 8, height = 6
      properties = merge(local.graph, {
        title = "Requisições por target group"
        stat  = "Sum"
        metrics = [
          for k, tg in local.public_tgs :
          ["AWS/ApplicationELB", "RequestCountPerTarget", "TargetGroup", tg.arn_suffix, { label = k }]
        ]
      })
    },
    {
      type = "metric", x = 8, y = 10, width = 8, height = 6
      properties = merge(local.graph, {
        title = "Erros 5xx"
        stat  = "Sum"
        metrics = [
          ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", var.alb_public_arn_suffix, { label = "ALB" }],
          ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_public_arn_suffix, { label = "Aplicações" }],
          ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_internal_arn_suffix, { label = "Backend (interno)" }],
        ]
      })
    },
    {
      type = "metric", x = 16, y = 10, width = 8, height = 6
      properties = merge(local.graph, {
        title = "Tempo de resposta (s)"
        metrics = [
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_public_arn_suffix, { stat = "p50", label = "p50" }],
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_public_arn_suffix, { stat = "p95", label = "p95" }],
        ]
        annotations = { horizontal = [{ value = var.alb_p95_latency_seconds, label = "Alarme p95" }] }
      })
    },

    # 4. Serviços -------------------------------------------------------------
    {
      type = "metric", x = 0, y = 16, width = 12, height = 6
      properties = merge(local.graph, {
        title = "Tasks rodando por serviço"
        stat  = "Average"
        metrics = [
          for k, svc in var.ecs_services :
          [local.ci, "RunningTaskCount", "ClusterName", var.cluster_name, "ServiceName", svc, { label = k }]
        ]
      })
    },
    {
      type = "metric", x = 12, y = 16, width = 12, height = 6
      properties = merge(local.graph, {
        title = "CPU por serviço (%)"
        stat  = "Average"
        metrics = [
          for k, svc in var.ecs_services :
          ["AWS/ECS", "CPUUtilization", "ClusterName", var.cluster_name, "ServiceName", svc, { label = k }]
        ]
      })
    },

    # 5. Capacidade -----------------------------------------------------------
    {
      type = "metric", x = 0, y = 22, width = 8, height = 6
      properties = merge(local.graph, {
        title = "Instâncias do ASG"
        stat  = "Average"
        metrics = [
          ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", var.asg_name, { label = "Em serviço" }],
          ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", var.asg_name, { label = "Desejadas" }],
          ["AWS/AutoScaling", "GroupMaxSize", "AutoScalingGroupName", var.asg_name, { label = "Máximo" }],
        ]
      })
    },
    {
      type = "metric", x = 8, y = 22, width = 8, height = 6
      properties = merge(local.graph, {
        title = "Reserva do cluster (%)"
        stat  = "Average"
        metrics = [
          ["AWS/ECS", "CPUReservation", "ClusterName", var.cluster_name, { label = "CPU reservada" }],
          ["AWS/ECS", "MemoryReservation", "ClusterName", var.cluster_name, { label = "Memória reservada" }],
          ["AWS/ECS", "CPUUtilization", "ClusterName", var.cluster_name, { label = "CPU usada" }],
        ]
      })
    },
    {
      type = "metric", x = 16, y = 22, width = 8, height = 6
      properties = merge(local.graph, {
        title = "Capacity Provider (%)"
        stat  = "Average"
        metrics = [
          ["AWS/ECS/ManagedScaling", "CapacityProviderReservation", "ClusterName", var.cluster_name, "CapacityProviderName", var.capacity_provider_name, { label = "Ocupação pedida" }],
        ]
        annotations = { horizontal = [{ value = 90, label = "Alvo" }] }
      })
    },

    # 6. Fila e IA ------------------------------------------------------------
    {
      type = "metric", x = 0, y = 28, width = 12, height = 6
      properties = merge(local.graph, {
        title = "Fila de pedidos"
        stat  = "Maximum"
        metrics = [
          ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.orders_queue_name, { label = "Esperando" }],
          ["AWS/SQS", "ApproximateNumberOfMessagesNotVisible", "QueueName", var.orders_queue_name, { label = "Em processamento" }],
          ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.orders_dlq_name, { label = "Na DLQ" }],
        ]
      })
    },
    {
      type = "metric", x = 12, y = 28, width = 12, height = 6
      properties = merge(local.graph, {
        title = "Latência das dependências (ms, p95)"
        stat  = "p95"
        metrics = [
          ["ConvCommerce", "LLMLatency", "env", local.env, "service", "chatbot", "provider", "bedrock", { label = "Bedrock (chat)" }],
          ["ConvCommerce", "EmbeddingLatency", "env", local.env, "service", "backend-api", { label = "Titan (embeddings)" }],
          ["ConvCommerce", "OrderProcessingLatency", "env", local.env, "service", "order-worker", { label = "Pedido na fila até confirmar" }],
        ]
      })
    },

    # 7. Banco ----------------------------------------------------------------
    {
      type = "metric", x = 0, y = 34, width = 24, height = 5
      properties = merge(local.graph, {
        title = "Postgres"
        stat  = "Average"
        metrics = [
          ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.rds_identifier, { label = "CPU (%)" }],
          ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.rds_identifier, { label = "Conexões", yAxis = "right" }],
        ]
      })
    },
  ]
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = var.name_prefix
  dashboard_body = jsonencode({ widgets = local.widgets })
}
