output "cluster_name" {
  description = "Nome do cluster ECS."
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ARN do cluster ECS."
  value       = aws_ecs_cluster.this.arn
}

# Os serviços só podem usar o Capacity Provider depois de ele estar ligado ao
# cluster, e precisam ser apagados antes de ele ser desligado (no destroy).
output "capacity_provider_name" {
  description = "Capacity Provider, usado na estratégia de cada serviço."
  value       = aws_ecs_capacity_provider.ec2.name

  depends_on = [aws_ecs_cluster_capacity_providers.this]
}

output "asg_name" {
  description = "Auto Scaling Group das instâncias."
  value       = aws_autoscaling_group.ecs.name
}

output "ami_id" {
  description = "AMI do ECS escolhida para esta região."
  value       = data.aws_ssm_parameter.ecs_ami.insecure_value
}
