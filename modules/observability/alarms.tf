# Alarmes exigidos pelo enunciado, todos avisando o tópico SNS:
#
#   saúde das tasks           tasks rodando < desejadas; targets doentes no ALB
#   utilização do cluster     CPU, memória reservada, falta de capacidade
#   capacidade do ASG         instâncias abaixo do mínimo; grupo no máximo
#   respostas do ALB          erros 5xx do ALB e das tasks; latência p95
#   profundidade das filas    mensagens acumuladas, mensagem antiga, DLQ
#   falhas da aplicação       métricas próprias (namespace ConvCommerce)
#   banco                     CPU e disco do RDS
#
# A maioria é um alarme simples (uma métrica, um limite). Os que comparam duas
# métricas (rodando x desejado, em serviço x mínimo) usam metric math.

locals {
  alarm_actions = [aws_sns_topic.alarms.arn]

  public_tgs   = { for k, tg in var.target_groups : k => tg if !tg.internal }
  internal_tgs = { for k, tg in var.target_groups : k => tg if tg.internal }

  app_dims = { env = var.app_env }

  # nome => configuração. period em segundos; avaliado em `periods` períodos
  # seguidos. missing = como tratar ausência de dados.
  simple_alarms = merge(
    # --- saúde das tasks: targets doentes ---------------------------------
    {
      for k, tg in var.target_groups : "tg-${k}-unhealthy" => {
        description = "Target group ${k}: há tasks falhando no health check do ALB."
        namespace   = "AWS/ApplicationELB"
        metric      = "UnHealthyHostCount"
        dimensions = {
          TargetGroup  = tg.arn_suffix
          LoadBalancer = tg.internal ? var.alb_internal_arn_suffix : var.alb_public_arn_suffix
        }
        stat       = "Maximum"
        comparison = "GreaterThanThreshold"
        threshold  = 0
        period     = 60
        periods    = 3
        missing    = "notBreaching"
      }
    },

    # --- utilização do cluster --------------------------------------------
    {
      "cluster-cpu-high" = {
        description = "CPU média do cluster acima de 80% por 10 minutos."
        namespace   = "AWS/ECS"
        metric      = "CPUUtilization"
        dimensions  = { ClusterName = var.cluster_name }
        stat        = "Average"
        comparison  = "GreaterThanThreshold"
        threshold   = 80
        period      = 300
        periods     = 2
        missing     = "missing"
      }
      "cluster-memory-reservation-high" = {
        description = "Mais de 90% da memória do cluster reservada: tasks novas podem não caber."
        namespace   = "AWS/ECS"
        metric      = "MemoryReservation"
        dimensions  = { ClusterName = var.cluster_name }
        stat        = "Average"
        comparison  = "GreaterThanThreshold"
        threshold   = 90
        period      = 300
        periods     = 2
        missing     = "missing"
      }
      # Acima de 100 = as tasks pedem mais capacidade do que existe. Normal por
      # alguns minutos (o ASG está subindo instâncias); por 15 min, o grupo
      # chegou ao máximo ou as instâncias não estão entrando no cluster.
      "cluster-capacity-insufficient" = {
        description = "Capacity Provider pede mais instâncias do que consegue há 15 minutos."
        namespace   = "AWS/ECS/ManagedScaling"
        metric      = "CapacityProviderReservation"
        dimensions = {
          ClusterName          = var.cluster_name
          CapacityProviderName = var.capacity_provider_name
        }
        stat       = "Average"
        comparison = "GreaterThanThreshold"
        threshold  = 100
        period     = 300
        periods    = 3
        missing    = "missing"
      }
    },

    # --- respostas do ALB -------------------------------------------------
    {
      "alb-public-elb-5xx" = {
        description = "ALB público devolveu mais de 10 erros 5xx próprios em 5 minutos (sem task saudável, timeout)."
        namespace   = "AWS/ApplicationELB"
        metric      = "HTTPCode_ELB_5XX_Count"
        dimensions  = { LoadBalancer = var.alb_public_arn_suffix }
        stat        = "Sum"
        comparison  = "GreaterThanThreshold"
        threshold   = 10
        period      = 300
        periods     = 1
        missing     = "notBreaching"
      }
      "alb-public-target-5xx" = {
        description = "As aplicações responderam mais de 10 erros 5xx em 5 minutos."
        namespace   = "AWS/ApplicationELB"
        metric      = "HTTPCode_Target_5XX_Count"
        dimensions  = { LoadBalancer = var.alb_public_arn_suffix }
        stat        = "Sum"
        comparison  = "GreaterThanThreshold"
        threshold   = 10
        period      = 300
        periods     = 1
        missing     = "notBreaching"
      }
      "alb-internal-5xx" = {
        description = "O backend respondeu mais de 10 erros 5xx ao chatbot em 5 minutos (ALB interno)."
        namespace   = "AWS/ApplicationELB"
        metric      = "HTTPCode_Target_5XX_Count"
        dimensions  = { LoadBalancer = var.alb_internal_arn_suffix }
        stat        = "Sum"
        comparison  = "GreaterThanThreshold"
        threshold   = 10
        period      = 300
        periods     = 1
        missing     = "notBreaching"
      }
      "alb-public-latency-p95" = {
        description = "Tempo de resposta p95 do ALB público acima de ${var.alb_p95_latency_seconds} s por 10 minutos."
        namespace   = "AWS/ApplicationELB"
        metric      = "TargetResponseTime"
        dimensions  = { LoadBalancer = var.alb_public_arn_suffix }
        stat        = "p95"
        comparison  = "GreaterThanThreshold"
        threshold   = var.alb_p95_latency_seconds
        period      = 300
        periods     = 2
        missing     = "notBreaching"
      }
    },

    # --- profundidade das filas -------------------------------------------
    {
      "orders-queue-backlog" = {
        description = "Mais de 100 pedidos esperando na fila por 10 minutos: o worker não está dando conta."
        namespace   = "AWS/SQS"
        metric      = "ApproximateNumberOfMessagesVisible"
        dimensions  = { QueueName = var.orders_queue_name }
        stat        = "Maximum"
        comparison  = "GreaterThanThreshold"
        threshold   = 100
        period      = 300
        periods     = 2
        missing     = "notBreaching"
      }
      "orders-queue-oldest-message" = {
        description = "Há pedido esperando há mais de 5 minutos na fila."
        namespace   = "AWS/SQS"
        metric      = "ApproximateAgeOfOldestMessage"
        dimensions  = { QueueName = var.orders_queue_name }
        stat        = "Maximum"
        comparison  = "GreaterThanThreshold"
        threshold   = 300
        period      = 60
        periods     = 5
        missing     = "notBreaching"
      }
      "orders-dlq-not-empty" = {
        description = "Pedido foi para a DLQ depois de 3 tentativas: precisa de análise."
        namespace   = "AWS/SQS"
        metric      = "ApproximateNumberOfMessagesVisible"
        dimensions  = { QueueName = var.orders_dlq_name }
        stat        = "Maximum"
        comparison  = "GreaterThanThreshold"
        threshold   = 0
        period      = 60
        periods     = 1
        missing     = "notBreaching"
      }
    },

    # --- falhas da aplicação (métricas próprias) ---------------------------
    # As métricas só existem quando o erro acontece: sem dados = sem erro.
    {
      "app-worker-errors" = {
        description = "order-worker: mais de 3 falhas ao processar pedidos em 5 minutos."
        namespace   = "ConvCommerce"
        metric      = "WorkerErrors"
        dimensions  = merge(local.app_dims, { service = "order-worker" })
        stat        = "Sum"
        comparison  = "GreaterThanThreshold"
        threshold   = 3
        period      = 300
        periods     = 1
        missing     = "notBreaching"
      }
      "app-worker-loop-errors" = {
        description = "order-worker: o loop de leitura da fila está falhando."
        namespace   = "ConvCommerce"
        metric      = "WorkerLoopErrors"
        dimensions  = merge(local.app_dims, { service = "order-worker" })
        stat        = "Sum"
        comparison  = "GreaterThanThreshold"
        threshold   = 0
        period      = 300
        periods     = 1
        missing     = "notBreaching"
      }
      "app-llm-errors" = {
        description = "chatbot: mais de 3 erros na chamada ao Bedrock em 5 minutos."
        namespace   = "ConvCommerce"
        metric      = "LLMErrors"
        dimensions  = merge(local.app_dims, { service = "chatbot", provider = "bedrock" })
        stat        = "Sum"
        comparison  = "GreaterThanThreshold"
        threshold   = 3
        period      = 300
        periods     = 1
        missing     = "notBreaching"
      }
      "app-chat-degraded" = {
        description = "chatbot: mais de 3 respostas degradadas (modelo ou backend fora) em 5 minutos."
        namespace   = "ConvCommerce"
        metric      = "DegradedTurns"
        dimensions  = merge(local.app_dims, { service = "chatbot" })
        stat        = "Sum"
        comparison  = "GreaterThanThreshold"
        threshold   = 3
        period      = 300
        periods     = 1
        missing     = "notBreaching"
      }
      "app-backend-errors" = {
        description = "chatbot: mais de 3 falhas ao chamar o backend em 5 minutos."
        namespace   = "ConvCommerce"
        metric      = "BackendErrors"
        dimensions  = merge(local.app_dims, { service = "chatbot" })
        stat        = "Sum"
        comparison  = "GreaterThanThreshold"
        threshold   = 3
        period      = 300
        periods     = 1
        missing     = "notBreaching"
      }
      "app-embedding-errors" = {
        description = "backend-api: mais de 5 falhas ao gerar embeddings em 5 minutos (busca semântica degradada)."
        namespace   = "ConvCommerce"
        metric      = "EmbeddingErrors"
        dimensions  = merge(local.app_dims, { service = "backend-api" })
        stat        = "Sum"
        comparison  = "GreaterThanThreshold"
        threshold   = 5
        period      = 300
        periods     = 1
        missing     = "notBreaching"
      }
    },

    # --- banco ------------------------------------------------------------
    {
      "rds-cpu-high" = {
        description = "CPU do Postgres acima de 80% por 10 minutos."
        namespace   = "AWS/RDS"
        metric      = "CPUUtilization"
        dimensions  = { DBInstanceIdentifier = var.rds_identifier }
        stat        = "Average"
        comparison  = "GreaterThanThreshold"
        threshold   = 80
        period      = 300
        periods     = 2
        missing     = "missing"
      }
      "rds-storage-low" = {
        description = "Menos de 2 GB livres no disco do Postgres."
        namespace   = "AWS/RDS"
        metric      = "FreeStorageSpace"
        dimensions  = { DBInstanceIdentifier = var.rds_identifier }
        stat        = "Minimum"
        comparison  = "LessThanThreshold"
        threshold   = 2 * 1024 * 1024 * 1024
        period      = 300
        periods     = 1
        missing     = "missing"
      }
    },
  )
}

resource "aws_cloudwatch_metric_alarm" "simple" {
  for_each = local.simple_alarms

  alarm_name          = "${var.name_prefix}-${each.key}"
  alarm_description   = each.value.description
  namespace           = each.value.namespace
  metric_name         = each.value.metric
  dimensions          = each.value.dimensions
  statistic           = startswith(each.value.stat, "p") ? null : each.value.stat
  extended_statistic  = startswith(each.value.stat, "p") ? each.value.stat : null
  comparison_operator = each.value.comparison
  threshold           = each.value.threshold
  period              = each.value.period
  evaluation_periods  = each.value.periods
  treat_missing_data  = each.value.missing

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

# --- saúde das tasks: rodando x desejadas (Container Insights) ------------
# Dispara se, por 3 minutos, um serviço tem menos tasks rodando do que deveria
# (tasks caindo em loop, sem capacidade, imagem que não sobe).

resource "aws_cloudwatch_metric_alarm" "tasks_missing" {
  for_each = var.ecs_services

  alarm_name          = "${var.name_prefix}-${each.key}-tasks-missing"
  alarm_description   = "${each.key}: menos tasks rodando do que o desejado há 3 minutos."
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = 3
  treat_missing_data  = "breaching" # sem métrica = serviço sem nenhuma task

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions

  metric_query {
    id          = "missing"
    expression  = "desired - running"
    label       = "Tasks faltando"
    return_data = true
  }

  metric_query {
    id = "desired"
    metric {
      namespace   = "ECS/ContainerInsights"
      metric_name = "DesiredTaskCount"
      dimensions  = { ClusterName = var.cluster_name, ServiceName = each.value }
      stat        = "Average"
      period      = 60
    }
  }

  metric_query {
    id = "running"
    metric {
      namespace   = "ECS/ContainerInsights"
      metric_name = "RunningTaskCount"
      dimensions  = { ClusterName = var.cluster_name, ServiceName = each.value }
      stat        = "Average"
      period      = 60
    }
  }
}

# --- capacidade do ASG ----------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "asg_below_min" {
  alarm_name          = "${var.name_prefix}-asg-below-min"
  alarm_description   = "Menos instâncias em serviço do que o mínimo do ASG há 5 minutos (instância perdida e não reposta)."
  comparison_operator = "LessThanThreshold"
  threshold           = 0
  evaluation_periods  = 5
  treat_missing_data  = "breaching"

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions

  metric_query {
    id          = "margin"
    expression  = "in_service - min_size"
    label       = "Instâncias acima do mínimo"
    return_data = true
  }

  metric_query {
    id = "in_service"
    metric {
      namespace   = "AWS/AutoScaling"
      metric_name = "GroupInServiceInstances"
      dimensions  = { AutoScalingGroupName = var.asg_name }
      stat        = "Average"
      period      = 60
    }
  }

  metric_query {
    id = "min_size"
    metric {
      namespace   = "AWS/AutoScaling"
      metric_name = "GroupMinSize"
      dimensions  = { AutoScalingGroupName = var.asg_name }
      stat        = "Average"
      period      = 60
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "asg_at_max" {
  alarm_name          = "${var.name_prefix}-asg-at-max"
  alarm_description   = "ASG no máximo de instâncias há 15 minutos: não há mais para onde crescer."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 0
  evaluation_periods  = 3
  treat_missing_data  = "notBreaching"

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions

  metric_query {
    id          = "over"
    expression  = "in_service - max_size"
    label       = "Instâncias acima do máximo"
    return_data = true
  }

  metric_query {
    id = "in_service"
    metric {
      namespace   = "AWS/AutoScaling"
      metric_name = "GroupInServiceInstances"
      dimensions  = { AutoScalingGroupName = var.asg_name }
      stat        = "Average"
      period      = 300
    }
  }

  metric_query {
    id = "max_size"
    metric {
      namespace   = "AWS/AutoScaling"
      metric_name = "GroupMaxSize"
      dimensions  = { AutoScalingGroupName = var.asg_name }
      stat        = "Average"
      period      = 300
    }
  }
}
