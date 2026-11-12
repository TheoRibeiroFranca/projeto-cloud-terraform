output "service_name" {
  description = "Nome do serviço ECS."
  value       = aws_ecs_service.this.name
}

output "log_group_name" {
  description = "Log group do serviço."
  value       = aws_cloudwatch_log_group.this.name
}

output "task_definition_family" {
  description = "Família da task definition (para tasks avulsas)."
  value       = aws_ecs_task_definition.this.family
}

output "task_definition_arn" {
  description = "Revisão atual da task definition."
  value       = aws_ecs_task_definition.this.arn
}
