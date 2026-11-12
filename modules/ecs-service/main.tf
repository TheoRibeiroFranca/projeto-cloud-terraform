# Um serviço ECS completo: log group, task definition, serviço e autoscaling.
# Usado pelos 4 serviços da aplicação, cada um com seus parâmetros.

locals {
  full_name = "${var.name_prefix}-${var.name}"
  container = "app"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "${var.log_group_prefix}/${var.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_ecs_task_definition" "this" {
  family                   = local.full_name
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name              = local.container
      image             = var.image
      essential         = true
      cpu               = var.cpu
      memory            = var.memory
      memoryReservation = var.memory_reservation
      stopTimeout       = 30

      # hostPort 0 = porta dinâmica: várias tasks do mesmo serviço cabem na
      # mesma instância, e o ECS informa a porta ao target group.
      portMappings = var.container_port == null ? [] : [
        { containerPort = var.container_port, hostPort = 0, protocol = "tcp" }
      ]

      environment = [for k in sort(keys(var.environment)) : { name = k, value = var.environment[k] }]
      secrets     = [for k in sort(keys(var.secrets)) : { name = k, valueFrom = var.secrets[k] }]

      healthCheck = {
        command     = var.health_check_command
        interval    = var.health_check_interval
        timeout     = 5
        retries     = 3
        startPeriod = var.health_check_start_period
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "this" {
  name            = local.full_name
  cluster         = var.cluster_name
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.min_tasks

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider_name
    weight            = 1
    base              = 0
  }

  # Deploy sem queda: sobe as tasks novas antes de tirar as velhas.
  # Se as novas não ficarem saudáveis, volta para a versão anterior.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Espalha as tasks entre as zonas (disponibilidade) e, dentro da zona,
  # concentra nas instâncias mais cheias de memória (menos instâncias ociosas,
  # o que deixa o Capacity Provider remover as sobras).
  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  ordered_placement_strategy {
    type  = "binpack"
    field = "memory"
  }

  availability_zone_rebalancing = "ENABLED"

  # Tempo para a aplicação subir antes do health check do ALB contar.
  health_check_grace_period_seconds = length(var.load_balancers) > 0 ? 60 : null

  dynamic "load_balancer" {
    for_each = var.load_balancers

    content {
      target_group_arn = load_balancer.value
      container_name   = local.container
      container_port   = var.container_port
    }
  }

  lifecycle {
    # O autoscaling muda o número de tasks; o Terraform não desfaz.
    ignore_changes = [desired_count]
  }
}

# --- Autoscaling de tasks -------------------------------------------------

resource "aws_appautoscaling_target" "this" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${var.cluster_name}/${aws_ecs_service.this.name}"
  min_capacity       = var.min_tasks
  max_capacity       = var.max_tasks
}

resource "aws_appautoscaling_policy" "cpu" {
  count = var.cpu_target == null ? 0 : 1

  name               = "cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  resource_id        = aws_appautoscaling_target.this.resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_target
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "requests" {
  count = var.requests_per_target == null ? 0 : 1

  name               = "requests-per-target"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  resource_id        = aws_appautoscaling_target.this.resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.requests_per_target.target
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = var.requests_per_target.resource_label
    }
  }
}

# Mensagens visíveis na fila divididas pelas tasks rodando: o worker cresce
# quando cada task tem trabalho acumulado demais.
resource "aws_appautoscaling_policy" "backlog" {
  count = var.sqs_backlog == null ? 0 : 1

  name               = "backlog-per-task"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  resource_id        = aws_appautoscaling_target.this.resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.sqs_backlog.target
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown

    customized_metric_specification {
      metrics {
        id          = "visiveis"
        return_data = false

        metric_stat {
          stat = "Average"
          metric {
            namespace   = "AWS/SQS"
            metric_name = "ApproximateNumberOfMessagesVisible"
            dimensions {
              name  = "QueueName"
              value = var.sqs_backlog.queue_name
            }
          }
        }
      }

      metrics {
        id          = "tasks"
        return_data = false

        metric_stat {
          stat = "Average"
          metric {
            namespace   = "ECS/ContainerInsights"
            metric_name = "RunningTaskCount"
            dimensions {
              name  = "ClusterName"
              value = var.cluster_name
            }
            dimensions {
              name  = "ServiceName"
              value = aws_ecs_service.this.name
            }
          }
        }
      }

      metrics {
        id          = "backlog"
        label       = "BacklogPerTask"
        expression  = "visiveis / FILL(tasks, 1)"
        return_data = true
      }
    }
  }
}
