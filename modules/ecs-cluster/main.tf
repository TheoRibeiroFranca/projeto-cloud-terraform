# Cluster ECS sobre EC2:
#
#   Capacity Provider ──controla──> Auto Scaling Group ──usa──> Launch Template
#          │                                │
#          └── o ECS pede mais instâncias   └── sobe instâncias que entram no
#              quando as tasks não cabem        cluster pelo user data
#
# Elasticidade em dois níveis: o autoscaling de cada serviço muda o número de
# tasks; quando elas não cabem (ou sobram instâncias), o Capacity Provider
# muda o tamanho do ASG.

# AMI otimizada para ECS, publicada pela AWS em cada região. Nenhum ID fixo:
# o mesmo código acha a AMI certa em São Paulo, Ohio ou qualquer região.
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

resource "aws_ecs_cluster" "this" {
  name = var.name_prefix

  setting {
    name  = "containerInsights"
    value = var.container_insights
  }
}

# --- Launch Template -----------------------------------------------------

resource "aws_launch_template" "ecs" {
  name          = "${var.name_prefix}-ecs"
  image_id      = data.aws_ssm_parameter.ecs_ami.insecure_value
  instance_type = var.instance_type

  iam_instance_profile {
    name = var.instance_profile_name
  }

  vpc_security_group_ids = [var.security_group_id]

  # Registra a instância no cluster. O stop timeout dá 30 s para os containers
  # terminarem as requisições quando uma task para.
  user_data = base64encode(<<-EOT
    #!/bin/bash
    cat >> /etc/ecs/ecs.config <<'CFG'
    ECS_CLUSTER=${aws_ecs_cluster.this.name}
    ECS_CONTAINER_STOP_TIMEOUT=30s
    ECS_ENABLE_CONTAINER_METADATA=true
    CFG
  EOT
  )

  # IMDSv2 obrigatório e hop limit 1: os containers (modo bridge) não alcançam
  # as credenciais da instância e só usam a role da própria task.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.name_prefix}-ecs" }
  }

  tag_specifications {
    resource_type = "volume"
    tags          = { Name = "${var.name_prefix}-ecs" }
  }
}

# --- Auto Scaling Group --------------------------------------------------

resource "aws_autoscaling_group" "ecs" {
  name                = "${var.name_prefix}-ecs"
  vpc_zone_identifier = var.subnet_ids
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity

  launch_template {
    id      = aws_launch_template.ecs.id
    version = aws_launch_template.ecs.latest_version
  }

  # Instância que falha no health check do EC2 é substituída.
  health_check_type         = "EC2"
  health_check_grace_period = 180

  # Exigido pela proteção de encerramento do Capacity Provider: o ASG não
  # encerra uma instância que ainda roda tasks; o ECS libera antes.
  protect_from_scale_in = true

  # Métricas de grupo (instâncias em serviço, pendentes...), usadas pelo
  # alarme de capacidade do ASG. Em Ohio estão desligadas.
  metrics_granularity = "1Minute"
  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
  ]

  # Permite o terraform destroy apagar o grupo mesmo com instâncias protegidas.
  force_delete = true

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-ecs"
    propagate_at_launch = true
  }

  lifecycle {
    # O Capacity Provider muda o tamanho do grupo; o Terraform não desfaz.
    ignore_changes = [desired_capacity]
  }
}

# --- Capacity Provider ---------------------------------------------------

resource "aws_ecs_capacity_provider" "ec2" {
  name = "${var.name_prefix}-ec2"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs.arn

    # Não encerra instância com tasks rodando.
    managed_termination_protection = "ENABLED"

    # Antes de encerrar uma instância, o ECS tira as tasks dela e sobe
    # substitutas em outra (drenagem), sem derrubar o serviço.
    managed_draining = "ENABLED"

    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = var.target_capacity
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 2
      instance_warmup_period    = var.instance_warmup_seconds
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = [aws_ecs_capacity_provider.ec2.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
    base              = 0
  }
}
